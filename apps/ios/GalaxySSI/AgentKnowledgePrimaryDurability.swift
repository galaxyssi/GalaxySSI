import SQLite3

enum AgentKnowledgePrimaryDurability {
  enum Role: Equatable { case catalog, primary }
  enum Failure: Error { case invalidWriter, activeTransaction, sqlite, configuration }

  static func configure(_ handle: OpaquePointer?, role: Role) throws {
    guard let handle, sqlite3_db_readonly(handle, "main") == 0 else { throw Failure.invalidWriter }
    guard sqlite3_get_autocommit(handle) != 0 else { throw Failure.activeTransaction }
    let synchronous = role == .primary ? "EXTRA" : "FULL"
    for sql in ["PRAGMA journal_mode=WAL", "PRAGMA synchronous=\(synchronous)",
      "PRAGMA fullfsync=ON", "PRAGMA checkpoint_fullfsync=ON"] {
      guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw Failure.sqlite }
    }
    try verify(handle, role: role)
  }

  static func verify(_ handle: OpaquePointer?, role: Role) throws {
    guard let handle, sqlite3_db_readonly(handle, "main") == 0 else { throw Failure.invalidWriter }
    // WAL deliberately remains the iOS reader/writer contract. EXTRA adds no
    // WAL durability beyond FULL, but read back the requested body setting too.
    guard try scalar(handle, "PRAGMA journal_mode").lowercased() == "wal",
          try scalar(handle, "PRAGMA synchronous") == (role == .primary ? "3" : "2"),
          try scalar(handle, "PRAGMA fullfsync") == "1",
          try scalar(handle, "PRAGMA checkpoint_fullfsync") == "1" else { throw Failure.configuration }
  }

  private static func scalar(_ handle: OpaquePointer, _ sql: String) throws -> String {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
      if let statement { sqlite3_finalize(statement) }
      throw Failure.sqlite
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_text(statement, 0) else { throw Failure.configuration }
    let value = String(cString: bytes)
    guard sqlite3_step(statement) == SQLITE_DONE else { throw Failure.sqlite }
    return value
  }
}
