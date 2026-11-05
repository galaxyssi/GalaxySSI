import CryptoKit
import Foundation

@MainActor
struct GalaxySSIHealthBackupHistory {
  struct Entry: Codable, Identifiable, Sendable {
    enum Generation: String, Codable, Sendable { case pending, ready, interrupted }
    enum Save: String, Codable, Sendable { case pending, verified, unverified, interrupted }
    let id: UUID
    let at: Date
    var generation: Generation = .pending
    var bytes: Int?
    var sha256: String?
    var latestSave: Save?
    var lastVerifiedAt: Date?
  }

  let owner: String
  let secrets: GalaxySSISecretStore
  var fixtureDirectory: URL? = nil
  private var context: Data { Data(("galaxyssi.health.backup.history.v1:" + owner).utf8) }
  private var account: String { "health.backup.history.v1." + owner }

  func begin() throws -> UUID {
    var entries = try load()
    let id = UUID()
    entries.insert(Entry(id: id, at: Date()), at: 0)
    try persist(Array(entries.prefix(100)))
    return id
  }

  func publish(_ data: Data, id: UUID) throws {
    guard (1...GalaxySSIHealthPortableBackup.maximumFileBytes).contains(data.count) else {
      throw GalaxySSIHealthPortableBackup.Failure.limit
    }
    var entries = try load()
    guard let index = entries.firstIndex(where: { $0.id == id && $0.generation == .pending }) else {
      throw GalaxySSIHealthPortableBackup.Failure.stale
    }
    entries[index].bytes = data.count
    entries[index].sha256 = Self.digest(data)
    try persist(entries)
    try data.write(to: package(id), options: [.atomic, .completeFileProtection])
    entries[index].generation = .ready
    try persist(entries)
    try? prune(entries)
  }

  func recover() throws {
    var entries = try load()
    var changed = false
    for index in entries.indices {
      if entries[index].generation == .pending {
        entries[index].generation = (try? checkedPackage(entries[index])) != nil ? .ready : .interrupted
        changed = true
      }
      if entries[index].latestSave == .pending {
        entries[index].latestSave = .interrupted
        changed = true
      }
    }
    if changed { try persist(entries) }
    try prune(entries)
  }

  func beginSave(_ id: UUID) throws -> Entry {
    var entries = try load()
    guard let index = entries.firstIndex(where: { $0.id == id && $0.generation == .ready }),
          entries[index].latestSave != .pending else { throw GalaxySSIHealthPortableBackup.Failure.stale }
    entries[index].latestSave = .pending
    try persist(entries)
    return entries[index]
  }

  func finishSave(_ id: UUID, verified: Bool) throws {
    var entries = try load()
    guard let index = entries.firstIndex(where: { $0.id == id && $0.latestSave == .pending }) else {
      throw GalaxySSIHealthPortableBackup.Failure.stale
    }
    entries[index].latestSave = verified ? .verified : .unverified
    if verified { entries[index].lastVerifiedAt = Date() }
    try persist(entries)
  }

  func entries() throws -> [Entry] { try load() }

  func hasCopy(_ entry: Entry) -> Bool {
    guard entry.generation == .ready, let url = try? package(entry.id) else { return false }
    return FileManager.default.fileExists(atPath: url.path)
  }

  func readCopy(_ entry: Entry) throws -> Data {
    guard entry.generation == .ready else { throw GalaxySSIHealthPortableBackup.Failure.stale }
    return try checkedPackage(entry)
  }

  nonisolated static func verifyDestination(_ url: URL, entry: Entry) throws -> Bool {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    var error: NSError?
    var result: Result<Bool, Error>?
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { resolved in
      result = Result { try matches(resolved, entry: entry) }
    }
    if let error { throw error }
    guard let result else { throw GalaxySSIHealthPortableBackup.Failure.invalid }
    return try result.get()
  }

  private nonisolated static func matches(_ url: URL, entry: Entry) throws -> Bool {
    guard let length = entry.bytes, let expected = entry.sha256 else { return false }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var count = 0
    var hash = SHA256()
    while let bytes = try handle.read(upToCount: 128 * 1024), !bytes.isEmpty {
      count += bytes.count
      guard count <= length else { return false }
      hash.update(data: bytes)
    }
    return count == length && hash.finalize().map { String(format: "%02x", $0) }.joined() == expected
  }

  private func checkedPackage(_ entry: Entry) throws -> Data {
    guard let length = entry.bytes, (1...GalaxySSIHealthPortableBackup.maximumFileBytes).contains(length),
          let expected = entry.sha256 else { throw GalaxySSIHealthPortableBackup.Failure.invalid }
    let file = try FileHandle(forReadingFrom: package(entry.id))
    defer { try? file.close() }
    guard let data = try file.read(upToCount: length + 1), data.count == length, Self.digest(data) == expected
    else { throw GalaxySSIHealthPortableBackup.Failure.invalid }
    return data
  }

  private func prune(_ entries: [Entry]) throws {
    let root = try directory()
    let fm = FileManager.default
    let kept = Set(entries.filter { $0.generation == .ready && hasCopy($0) }.prefix(2).map(\.id))
    for file in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
      guard let id = UUID(uuidString: file.lastPathComponent), !kept.contains(id) else { continue }
      try fm.removeItem(at: file)
    }
  }

  private func load() throws -> [Entry] {
    let url = try directory().appendingPathComponent("history")
    let data: Data
    do { data = try Data(contentsOf: url) }
    catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return [] }
    let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key(create: false), authenticating: context)
    return try JSONDecoder().decode([Entry].self, from: plain)
  }

  private func persist(_ entries: [Entry]) throws {
    let bytes = try JSONEncoder().encode(entries)
    guard let sealed = try AES.GCM.seal(bytes, using: key(create: true), authenticating: context).combined
    else { throw GalaxySSIHealthPortableBackup.Failure.invalid }
    try sealed.write(to: directory().appendingPathComponent("history"), options: [.atomic, .completeFileProtection])
  }

  private func key(create: Bool) throws -> SymmetricKey {
    if let encoded = secrets.string(account: account) {
      guard let data = Data(base64Encoded: encoded), data.count == 32 else { throw GalaxySSIHealthPortableBackup.Failure.invalid }
      return SymmetricKey(data: data)
    }
    guard create else { throw GalaxySSIHealthPortableBackup.Failure.invalid }
    let key = SymmetricKey(size: .bits256)
    try secrets.setString(key.withUnsafeBytes { Data($0).base64EncodedString() }, account: account)
    return key
  }

  private func package(_ id: UUID) throws -> URL { try directory().appendingPathComponent(id.uuidString) }

  private func directory() throws -> URL {
    if let fixtureDirectory { return fixtureDirectory }
    let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                           appropriateFor: nil, create: true)
    var root = base.appendingPathComponent("HealthBackupHistory", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                            attributes: [.protectionKey: FileProtectionType.complete])
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try root.setResourceValues(values)
    let scoped = root.appendingPathComponent(Self.digest(Data(owner.utf8)), isDirectory: true)
    try FileManager.default.createDirectory(at: scoped, withIntermediateDirectories: true,
                                            attributes: [.protectionKey: FileProtectionType.complete])
    return scoped
  }

  private nonisolated static func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}
