import Darwin
import Foundation

// A dedicated private namespace, descriptor-relative disposal and per-job flock
// keep a sweep from deleting another live export or following unknown children.
final class AgentKnowledgeProjectionLease {
  let id: String
  let parent: URL
  let directory: URL
  var databaseURL: URL { directory.appendingPathComponent("order.sqlite") }
  private var parentFD: Int32 = -1, directoryFD: Int32 = -1, leaseFD: Int32 = -1
  private var created = false, closed = false
  private static let files: Set<String> = [".lease", "order.sqlite", "order.sqlite-journal", "order.sqlite-wal", "order.sqlite-shm"]

  init(parent: URL = FileManager.default.temporaryDirectory.appendingPathComponent("galaxyssi-knowledge-projection-v2", isDirectory: true)) throws {
    let id = UUID().uuidString.lowercased()
    self.id = id; self.parent = parent; directory = parent.appendingPathComponent("job-" + id, isDirectory: true)
    do {
      if Darwin.mkdir(parent.path, 0o700) != 0 && errno != EEXIST { throw Self.posix() }
      parentFD = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard parentFD >= 0 else { throw Self.posix() }
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete, .posixPermissions: 0o700], ofItemAtPath: parent.path)
      try withParentLock {
        try sweep()
        guard Darwin.mkdirat(parentFD, directory.lastPathComponent, 0o700) == 0 else { throw Self.posix() }
        created = true
        directoryFD = Darwin.openat(parentFD, directory.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { throw Self.posix() }
        leaseFD = Darwin.openat(directoryFD, ".lease", O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard leaseFD >= 0, Darwin.flock(leaseFD, LOCK_EX | LOCK_NB) == 0 else { throw Self.posix() }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete, .posixPermissions: 0o700], ofItemAtPath: directory.path)
        let file = Darwin.openat(directoryFD, "order.sqlite", O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw Self.posix() }
        Darwin.close(file)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete, .posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
      }
    } catch { close(); throw error }
  }
  deinit { close() }
  func close() {
    guard !closed else { return }; closed = true
    if created, parentFD >= 0 {
      try? withParentLock(cleaning: true) { try dispose(directory.lastPathComponent, fd: directoryFD) }
    }
    if leaseFD >= 0 { Darwin.close(leaseFD); leaseFD = -1 }
    if directoryFD >= 0 { Darwin.close(directoryFD); directoryFD = -1 }
    if parentFD >= 0 { Darwin.close(parentFD); parentFD = -1 }
  }
  private func withParentLock<T>(cleaning: Bool = false, _ action: () throws -> T) throws -> T {
    let fd = Darwin.openat(parentFD, ".lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw Self.posix() }
    defer { Darwin.close(fd) }
    var info = stat()
    guard Darwin.fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_nlink == 1 else { throw AgentKnowledgeDatabaseError.corruptRecord }
    while Darwin.flock(fd, LOCK_EX | LOCK_NB) != 0 {
      if !cleaning { try Task.checkCancellation() }
      if errno == EINTR { continue }
      guard errno == EWOULDBLOCK || errno == EAGAIN else { throw Self.posix() }
      // Cleanup after cancellation still has to release the owned directory.
      Thread.sleep(forTimeInterval: 0.01)
    }
    defer { Darwin.flock(fd, LOCK_UN) }
    return try action()
  }
  private func sweep() throws {
    for name in try FileManager.default.contentsOfDirectory(atPath: parent.path) {
      try Task.checkCancellation()
      guard name.hasPrefix("job-"), UUID(uuidString: String(name.dropFirst(4)))?.uuidString.lowercased() == String(name.dropFirst(4)) else { continue }
      let fd = Darwin.openat(parentFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard fd >= 0 else { continue }
      defer { Darwin.close(fd) }
      let lock = Darwin.openat(fd, ".lease", O_RDWR | O_NOFOLLOW | O_CLOEXEC)
      if lock < 0 {
        if errno == ENOENT, (try? FileManager.default.contentsOfDirectory(atPath: parent.appendingPathComponent(name).path).isEmpty) == true {
          try? dispose(name, fd: fd)
        }
        continue
      }
      defer { Darwin.close(lock) }
      var info = stat()
      guard Darwin.fstat(lock, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_nlink == 1,
            Darwin.flock(lock, LOCK_EX | LOCK_NB) == 0 else { continue }
      try? dispose(name, fd: fd)
    }
  }
  private func dispose(_ name: String, fd: Int32) throws {
    guard fd >= 0 else { return }
    var anchored = stat(), current = stat()
    guard Darwin.fstat(fd, &anchored) == 0, Darwin.fstatat(parentFD, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
          current.st_dev == anchored.st_dev, current.st_ino == anchored.st_ino else { throw AgentKnowledgeDatabaseError.corruptRecord }
    let names = try FileManager.default.contentsOfDirectory(atPath: parent.appendingPathComponent(name).path)
    guard Set(names).isSubset(of: Self.files) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    for file in names {
      var info = stat()
      guard Darwin.fstatat(fd, file, &info, AT_SYMLINK_NOFOLLOW) == 0,
            (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_nlink == 1 else { throw AgentKnowledgeDatabaseError.corruptRecord }
    }
    for file in names { guard Darwin.unlinkat(fd, file, 0) == 0 else { throw Self.posix() } }
    guard Darwin.unlinkat(parentFD, name, AT_REMOVEDIR) == 0 else { throw Self.posix() }
  }
  private static func posix() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
