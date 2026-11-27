import CryptoKit
import Foundation
import SQLite3

// Compact authenticated record integrity headers, not the central source directory.
enum AgentKnowledgePrimaryMetadata {
  struct Header: Codable {
    var version = 1
    var itemHash: String
    var sourceHash: String
    var updatedAtMillis: Int64
    var bodySHA256: String
  }
  struct Resolved { let encrypted: Data; let bodySHA256: String }
  static let maximumHeaderBytes = 4_096
  private static let prefix = Data("khp1:".utf8)

  static func hash(_ encrypted: Data) throws -> String {
    guard (1...maximumHeaderBytes).contains(encrypted.count) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    return SHA256.hash(data: encrypted).map { String(format: "%02x", $0) }.joined()
  }
  static func pointer(_ encrypted: Data) throws -> Data { try prefix + Data(hash(encrypted).utf8) }
  static func pointerHash(_ stored: Data) throws -> String? {
    guard stored.starts(with: prefix) else { return nil }
    let value = String(decoding: stored.dropFirst(prefix.count), as: UTF8.self)
    guard stored.count == 69, digest(value) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    return value
  }
  static func digest(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
  static func purpose(_ hash: String) -> String { "agent-knowledge-primary-header:v1:\(hash)" }

  static func configure(_ db: OpaquePointer, writable: Bool) throws {
    var raw: OpaquePointer?
    guard AgentKnowledgeSQLiteStatements.shared.prepare(db, "PRAGMA user_version", -1, &raw, nil) == SQLITE_OK, let row = raw else {
      if let raw { AgentKnowledgeSQLiteStatements.shared.release(raw) }; throw AgentKnowledgeDatabaseError.unavailable
    }
    let status = sqlite3_step(row)
    guard status == SQLITE_ROW else { AgentKnowledgeSQLiteStatements.shared.release(row); throw AgentKnowledgeDatabaseError.unavailable }
    let version = sqlite3_column_int(row, 0)
    AgentKnowledgeSQLiteStatements.shared.release(row)
    guard (0...2).contains(version) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    if writable && version < 2 {
      try execute(db, "BEGIN IMMEDIATE TRANSACTION")
      var committed = false
      defer { if !committed { try? execute(db, "ROLLBACK") } }
      try execute(db, "CREATE TABLE headers(entry_id TEXT PRIMARY KEY,sealed BLOB NOT NULL) WITHOUT ROWID")
      try execute(db, "PRAGMA user_version=2")
      try AgentKnowledgePrimaryDurability.verify(db, role: .primary)
      try execute(db, "COMMIT"); committed = true
    }
  }
  @discardableResult static func write(_ db: OpaquePointer, entry: String, encrypted: Data) throws -> Int64 {
    guard sqlite3_get_autocommit(db) == 0 else { throw AgentKnowledgeDatabaseError.corruptRecord }
    _ = try hash(encrypted)
    try statement(db, "DELETE FROM headers WHERE entry_id=?", entry: entry) {
      guard sqlite3_step($0) == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
    }
    try statement(db, "INSERT INTO headers(entry_id,sealed) VALUES(?,?)", entry: entry) { row in
      let code = encrypted.withUnsafeBytes { sqlite3_bind_blob(row, 2, $0.baseAddress, Int32($0.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
      guard code == SQLITE_OK else { AgentKnowledgeSQLiteStatements.shared.markFailed(row); throw AgentKnowledgeDatabaseError.unavailable }
      guard sqlite3_step(row) == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
    }
    return Int64(encrypted.count)
  }
  static func read(_ db: OpaquePointer, entry: String, expected: String) throws -> Data {
    guard digest(expected) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    return try statement(db, "SELECT substr(sealed,1,4097) FROM headers WHERE entry_id=?", entry: entry) {
      guard sqlite3_step($0) == SQLITE_ROW, (1...maximumHeaderBytes).contains(Int(sqlite3_column_bytes($0, 0))),
            let raw = sqlite3_column_blob($0, 0) else { throw AgentKnowledgeDatabaseError.corruptRecord }
      let encrypted = Data(bytes: raw, count: Int(sqlite3_column_bytes($0, 0)))
      guard try hash(encrypted) == expected else { throw AgentKnowledgeDatabaseError.corruptRecord }
      return encrypted
    }
  }
  private static func execute(_ db: OpaquePointer, _ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
  }
  private static func statement<T>(_ db: OpaquePointer, _ sql: String, entry: String, _ action: (OpaquePointer) throws -> T) throws -> T {
    var raw: OpaquePointer?
    guard AgentKnowledgeSQLiteStatements.shared.prepare(db, sql, -1, &raw, nil) == SQLITE_OK, let statement = raw else {
      if let raw { AgentKnowledgeSQLiteStatements.shared.release(raw) }; throw AgentKnowledgeDatabaseError.unavailable
    }
    defer { AgentKnowledgeSQLiteStatements.shared.release(statement) }
    guard entry.withCString({ sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }) == SQLITE_OK else {
      AgentKnowledgeSQLiteStatements.shared.markFailed(statement); throw AgentKnowledgeDatabaseError.unavailable
    }
    return try action(statement)
  }
}
