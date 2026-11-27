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
  private(set) var incomingCount: Int64 = 0
  private var previousCount: Int64 = 0
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
      try execute("PRAGMA journal_mode=DELETE"); try execute("PRAGMA synchronous=FULL")
      try execute("PRAGMA cache_size=-2048"); try execute("PRAGMA mmap_size=0"); try execute("PRAGMA temp_store=FILE")
      try execute("CREATE TABLE records(token TEXT PRIMARY KEY,incoming BLOB,previous BLOB) WITHOUT ROWID")
      try execute("BEGIN IMMEDIATE")
    } catch { close(); throw error }
  }
  deinit { close() }
  func close() {
    guard phase != .closed else { return }; phase = .closed
    if let database { sqlite3_close_v2(database); self.database = nil }
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
    guard let database else { throw AgentKnowledgeDatabaseError.unavailable }
    var raw: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &raw, nil) == SQLITE_OK, let row = raw else {
      if let raw { sqlite3_finalize(raw) }; throw AgentKnowledgeDatabaseError.unavailable
    }
    defer { sqlite3_finalize(row) }
    return try work(row)
  }
}
