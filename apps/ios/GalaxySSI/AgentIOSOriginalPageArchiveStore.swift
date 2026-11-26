import CryptoKit
import Foundation

final class AgentIOSOriginalPageArchiveStore {
  private static let globalLock = NSRecursiveLock()
  struct Job: Codable {
    var id: String
    var profile: String
    var conversation: String
    var turn: String
    var url: String
    var name: String
    var language: String
    var source: Data
    var failures = 0
    var dueAt: Int64 = 0
  }

  private let root: URL
  private let documents: URL
  private let cipher: GalaxySSILocalAttachmentStoring
  private let profile: String
  private let lock = AgentIOSOriginalPageArchiveStore.globalLock

  init(profile: String, applicationSupport: URL? = nil, documents: URL? = nil,
       cipher: GalaxySSILocalAttachmentStoring = GalaxySSIAttachmentAtRestCipher(keyAccount: "web.original.archive.aes256.v1")) {
    self.profile = profile
    let scope = Self.hash(Data(profile.utf8))
    self.root = GalaxySSIPrivateChatFiles.directory("OriginalPageQueue/" + scope, applicationSupport: applicationSupport)
    self.documents = documents ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    self.cipher = cipher
  }

  @discardableResult
  func enqueue(source: Data, url: String, name: String, language: String, conversation: String, turn: String) throws -> String {
    lock.lock(); defer { lock.unlock() }
    guard !profile.isEmpty, !conversation.isEmpty, !turn.isEmpty,
          !source.isEmpty, source.count <= AgentIOSOriginalPageDocument.maximumSourceBytes,
          url.utf8.count <= 4_096, name.utf8.count <= 1_024, language.utf8.count <= 64 else { throw CocoaError(.fileWriteInvalidFileName) }
    let id = AgentMcpJSONCodec.sha256(["profile": .string(profile), "conversation": .string(conversation),
      "turn": .string(turn), "url": .string(url), "source": .string(Self.hash(source))])
    if FileManager.default.fileExists(atPath: file(id, "done").path) {
      guard try read(id, "done", maximum: 1_024) == Data(id.utf8) else { throw CocoaError(.fileReadCorruptFile) }
      return id
    }
    if FileManager.default.fileExists(atPath: file(id, "job").path) { _ = try job(id); return id }
    try write(try JSONEncoder().encode(Job(id: id, profile: profile, conversation: conversation,
      turn: turn, url: url, name: name, language: language, source: source)), id, "job")
    return id
  }

  func due(now: Int64, excluding: Set<String> = []) throws -> Job? {
    lock.lock(); defer { lock.unlock() }
    guard FileManager.default.fileExists(atPath: root.path) else { return nil }
    for path in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
      where path.pathExtension == "job" {
      let id = path.deletingPathExtension().lastPathComponent
      if excluding.contains(id) { continue }
      guard let candidate = try? job(id) else { continue }
      if FileManager.default.fileExists(atPath: file(id, "done").path) {
        guard try read(id, "done", maximum: 1_024) == Data(id.utf8) else { throw CocoaError(.fileReadCorruptFile) }
        try cleanup(id)
        continue
      }
      if candidate.failures < 3, candidate.dueAt <= now { return candidate }
    }
    return nil
  }

  func staged(_ id: String) throws -> Data? {
    lock.lock(); defer { lock.unlock() }
    try validate(id)
    guard FileManager.default.fileExists(atPath: file(id, "built").path) else { return nil }
    return try read(id, "built", maximum: AgentIOSOriginalPageDocument.maximumOutputBytes)
  }

  func stage(_ data: Data, id: String) throws {
    lock.lock(); defer { lock.unlock() }
    guard !data.isEmpty, data.count <= AgentIOSOriginalPageDocument.maximumOutputBytes else { throw CocoaError(.fileWriteOutOfSpace) }
    _ = try job(id)
    try write(data, id, "built")
  }

  func failed(_ original: Job, now: Int64) throws {
    lock.lock(); defer { lock.unlock() }
    var current = try job(original.id)
    current.failures += 1
    current.dueAt = now + Int64(current.failures) * 60_000
    try write(try JSONEncoder().encode(current), current.id, "job")
  }

  // Deterministic final name, no overwrite of a user's changed file. A committed
  // completion marker precedes cleanup, so interrupted cleanup cannot re-download.
  func publish(_ job: Job, data: Data) throws {
    lock.lock(); defer { lock.unlock() }
    try validate(job.id)
    guard job.profile == profile, !data.isEmpty, data.count <= AgentIOSOriginalPageDocument.maximumOutputBytes else { throw CocoaError(.fileReadCorruptFile) }
    let directory = documents.appendingPathComponent("GalaxySSI/Downloads/WebPages/" + Self.hash(Data(profile.utf8)), isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    guard GalaxySSIPrivateChatFiles.contains(directory, in: documents) else { throw CocoaError(.fileWriteNoPermission) }
    let stem = String(job.name.replacingOccurrences(of: #"[^\p{L}\p{N}._-]+"#, with: "-", options: .regularExpression).prefix(64))
    let destination = directory.appendingPathComponent(stem + "-" + job.id + "-original.html")
    if FileManager.default.fileExists(atPath: destination.path) {
      let values = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
      guard values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == data.count,
            Self.hash(try Data(contentsOf: destination)) == Self.hash(data) else { throw CocoaError(.fileWriteFileExists) }
    } else {
      let temporary = directory.appendingPathComponent("." + UUID().uuidString + ".partial")
      defer { try? FileManager.default.removeItem(at: temporary) }
      try data.write(to: temporary, options: [.atomic, .completeFileProtection])
      try FileManager.default.linkItem(at: temporary, to: destination)
    }
    try write(Data(job.id.utf8), job.id, "done")
    try cleanup(job.id)
  }

  private func job(_ id: String) throws -> Job {
    let value = try JSONDecoder().decode(Job.self, from: read(id, "job", maximum: 12 * 1_024 * 1_024))
    guard value.id == id, value.profile == profile, !value.conversation.isEmpty, !value.turn.isEmpty,
          !value.source.isEmpty, value.source.count <= AgentIOSOriginalPageDocument.maximumSourceBytes else { throw CocoaError(.fileReadCorruptFile) }
    return value
  }

  private func cleanup(_ id: String) throws {
    for ext in ["job", "built"] where FileManager.default.fileExists(atPath: file(id, ext).path) {
      try FileManager.default.removeItem(at: file(id, ext))
    }
  }

  private func file(_ id: String, _ ext: String) -> URL { root.appendingPathComponent(id + "." + ext) }
  private func purpose(_ id: String, _ ext: String) -> String { "galaxyssi.web.original.v1:\(profile):\(id):\(ext)" }
  private func read(_ id: String, _ ext: String, maximum: Int) throws -> Data {
    try validate(id)
    let path = file(id, ext), values = try path.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
          let size = values.fileSize, size <= maximum * 2 + 4_096 else { throw CocoaError(.fileReadCorruptFile) }
    let data = try cipher.read(from: path, purpose: purpose(id, ext))
    guard data.count <= maximum else { throw CocoaError(.fileReadTooLarge) }
    return data
  }
  private func write(_ data: Data, _ id: String, _ ext: String) throws {
    try validate(id)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try cipher.write(data, to: file(id, ext), purpose: purpose(id, ext))
  }
  private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
  private func validate(_ id: String) throws {
    guard id.utf8.count == 64, id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw CocoaError(.fileReadInvalidFileName) }
  }
}
