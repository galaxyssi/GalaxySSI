import CryptoKit
import Foundation
import SQLite3

// The owning cache serializes callers; SQLite transactions also serialize other
// handles. Only opaque source keys, recency and authenticated ciphertext persist.
final class AgentIOSWebSourceHealthDatabase {
  enum Failure: Error { case unavailable, corrupt }
  private var database: OpaquePointer?
  private let key: SymmetricKey
  private let indexKey: SymmetricKey
  private let namespace: String
  private let beforeCommit: () throws -> Void
  private let didDecode: () -> Void

  init(fileURL: URL, masterKey: SymmetricKey, storageIdentity: String? = nil, beforeCommit: @escaping () throws -> Void = {},
    didDecode: @escaping () -> Void = {}) throws {
    guard fileURL.isFileURL else { throw Failure.unavailable }
    let identity = Data((storageIdentity ?? fileURL.standardizedFileURL.path).utf8)
    namespace = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
    key = HKDF<SHA256>.deriveKey(inputKeyMaterial: masterKey, salt: identity,
      info: Data("galaxyssi.web-health.payload.v1".utf8), outputByteCount: 32)
    indexKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: masterKey, salt: identity,
      info: Data("galaxyssi.web-health.index.v1".utf8), outputByteCount: 32)
    self.beforeCommit = beforeCommit
    self.didDecode = didDecode
    let directory = fileURL.deletingLastPathComponent()
    try Self.rejectLink(directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication, .posixPermissions: 0o700])
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
      .posixPermissions: 0o700], ofItemAtPath: directory.path)
    var protectedDirectory = directory
    var resources = URLResourceValues()
    resources.isExcludedFromBackup = true
    try protectedDirectory.setResourceValues(resources)
    for path in [fileURL.path, fileURL.path + "-wal", fileURL.path + "-shm"] { try Self.rejectLink(URL(fileURLWithPath: path)) }
    guard sqlite3_open_v2(fileURL.path, &database,
      SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
      if let database { sqlite3_close_v2(database) }
      database = nil
      throw Failure.unavailable
    }
    var ready = false
    defer { if !ready, let database { sqlite3_close_v2(database); self.database = nil } }
    sqlite3_busy_timeout(database, 5_000)
    try execute("PRAGMA journal_mode = WAL")
    try execute("PRAGMA synchronous = FULL")
    try execute("PRAGMA fullfsync = ON")
    try execute("PRAGMA cache_size = -512")
    try execute("PRAGMA mmap_size = 0")
    try execute("CREATE TABLE IF NOT EXISTS web_health (source_key TEXT PRIMARY KEY, updated_at INTEGER NOT NULL, payload BLOB NOT NULL)")
    try execute("CREATE INDEX IF NOT EXISTS web_health_recency ON web_health(updated_at DESC,source_key)")
    try execute("CREATE TABLE IF NOT EXISTS web_health_migration (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL)")
    for path in [fileURL.path, fileURL.path + "-wal", fileURL.path + "-shm"] where FileManager.default.fileExists(atPath: path) {
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
        .posixPermissions: 0o600], ofItemAtPath: path)
    }
    ready = true
  }

  deinit { if let database { sqlite3_close_v2(database) } }

  func initialize(allowLegacyImport: Bool = true, _ legacy: () throws -> [AgentIOSWebSourceHealth]) throws {
    // Check before BEGIN to avoid commit hooks and legacy I/O on normal reads.
    if try initialized() { return }
    guard allowLegacyImport else { throw Failure.corrupt }
    try transaction {
      if try initialized() { return }
      guard allowLegacyImport else { throw Failure.corrupt }
      let values = try legacy()
      guard values.count <= AgentIOSWebSourceHealth.maximumSources, values.allSatisfy(\.isValid),
        Set(values.map(\.sourceID)).count == values.count else { throw Failure.corrupt }
      guard try count() == 0 else { throw Failure.corrupt }
      for value in values { try put(value) }
      let statement = try prepare("INSERT INTO web_health_migration(id,payload) VALUES(1,?)")
      defer { sqlite3_finalize(statement) }
      try bind(seal(Data(namespace.utf8), purpose: "migration"), at: 1, to: statement)
      try finish(statement)
    }
  }

  func records(ids: Set<String> = []) throws -> [String: AgentIOSWebSourceHealth] {
    guard ids.count <= AgentIOSWebSourceHealth.maximumSources, ids.allSatisfy(AgentIOSWebSourceHealth.validID) else { throw Failure.corrupt }
    let sorted = ids.sorted()
    let clause = sorted.isEmpty ? "" : " WHERE source_key IN (" + Array(repeating: "?", count: sorted.count).joined(separator: ",") + ")"
    let statement = try prepare("SELECT source_key,updated_at,payload FROM web_health" + clause + " LIMIT 513")
    defer { sqlite3_finalize(statement) }
    for (index, id) in sorted.enumerated() { try bind(sourceKey(id), at: Int32(index + 1), to: statement) }
    var result: [String: AgentIOSWebSourceHealth] = [:]
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return result }
      guard status == SQLITE_ROW, result.count < AgentIOSWebSourceHealth.maximumSources,
        let text = sqlite3_column_text(statement, 0) else { throw Failure.corrupt }
      let opaque = String(cString: text)
      let value = try JSONDecoder().decode(AgentIOSWebSourceHealth.self, from: open(blob(statement, column: 2), purpose: opaque))
      guard value.isValid, sourceKey(value.sourceID) == opaque, result[value.sourceID] == nil,
        value.lastAttemptAtMillis == sqlite3_column_int64(statement, 1),
        sorted.isEmpty || ids.contains(value.sourceID) else { throw Failure.corrupt }
      didDecode()
      result[value.sourceID] = value
    }
  }

  func record(_ receipts: [AgentIOSWebSourceReceipt], now: () -> Int64) throws {
    guard receipts.count <= AgentIOSWebSourceHealth.maximumSources, receipts.allSatisfy(\.isValid) else { throw Failure.corrupt }
    if receipts.isEmpty { return }
    try transaction {
      var changes = try records(ids: Set(receipts.map(\.sourceID)))
      for receipt in receipts {
        changes[receipt.sourceID] = (changes[receipt.sourceID] ?? AgentIOSWebSourceHealth(sourceID: receipt.sourceID))
          .evolved(receipt, now: now())
      }
      for value in changes.values { try put(value) }
      try execute("DELETE FROM web_health WHERE source_key IN (SELECT source_key FROM web_health ORDER BY updated_at DESC,source_key LIMIT -1 OFFSET 512)")
    }
  }

  func reset() throws -> Int64 {
    try transaction {
      let removed = try count()
      try execute("DELETE FROM web_health")
      return removed
    }
  }

  func count() throws -> Int64 {
    let statement = try prepare("SELECT COUNT(*) FROM web_health")
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw Failure.unavailable }
    return sqlite3_column_int64(statement, 0)
  }

  private func initialized() throws -> Bool {
    let statement = try prepare("SELECT payload FROM web_health_migration WHERE id=1")
    defer { sqlite3_finalize(statement) }
    switch sqlite3_step(statement) {
    case SQLITE_DONE: return false
    case SQLITE_ROW:
      guard try open(blob(statement, column: 0), purpose: "migration") == Data(namespace.utf8) else { throw Failure.corrupt }
      return true
    default: throw Failure.unavailable
    }
  }

  private func transaction<T>(_ body: () throws -> T) throws -> T {
    try execute("BEGIN IMMEDIATE TRANSACTION")
    var committed = false
    defer { if !committed { try? execute("ROLLBACK") } }
    let result = try body()
    try beforeCommit()
    try execute("COMMIT")
    committed = true
    return result
  }

  private func put(_ value: AgentIOSWebSourceHealth) throws {
    guard value.isValid else { throw Failure.corrupt }
    let opaque = sourceKey(value.sourceID)
    let encrypted = try seal(JSONEncoder().encode(value), purpose: opaque)
    let statement = try prepare("INSERT INTO web_health(source_key,updated_at,payload) VALUES(?,?,?) ON CONFLICT(source_key) DO UPDATE SET updated_at=excluded.updated_at,payload=excluded.payload")
    defer { sqlite3_finalize(statement) }
    try bind(opaque, at: 1, to: statement)
    guard sqlite3_bind_int64(statement, 2, value.lastAttemptAtMillis) == SQLITE_OK else { throw Failure.unavailable }
    try bind(encrypted, at: 3, to: statement)
    try finish(statement)
  }

  private func sourceKey(_ id: String) -> String {
    HMAC<SHA256>.authenticationCode(for: Data(id.utf8), using: indexKey).map { String(format: "%02x", $0) }.joined()
  }
  private func purpose(_ value: String) -> Data { Data("galaxyssi.web-health.v1:\(namespace):\(value)".utf8) }
  private func seal(_ value: Data, purpose: String) throws -> Data {
    guard let combined = try AES.GCM.seal(value, using: key, authenticating: self.purpose(purpose)).combined else { throw Failure.corrupt }
    return combined
  }
  private func open(_ value: Data, purpose: String) throws -> Data {
    try AES.GCM.open(AES.GCM.SealedBox(combined: value), using: key, authenticating: self.purpose(purpose))
  }
  private func blob(_ statement: OpaquePointer, column: Int32) throws -> Data {
    let count = Int(sqlite3_column_bytes(statement, column))
    guard (1...32_768).contains(count), let bytes = sqlite3_column_blob(statement, column) else { throw Failure.corrupt }
    return Data(bytes: bytes, count: count)
  }
  private func prepare(_ sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw Failure.unavailable }
    return statement
  }
  private func execute(_ sql: String) throws {
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw Failure.unavailable }
  }
  private func finish(_ statement: OpaquePointer) throws {
    guard sqlite3_step(statement) == SQLITE_DONE else { throw Failure.unavailable }
  }
  private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) throws {
    guard value.withCString({ sqlite3_bind_text(statement, index, $0, -1, Self.transient) }) == SQLITE_OK else { throw Failure.unavailable }
  }
  private func bind(_ value: Data, at index: Int32, to statement: OpaquePointer) throws {
    guard value.withUnsafeBytes({ sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), Self.transient) }) == SQLITE_OK else { throw Failure.unavailable }
  }
  private static func rejectLink(_ url: URL) throws {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else { throw Failure.corrupt }
    } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { return }
  }
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
