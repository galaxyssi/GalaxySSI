import Darwin
import Foundation

struct AgentIOSProjectionDestination {
  let url: URL
  private let baseline: String?
  init(_ url: URL, expected: String? = nil) throws {
    self.url = url
    baseline = try Self.fingerprint(url)
    if let expected, let baseline, expected != baseline { throw AgentKnowledgeDatabaseError.staleCursor }
  }
  func publish(_ staged: URL) throws {
    try Task.checkCancellation()
    var coordination: NSError?, failure: Error?, coordinated = false
    NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordination) { target in
      coordinated = true
      do {
        try Task.checkCancellation()
        guard target.standardizedFileURL == url.standardizedFileURL,
              try Self.fingerprint(target) == baseline else { throw AgentKnowledgeDatabaseError.staleCursor }
        try Task.checkCancellation()
        if baseline != nil { _ = try FileManager.default.replaceItemAt(target, withItemAt: staged) }
        else { try FileManager.default.moveItem(at: staged, to: target) }
      } catch { failure = error }
    }
    if let failure { throw failure }
    if let coordination { throw coordination }
    guard coordinated else { throw AgentKnowledgeDatabaseError.unavailable }
  }
  func stage(job: String) throws -> URL {
    try Task.checkCancellation()
    let stage = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(job).tmp")
    let fd = Darwin.open(stage.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    Darwin.close(fd)
    do { try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete, .posixPermissions: 0o600], ofItemAtPath: stage.path) }
    catch { try? FileManager.default.removeItem(at: stage); throw error }
    return stage
  }
  func publish(_ data: Data, job: String) throws {
    let staged = try stage(job: job)
    defer { try? FileManager.default.removeItem(at: staged) }
    let file = try FileHandle(forWritingTo: staged)
    do { try file.write(contentsOf: data); try file.synchronize(); try file.close() }
    catch { try? file.close(); throw error }
    try publish(staged)
  }
  private static func fingerprint(_ url: URL) throws -> String? {
    var info = stat()
    if Darwin.lstat(url.path, &info) != 0 {
      if errno == ENOENT { return nil }
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    return try AgentIOSObsidianTextScan.read(url, maximumUTF16: 0).hash
  }
}
