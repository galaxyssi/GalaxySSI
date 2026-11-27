import CryptoKit
import Darwin
import Foundation
import SQLite3

// One call owns this encrypted, non-resumable scratch. No body lists or stable
// identifiers are persisted in its index; each record is authenticated separately.
final class AgentKnowledgeSourceStaging {
  enum Side: String { case incoming, previous }
  private enum Phase { case incoming, verified, prepared, finished, closed }
  let directory: URL
  var fileURL: URL { directory.appendingPathComponent("records.sqlite") }
  let source: String
  private let job = UUID().uuidString
  private var cipherKey: SymmetricKey? = SymmetricKey(size: .bits256)
  private var tokenKey: SymmetricKey? = SymmetricKey(size: .bits256)
  private var database: OpaquePointer?
  private var phase = Phase.incoming
  private var previousBegun = false
  private var collationFailed = false
  private var activeStatements = 0, closing = false
  private var allowedCount = 0
  private struct OrderKey: Codable { var id: String; var chunk: Int; var record: Bool }
  private(set) var incomingCount: Int64 = 0
  private(set) var previousCount: Int64 = 0
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  init(source: String, parent: URL = FileManager.default.temporaryDirectory) throws {
    self.source = source
    directory = parent.appendingPathComponent("galaxyssi-source-stage-" + UUID().uuidString.lowercased(), isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o700])
      let fd = Darwin.open(fileURL.path, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
      guard fd >= 0 else { throw AgentKnowledgeDatabaseError.unavailable }
      Darwin.close(fd)
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path)
      guard sqlite3_open_v2(fileURL.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      guard sqlite3_create_collation_v2(database, "SOURCE_ORDER", SQLITE_UTF8, Unmanaged.passUnretained(self).toOpaque(), { context, ac, a, bc, b in
        guard let context else { return 0 }
        return Unmanaged<AgentKnowledgeSourceStaging>.fromOpaque(context).takeUnretainedValue().compare(a, ac, b, bc)
      }, nil) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
      guard sqlite3_create_collation_v2(database, "SOURCE_ID_ORDER", SQLITE_UTF8, Unmanaged.passUnretained(self).toOpaque(), { context, ac, a, bc, b in
        guard let context else { return 0 }
        return Unmanaged<AgentKnowledgeSourceStaging>.fromOpaque(context).takeUnretainedValue().compare(a, ac, b, bc, identity: true)
      }, nil) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
      try execute("PRAGMA journal_mode=DELETE"); try execute("PRAGMA synchronous=FULL")
      try execute("PRAGMA cache_size=-2048"); try execute("PRAGMA mmap_size=0"); try execute("PRAGMA temp_store=FILE")
      try execute("CREATE TABLE records(token TEXT PRIMARY KEY,incoming BLOB,previous BLOB) WITHOUT ROWID")
      try execute("CREATE TABLE ordering(side TEXT,sort_key TEXT COLLATE SOURCE_ORDER,token TEXT,PRIMARY KEY(side,sort_key)) WITHOUT ROWID")
      try execute("CREATE INDEX source_identity_order ON ordering(side,sort_key COLLATE SOURCE_ID_ORDER)")
      try execute("CREATE TABLE allowed_keys(token TEXT PRIMARY KEY,sort_key TEXT COLLATE SOURCE_ORDER UNIQUE) WITHOUT ROWID")
      try execute("BEGIN IMMEDIATE")
    } catch { close(); throw error }
  }
  deinit { close() }
  func close() {
    if activeStatements > 0 { closing = true; return }
    guard phase != .closed else { return }; phase = .closed
    if let database { AgentKnowledgeSQLiteStatements.shared.close(database); self.database = nil }
    cipherKey = nil; tokenKey = nil
    try? FileManager.default.removeItem(at: directory)
  }
  @discardableResult
  func accept(_ item: AgentKnowledgeItem) throws -> Bool {
    try Task.checkCancellation()
    guard phase == .incoming else { throw AgentKnowledgeDatabaseError.corruptRecord }
    guard item.source.utf8.elementsEqual(source.utf8), !item.title.isBlank, !item.content.isBlank else { return false }
    guard !item.id.isBlank, incomingCount < Int64.max else { throw AgentKnowledgeDatabaseError.corruptRecord }
    let key = try token(item.id)
    if let existing = try itemAt(key, side: .incoming) {
      guard existing.id.utf8.elementsEqual(item.id.utf8) else { throw AgentKnowledgeDatabaseError.corruptRecord }
      return false
    }
    try write(item, key: key, side: .incoming, inserting: true)
    incomingCount += 1
    return true
  }
  func finishIncoming() throws {
    guard phase == .incoming else { throw AgentKnowledgeDatabaseError.corruptRecord }
    try execute("COMMIT"); phase = .verified
    try scan(.incoming) { _ in }
  }
  func rememberPrevious(_ item: AgentKnowledgeItem) throws {
    try Task.checkCancellation()
    guard phase == .verified, item.source.utf8.elementsEqual(source.utf8), previousCount < Int64.max else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    if !previousBegun { try execute("BEGIN IMMEDIATE"); previousBegun = true }
    let key = try token(item.id)
    guard try itemAt(key, side: .previous) == nil else { throw AgentKnowledgeDatabaseError.corruptRecord }
    try write(item, key: key, side: .previous, inserting: true)
    previousCount += 1
  }
  func finishPrevious() throws {
    guard phase == .verified else { throw AgentKnowledgeDatabaseError.corruptRecord }
    if previousBegun { try execute("COMMIT") }
    phase = .prepared
    try scan(.previous) { _ in }
    try execute("BEGIN IMMEDIATE")
  }
  func normalized(_ item: AgentKnowledgeItem) throws {
    guard phase == .prepared else { throw AgentKnowledgeDatabaseError.corruptRecord }
    let key = try token(item.id)
    guard try itemAt(key, side: .incoming) != nil else { throw AgentKnowledgeDatabaseError.corruptRecord }
    try write(item, key: key, side: .incoming, inserting: false)
  }
  func finishMutation() throws {
    guard phase == .prepared else { throw AgentKnowledgeDatabaseError.corruptRecord }
    try execute("COMMIT"); phase = .finished
    try scan(.incoming) { _ in }
  }
  func item(_ id: String, side: Side) throws -> AgentKnowledgeItem? { try itemAt(token(id), side: side) }
  func hasPreparedIdentity(_ id: String) throws -> Bool {
    guard phase == .prepared else { throw AgentKnowledgeDatabaseError.corruptRecord }
    return try statement("SELECT previous IS NOT NULL FROM records WHERE token=?") { row in
      try bind(token(id), at: 1, to: row)
      let status = sqlite3_step(row)
      if status == SQLITE_DONE { return false }
      guard status == SQLITE_ROW else { throw AgentKnowledgeDatabaseError.corruptRecord }
      return sqlite3_column_int(row, 0) == 1
    }
  }
  // SQLite sorts only encrypted metadata. Bodies remain in the authenticated
  // staging table and are resolved one at a time after verifying their sort key.
  func orderedVisit(_ side: Side, byIdentity: Bool = false, consume: (AgentKnowledgeItem) throws -> Void) throws {
    guard phase == .finished, !collationFailed else { throw AgentKnowledgeDatabaseError.corruptRecord }
    try execute("BEGIN IMMEDIATE")
    do {
      try statement("DELETE FROM ordering WHERE side=?") { row in
        try bind(side.rawValue, at: 1, to: row)
        guard sqlite3_step(row) == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
      }
      try scan(side) { item in
        let key = try encodedOrderKey(OrderKey(id: item.id, chunk: item.chunkIndex, record: true))
        try statement("INSERT INTO ordering VALUES(?,?,?)") { row in
          try bind(side.rawValue, at: 1, to: row); try bind(key, at: 2, to: row); try bind(token(item.id), at: 3, to: row)
          guard sqlite3_step(row) == SQLITE_DONE, !collationFailed else { throw AgentKnowledgeDatabaseError.corruptRecord }
        }
      }
      try execute("COMMIT")
    } catch { try? execute("ROLLBACK"); throw error }
    try execute("BEGIN IMMEDIATE")
    do {
      let collation = byIdentity ? "SOURCE_ID_ORDER" : "SOURCE_ORDER"
      try statement("SELECT sort_key,token FROM ordering WHERE side=? ORDER BY sort_key COLLATE \(collation)") { row in
        try bind(side.rawValue, at: 1, to: row)
        var seen: Int64 = 0, previous: OrderKey?
        while true {
          try Task.checkCancellation()
          guard !closing else { throw AgentKnowledgeDatabaseError.unavailable }
          let status = sqlite3_step(row)
          if status == SQLITE_DONE { break }
          guard status == SQLITE_ROW, !collationFailed, let tokenText = sqlite3_column_text(row, 1) else { throw AgentKnowledgeDatabaseError.corruptRecord }
          let key = try orderKey(sqlite3_column_text(row, 0), sqlite3_column_bytes(row, 0))
          if let previous, !(byIdentity ? AgentKnowledgeSourceRevision.identityPrecedes(previous.id, key.id) : less(previous, key)) { throw AgentKnowledgeDatabaseError.corruptRecord }
          guard key.record, let item = try itemAt(String(cString: tokenText), side: side),
            item.id.utf8.elementsEqual(key.id.utf8), item.chunkIndex == key.chunk else { throw AgentKnowledgeDatabaseError.corruptRecord }
          try consume(item); previous = key; seen += 1
        }
        guard seen == (side == .incoming ? incomingCount : previousCount), !collationFailed,
          sqlite3_stmt_status(row, SQLITE_STMTSTATUS_SORT, 0) == 0 else { throw AgentKnowledgeDatabaseError.corruptRecord }
      }
      try execute("COMMIT")
    } catch { try? execute("ROLLBACK"); throw error }
  }
  func sourceRevision(side: Side = .incoming, checkActive: () throws -> Void = {}) throws -> String {
    var accumulator = AgentKnowledgeSourceRevision.Accumulator()
    try orderedVisit(side, byIdentity: true) { try checkActive(); try accumulator.append($0); try checkActive() }
    return accumulator.finish()
  }
  func clearAllowed() throws {
    guard phase == .finished else { throw AgentKnowledgeDatabaseError.corruptRecord }
    try execute("DELETE FROM allowed_keys"); allowedCount = 0
  }
  func rememberAllowed(_ id: String) throws {
    guard phase == .finished else { throw AgentKnowledgeDatabaseError.corruptRecord }
    let key = try encodedOrderKey(OrderKey(id: id, chunk: 0, record: false))
    try statement("INSERT OR IGNORE INTO allowed_keys VALUES(?,?)") { row in
      try bind(token(id), at: 1, to: row); try bind(key, at: 2, to: row)
      guard sqlite3_step(row) == SQLITE_DONE, !collationFailed, let database else { throw AgentKnowledgeDatabaseError.corruptRecord }
      allowedCount += Int(sqlite3_changes(database))
    }
  }
  func visitAllowed(_ consume: (String) throws -> Void) throws -> Int {
    try statement("SELECT sort_key,token FROM allowed_keys ORDER BY sort_key COLLATE SOURCE_ORDER") { row in
      var seen = 0, previous: OrderKey?
      while true {
        try Task.checkCancellation()
        let status = sqlite3_step(row)
        if status == SQLITE_DONE { break }
        guard status == SQLITE_ROW, !collationFailed, !closing, let tokenText = sqlite3_column_text(row, 1) else { throw AgentKnowledgeDatabaseError.corruptRecord }
        let key = try orderKey(sqlite3_column_text(row, 0), sqlite3_column_bytes(row, 0))
        guard !key.record, key.chunk == 0, try token(key.id) == String(cString: tokenText) else { throw AgentKnowledgeDatabaseError.corruptRecord }
        if let previous, !less(previous, key) { throw AgentKnowledgeDatabaseError.corruptRecord }
        try consume(key.id); previous = key; seen += 1
      }
      guard seen == allowedCount, !collationFailed, sqlite3_stmt_status(row, SQLITE_STMTSTATUS_SORT, 0) == 0 else { throw AgentKnowledgeDatabaseError.corruptRecord }
      return seen
    }
  }
  private func less(_ a: OrderKey, _ b: OrderKey) -> Bool {
    if a.record != b.record { return !a.record }
    if a.chunk != b.chunk { return a.chunk < b.chunk }
    return a.record ? a.id.utf16.lexicographicallyPrecedes(b.id.utf16) : a.id < b.id
  }
  private func encodedOrderKey(_ value: OrderKey) throws -> String {
    guard let cipherKey, let bytes = try AES.GCM.seal(JSONEncoder().encode(value), using: cipherKey,
      authenticating: Data("source-order:\(job)".utf8)).combined else { throw AgentKnowledgeDatabaseError.unavailable }
    let result = bytes.base64EncodedString()
    guard result.utf8.count <= 65_536 else { throw AgentKnowledgeDatabaseError.corruptRecord }
    return result
  }
  private func orderKey(_ bytes: UnsafeRawPointer?, _ count: Int32) throws -> OrderKey {
    guard let cipherKey, let bytes, (1...65_536).contains(count),
      let sealed = Data(base64Encoded: Data(bytes: bytes, count: Int(count))) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    return try JSONDecoder().decode(OrderKey.self, from: AES.GCM.open(AES.GCM.SealedBox(combined: sealed),
      using: cipherKey, authenticating: Data("source-order:\(job)".utf8)))
  }
  private func compare(_ a: UnsafeRawPointer?, _ ac: Int32, _ b: UnsafeRawPointer?, _ bc: Int32, identity: Bool = false) -> Int32 {
    let left = try? orderKey(a, ac), right = try? orderKey(b, bc)
    if identity, let left, let right {
      return AgentKnowledgeSourceRevision.identityPrecedes(left.id, right.id) ? -1 :
        (AgentKnowledgeSourceRevision.identityPrecedes(right.id, left.id) ? 1 : 0)
    }
    if let left, let right { return less(left, right) ? -1 : (less(right, left) ? 1 : 0) }
    collationFailed = true
    // Keep a deterministic total ordering even after failure; consumers reject
    // the whole scan instead of exposing SQLite's partial corrupt ordering.
    if left != nil { return -1 }; if right != nil { return 1 }
    if ac != bc { return ac < bc ? -1 : 1 }
    guard ac > 0, let a, let b else { return 0 }
    let aa = UnsafeRawBufferPointer(start: a, count: min(Int(ac), 65_536))
    let bb = UnsafeRawBufferPointer(start: b, count: min(Int(bc), 65_536))
    return aa.elementsEqual(bb) ? 0 : (aa.lexicographicallyPrecedes(bb) ? -1 : 1)
  }
  func scan(_ side: Side, consume: (AgentKnowledgeItem) throws -> Void) throws {
    guard phase != .incoming, phase != .closed else { throw AgentKnowledgeDatabaseError.corruptRecord }
    var after = "", seen: Int64 = 0
    while true {
      try Task.checkCancellation()
      let keys: [String] = try statement("SELECT token FROM records WHERE \(side.rawValue) IS NOT NULL AND token>? ORDER BY token LIMIT 64") { row in
        try bind(after, at: 1, to: row)
        var keys: [String] = []
        while true {
          let code = sqlite3_step(row)
          if code == SQLITE_DONE { return keys }
          guard code == SQLITE_ROW, let text = sqlite3_column_text(row, 0) else { throw AgentKnowledgeDatabaseError.corruptRecord }
          keys.append(String(cString: text))
        }
      }
      guard !keys.isEmpty else { break }
      for key in keys {
        try Task.checkCancellation()
        guard key > after, seen < Int64.max, let item = try itemAt(key, side: side) else { throw AgentKnowledgeDatabaseError.corruptRecord }
        try consume(item); seen += 1; after = key
      }
    }
    guard seen == (side == .incoming ? incomingCount : previousCount) else { throw AgentKnowledgeDatabaseError.corruptRecord }
  }
  private func token(_ id: String) throws -> String {
    guard let tokenKey else { throw AgentKnowledgeDatabaseError.unavailable }
    return HMAC<SHA256>.authenticationCode(for: Data(id.utf8), using: tokenKey).map { String(format: "%02x", $0) }.joined()
  }
  private func aad(_ key: String, side: Side) -> Data { Data("source-stage:\(job):\(side.rawValue):\(key)".utf8) }
  private func itemAt(_ key: String, side: Side) throws -> AgentKnowledgeItem? {
    try statement("SELECT \(side.rawValue) FROM records WHERE token=?") { row in
      try bind(key, at: 1, to: row)
      let code = sqlite3_step(row)
      if code == SQLITE_DONE { return nil }
      guard code == SQLITE_ROW else { throw AgentKnowledgeDatabaseError.corruptRecord }
      if sqlite3_column_type(row, 0) == SQLITE_NULL { return nil }
      guard let cipherKey, let bytes = sqlite3_column_blob(row, 0), sqlite3_column_bytes(row, 0) > 0 else { throw AgentKnowledgeDatabaseError.corruptRecord }
      let sealed = Data(bytes: bytes, count: Int(sqlite3_column_bytes(row, 0)))
      let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: cipherKey, authenticating: aad(key, side: side))
      let item = try JSONDecoder.galaxySSI.decode(AgentKnowledgeItem.self, from: plain)
      guard try token(item.id) == key, item.source.utf8.elementsEqual(source.utf8) else { throw AgentKnowledgeDatabaseError.corruptRecord }
      return item
    }
  }
  private func write(_ item: AgentKnowledgeItem, key: String, side: Side, inserting: Bool) throws {
    guard let cipherKey, let sealed = try AES.GCM.seal(JSONEncoder.galaxySSI.encode(item), using: cipherKey,
      authenticating: aad(key, side: side)).combined, let size = Int32(exactly: sealed.count) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    let sql = inserting
      ? "INSERT INTO records(token,\(side.rawValue)) VALUES(?,?) ON CONFLICT(token) DO UPDATE SET \(side.rawValue)=excluded.\(side.rawValue) WHERE records.\(side.rawValue) IS NULL"
      : "UPDATE records SET \(side.rawValue)=?2 WHERE token=?1 AND \(side.rawValue) IS NOT NULL"
    try statement(sql) { row in
      try bind(key, at: 1, to: row)
      guard sealed.withUnsafeBytes({ sqlite3_bind_blob(row, 2, $0.baseAddress, size, Self.transient) }) == SQLITE_OK,
            sqlite3_step(row) == SQLITE_DONE, let database, sqlite3_changes(database) == 1 else { throw AgentKnowledgeDatabaseError.corruptRecord }
    }
  }
  private func bind(_ text: String, at index: Int32, to row: OpaquePointer) throws {
    guard text.withCString({ sqlite3_bind_text(row, index, $0, -1, Self.transient) }) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
  }
  private func execute(_ sql: String) throws {
    guard let database, sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
  }
  private func statement<T>(_ sql: String, _ work: (OpaquePointer) throws -> T) throws -> T {
    guard let database, !closing else { throw AgentKnowledgeDatabaseError.unavailable }
    var raw: OpaquePointer?
    guard AgentKnowledgeSQLiteStatements.shared.prepare(database, sql, -1, &raw, nil) == SQLITE_OK, let row = raw else {
      if let raw { AgentKnowledgeSQLiteStatements.shared.release(raw) }; throw AgentKnowledgeDatabaseError.unavailable
    }
    activeStatements += 1
    defer { AgentKnowledgeSQLiteStatements.shared.release(row); activeStatements -= 1; if closing { close() } }
    do { return try work(row) }
    catch { AgentKnowledgeSQLiteStatements.shared.markFailed(row); throw error }
  }
}
