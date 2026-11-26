import CryptoKit
import Foundation
import SQLite3

final class AgentIOSWebCacheIndex {
  enum Failure: Error { case unavailable, corrupt, staleGeneration }
  enum Kind: String, Codable, CaseIterable { case document, search, watch, learned }
  struct Entry: Codable {
    var kind: Kind
    var id: String
    var updated: Int64
    var expires: Int64 = 0
    var characters: Int64 = 0
    var verified = false
    var payload: Data
  }
  private struct Marker: Codable { var namespace: String; var generation: UUID }
  private var database: OpaquePointer?
  private let key: SymmetricKey
  private let indexKey: SymmetricKey
  private let namespace: String
  private let beforeCommit: () throws -> Void
  private let didDecode: () -> Void

  init(url: URL, master: SymmetricKey, identity: String, beforeCommit: @escaping () throws -> Void,
    didDecode: @escaping () -> Void = {}) throws {
    guard url.isFileURL else { throw Failure.unavailable }
    let salt = Data(identity.utf8)
    namespace = SHA256.hash(data: salt).map { String(format: "%02x", $0) }.joined()
    key = HKDF<SHA256>.deriveKey(inputKeyMaterial: master, salt: salt, info: Data("web-cache.rows.v1".utf8), outputByteCount: 32)
    indexKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: master, salt: salt, info: Data("web-cache.keys.v1".utf8), outputByteCount: 32)
    self.beforeCommit = beforeCommit
    self.didDecode = didDecode
    let root = url.deletingLastPathComponent()
    for candidate in [root, url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")] {
      do {
        let attrs = try FileManager.default.attributesOfItem(atPath: candidate.path)
        guard attrs[.type] as? FileAttributeType != .typeSymbolicLink else { throw Failure.corrupt }
      } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { continue }
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication, .posixPermissions: 0o700], ofItemAtPath: root.path)
    var folder = root, resources = URLResourceValues()
    resources.isExcludedFromBackup = true
    try folder.setResourceValues(resources)
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
      if let database { sqlite3_close_v2(database) }; database = nil; throw Failure.unavailable
    }
    var ready = false
    defer { if !ready, let database { sqlite3_close_v2(database); self.database = nil } }
    sqlite3_busy_timeout(database, 5_000)
    for sql in ["PRAGMA journal_mode=WAL", "PRAGMA synchronous=FULL", "PRAGMA fullfsync=ON", "PRAGMA cache_size=-1024", "PRAGMA mmap_size=0",
      "CREATE TABLE IF NOT EXISTS cache_rows(row_id INTEGER PRIMARY KEY AUTOINCREMENT,kind TEXT NOT NULL,entry_key TEXT NOT NULL,updated INTEGER NOT NULL,expires INTEGER NOT NULL,characters INTEGER NOT NULL,verified INTEGER NOT NULL,payload BLOB NOT NULL,UNIQUE(kind,entry_key))",
      "CREATE INDEX IF NOT EXISTS cache_recency ON cache_rows(kind,updated DESC,entry_key)",
      "CREATE INDEX IF NOT EXISTS cache_insertion ON cache_rows(kind,row_id DESC)",
      "CREATE INDEX IF NOT EXISTS cache_expiry ON cache_rows(kind,expires)",
      "CREATE TABLE IF NOT EXISTS cache_marker(id INTEGER PRIMARY KEY CHECK(id=1),payload BLOB NOT NULL)"] { try execute(sql) }
    for path in [url.path, url.path + "-wal", url.path + "-shm"] where FileManager.default.fileExists(atPath: path) {
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication, .posixPermissions: 0o600], ofItemAtPath: path)
    }
    ready = true
  }
  deinit { if let database { sqlite3_close_v2(database) } }

  func initialize(allowImport: Bool, legacy: () throws -> [Entry]) throws {
    if try marker() != nil { return }
    guard allowImport else { throw Failure.corrupt }
    try transaction {
      if try marker() != nil { return }
      guard try scalar("SELECT COUNT(*) FROM cache_rows") == 0 else { throw Failure.corrupt }
      let entries = try legacy()
      guard entries.count <= 2_644, Set(entries.map { $0.kind.rawValue + ":" + $0.id }).count == entries.count else { throw Failure.corrupt }
      for (kind, limit) in [(Kind.document, 2000), (.search, 32), (.watch, 100), (.learned, 512)] {
        guard entries.filter({ $0.kind == kind }).count <= limit else { throw Failure.corrupt }
      }
      for entry in entries { try put(entry) }
      try writeMarker(Marker(namespace: namespace, generation: UUID()))
    }
  }

  func generation() throws -> UUID {
    guard let value = try marker() else { throw Failure.corrupt }
    return value.generation
  }
  func transaction<T>(_ body: () throws -> T) throws -> T {
    try execute("BEGIN IMMEDIATE TRANSACTION")
    var committed = false
    defer { if !committed { try? execute("ROLLBACK") } }
    let value = try body()
    try beforeCommit()
    try execute("COMMIT")
    committed = true
    return value
  }

  func entry(_ kind: Kind, id: String) throws -> Entry? {
    let values = try select(kind, id: id, limit: 1)
    return values.first
  }
  func entries(_ kind: Kind, limit: Int) throws -> [Entry] {
    let bound = min(max(limit, 1), 2000)
    let values = try select(kind, id: nil, limit: bound + 1)
    guard values.count <= bound else { throw Failure.corrupt }
    return values
  }
  func forEach(_ kind: Kind, _ body: (Entry) throws -> Void) throws {
    var count = 0
    try visit(kind, id: nil, limit: 2_001) { entry in
      count += 1
      guard count <= 2_000 else { throw Failure.corrupt }
      try body(entry)
    }
  }
  private func select(_ kind: Kind, id: String?, limit: Int) throws -> [Entry] {
    var result: [Entry] = []
    try visit(kind, id: id, limit: limit) { result.append($0) }
    return result
  }
  private func visit(_ kind: Kind, id: String?, limit: Int, _ body: (Entry) throws -> Void) throws {
    let statement = try prepare("SELECT entry_key,updated,expires,characters,verified,payload FROM cache_rows WHERE kind=?" +
      (id == nil ? "" : " AND entry_key=?") + " ORDER BY updated DESC,entry_key LIMIT ?")
    defer { sqlite3_finalize(statement) }
    try bind(kind.rawValue, 1, statement)
    if let id { try bind(opaque(kind, id), 2, statement) }
    sqlite3_bind_int(statement, id == nil ? 2 : 3, Int32(min(max(limit, 1), 2_745)))
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return }
      guard status == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw Failure.corrupt }
      let digest = String(cString: text)
      let entry = try JSONDecoder().decode(Entry.self, from: open(blob(statement, 5), purpose: kind.rawValue + ":" + digest))
      guard entry.kind == kind, opaque(kind, entry.id) == digest, id == nil || entry.id == id,
        entry.updated == sqlite3_column_int64(statement, 1), entry.expires == sqlite3_column_int64(statement, 2),
        entry.characters == sqlite3_column_int64(statement, 3), (entry.verified ? 1 : 0) == sqlite3_column_int(statement, 4) else { throw Failure.corrupt }
      didDecode()
      try body(entry)
    }
  }

  func put(_ entry: Entry) throws {
    guard !entry.id.isEmpty, entry.id.utf8.count <= 4_096, entry.updated >= 0, entry.expires >= 0,
      entry.characters >= 0, entry.payload.count <= 3_000_000 else { throw Failure.corrupt }
    let digest = opaque(entry.kind, entry.id)
    let encoded = try JSONEncoder().encode(entry)
    guard encoded.count <= 4_099_000 else { throw Failure.corrupt }
    let data = try seal(encoded, purpose: entry.kind.rawValue + ":" + digest)
    let s = try prepare("INSERT OR REPLACE INTO cache_rows(kind,entry_key,updated,expires,characters,verified,payload) VALUES(?,?,?,?,?,?,?)")
    defer { sqlite3_finalize(s) }
    try bind(entry.kind.rawValue, 1, s); try bind(digest, 2, s)
    sqlite3_bind_int64(s, 3, entry.updated); sqlite3_bind_int64(s, 4, entry.expires); sqlite3_bind_int64(s, 5, entry.characters)
    sqlite3_bind_int(s, 6, entry.verified ? 1 : 0); try bind(data, 7, s)
    try finish(s)
  }
  func remove(_ kind: Kind, id: String? = nil, before: Int64? = nil, inclusive: Bool = true) throws -> Int64 {
    let condition = id != nil ? " AND entry_key=?" : (before == nil ? "" : " AND expires" + (inclusive ? "<=?" : "<?"))
    let s = try prepare("DELETE FROM cache_rows WHERE kind=?" + condition)
    defer { sqlite3_finalize(s) }
    try bind(kind.rawValue, 1, s)
    if let id { try bind(opaque(kind, id), 2, s) }
    else if let before { sqlite3_bind_int64(s, 2, before) }
    try finish(s)
    return Int64(sqlite3_changes(database))
  }
  func prune(_ kind: Kind, limit: Int) throws {
    let order = kind == .document || kind == .learned ? "row_id DESC" : "updated DESC,entry_key"
    let s = try prepare("DELETE FROM cache_rows WHERE kind=? AND entry_key IN (SELECT entry_key FROM cache_rows WHERE kind=? ORDER BY " + order + " LIMIT -1 OFFSET ?)")
    defer { sqlite3_finalize(s) }
    try bind(kind.rawValue, 1, s); try bind(kind.rawValue, 2, s); sqlite3_bind_int(s, 3, Int32(min(max(0, limit), 2000)))
    try finish(s)
  }
  func putSearch(_ entry: Entry, now: Int64, expected: UUID?) throws {
    guard entry.kind == .search else { throw Failure.corrupt }
    try transaction {
      if let expected, try generation() != expected { throw Failure.staleGeneration }
      _ = try remove(.search, before: now)
      try put(entry); try prune(.search, limit: 32)
    }
  }
  func compareAndPutWatch(_ updated: Entry, expected: AgentIOSWebIntelligenceCacheWatch) throws -> Bool {
    guard updated.kind == .watch, updated.id == expected.id else { throw Failure.corrupt }
    let replacement = try JSONDecoder().decode(AgentIOSWebIntelligenceCacheWatch.self, from: updated.payload)
    guard replacement.id == updated.id, replacement.updatedAtMillis == updated.updated else { throw Failure.corrupt }
    try execute("BEGIN IMMEDIATE TRANSACTION")
    var committed = false
    defer { if !committed { try? execute("ROLLBACK") } }
    guard let current = try entry(.watch, id: expected.id) else { return false }
    let saved = try JSONDecoder().decode(AgentIOSWebIntelligenceCacheWatch.self, from: current.payload)
    guard saved.id == current.id, saved.updatedAtMillis == current.updated else { throw Failure.corrupt }
    guard saved == expected else { return false }
    try put(updated)
    try beforeCommit()
    try execute("COMMIT")
    committed = true
    return true
  }
  func clear(expiredOnly: Bool, now: Int64) throws -> (documents: Int64, searches: Int64, learned: Int64) {
    try transaction {
      let documents = try remove(.document, before: expiredOnly ? now : nil, inclusive: false)
      let searches = try remove(.search, before: expiredOnly ? now : nil)
      let learned = expiredOnly ? 0 : try remove(.learned)
      if !expiredOnly { try writeMarker(Marker(namespace: namespace, generation: UUID())) }
      return (documents, searches, learned)
    }
  }
  func metadata(now: Int64) throws -> AgentMcpJSONObject {
    try execute("BEGIN DEFERRED TRANSACTION")
    defer { try? execute("ROLLBACK") }
    var result: AgentMcpJSONObject = [:]
    for (kind, label) in [(Kind.document, "entry_count"), (.search, "search_count"), (.watch, "watch_count"), (.learned, "learned_source_count")] {
      result[label] = .int(try scalar("SELECT COUNT(*) FROM cache_rows WHERE kind='" + kind.rawValue + "'"))
    }
    result["content_chars"] = .int(try scalar("SELECT COALESCE(SUM(characters),0) FROM cache_rows WHERE kind='document'"))
    result["verified_learned_source_count"] = .int(try scalar("SELECT COUNT(*) FROM cache_rows WHERE kind='learned' AND verified=1"))
    let s = try prepare("SELECT COUNT(*) FROM cache_rows WHERE kind='document' AND expires<?")
    defer { sqlite3_finalize(s) }
    sqlite3_bind_int64(s, 1, now)
    guard sqlite3_step(s) == SQLITE_ROW else { throw Failure.unavailable }
    result["expired_count"] = .int(sqlite3_column_int64(s, 0))
    return result
  }
  private func marker() throws -> Marker? {
    let s = try prepare("SELECT payload FROM cache_marker WHERE id=1")
    defer { sqlite3_finalize(s) }
    switch sqlite3_step(s) {
    case SQLITE_DONE: return nil
    case SQLITE_ROW:
      let value = try JSONDecoder().decode(Marker.self, from: open(blob(s, 0), purpose: "marker"))
      guard value.namespace == namespace else { throw Failure.corrupt }
      return value
    default: throw Failure.unavailable
    }
  }
  private func writeMarker(_ marker: Marker) throws {
    let s = try prepare("INSERT OR REPLACE INTO cache_marker(id,payload) VALUES(1,?)")
    defer { sqlite3_finalize(s) }
    try bind(seal(JSONEncoder().encode(marker), purpose: "marker"), 1, s); try finish(s)
  }
  private func opaque(_ kind: Kind, _ id: String) -> String {
    HMAC<SHA256>.authenticationCode(for: Data((kind.rawValue + ":" + id).utf8), using: indexKey).map { String(format: "%02x", $0) }.joined()
  }
  private func aad(_ purpose: String) -> Data { Data("galaxyssi.web-cache.v1:\(namespace):\(purpose)".utf8) }
  private func seal(_ data: Data, purpose: String) throws -> Data {
    guard let bytes = try AES.GCM.seal(data, using: key, authenticating: aad(purpose)).combined else { throw Failure.corrupt }
    return bytes
  }
  private func open(_ data: Data, purpose: String) throws -> Data { try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: aad(purpose)) }
  private func blob(_ s: OpaquePointer, _ column: Int32) throws -> Data {
    let count = Int(sqlite3_column_bytes(s, column))
    guard (1...4_100_000).contains(count), let bytes = sqlite3_column_blob(s, column) else { throw Failure.corrupt }
    return Data(bytes: bytes, count: count)
  }
  private func scalar(_ sql: String) throws -> Int64 {
    let s = try prepare(sql); defer { sqlite3_finalize(s) }
    guard sqlite3_step(s) == SQLITE_ROW else { throw Failure.unavailable }
    return sqlite3_column_int64(s, 0)
  }
  private func prepare(_ sql: String) throws -> OpaquePointer {
    var s: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &s, nil) == SQLITE_OK, let s else { throw Failure.unavailable }
    return s
  }
  private func execute(_ sql: String) throws { guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw Failure.unavailable } }
  private func finish(_ s: OpaquePointer) throws { guard sqlite3_step(s) == SQLITE_DONE else { throw Failure.unavailable } }
  private func bind(_ text: String, _ index: Int32, _ s: OpaquePointer) throws {
    guard text.withCString({ sqlite3_bind_text(s, index, $0, -1, Self.transient) }) == SQLITE_OK else { throw Failure.unavailable }
  }
  private func bind(_ data: Data, _ index: Int32, _ s: OpaquePointer) throws {
    guard data.withUnsafeBytes({ sqlite3_bind_blob(s, index, $0.baseAddress, Int32($0.count), Self.transient) }) == SQLITE_OK else { throw Failure.unavailable }
  }
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
