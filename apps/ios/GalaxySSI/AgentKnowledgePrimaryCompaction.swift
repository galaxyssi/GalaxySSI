import Foundation
import SQLite3

// Caller holds the physical EX lease and an IMMEDIATE catalog transaction.
enum AgentKnowledgePrimaryCompaction {
  static func setup(_ db: OpaquePointer) throws {
    for sql in [
      "CREATE TABLE IF NOT EXISTS knowledge_primary_dirty(partition_id TEXT PRIMARY KEY)",
      "CREATE TABLE IF NOT EXISTS knowledge_primary_compaction(id INTEGER PRIMARY KEY CHECK(id=1),after_partition TEXT NOT NULL,discovered INTEGER NOT NULL CHECK(discovered IN (0,1)),source TEXT NOT NULL)",
      "INSERT OR IGNORE INTO knowledge_primary_compaction VALUES(1,'',0,'')",
      "CREATE TRIGGER IF NOT EXISTS knowledge_primary_dirty_insert AFTER INSERT ON knowledge_primary_partitions BEGIN INSERT OR IGNORE INTO knowledge_primary_dirty VALUES(NEW.partition_id); END",
      "CREATE TRIGGER IF NOT EXISTS knowledge_primary_dirty_delete AFTER DELETE ON knowledge_primary_refs BEGIN INSERT OR IGNORE INTO knowledge_primary_dirty VALUES(OLD.partition_id); END",
      "CREATE TRIGGER IF NOT EXISTS knowledge_primary_dirty_move AFTER UPDATE OF partition_id ON knowledge_primary_refs WHEN OLD.partition_id<>NEW.partition_id BEGIN INSERT OR IGNORE INTO knowledge_primary_dirty VALUES(OLD.partition_id); END"
    ] { try execute(db, sql) }
  }

  @discardableResult
  static func advance(_ db: OpaquePointer, checkActive: () throws -> Void,
                      resumeCopy: () throws -> Int = { throw AgentKnowledgeDatabaseError.corruptRecord },
                      relocate: (String, String) throws -> Bool) throws -> Int {
    guard sqlite3_get_autocommit(db) == 0 else { throw AgentKnowledgeDatabaseError.corruptRecord }
    if try AgentKnowledgePrimaryCopyStore.pending(db) {
      let moved = try resumeCopy()
      try finishSource(db)
      return moved
    }
    try discover(db, checkActive: checkActive)
    var source = try strings(db, "SELECT source FROM knowledge_primary_compaction WHERE id=1").first
    guard source != nil else { throw AgentKnowledgeDatabaseError.corruptRecord }
    if source == "" { source = try select(db, checkActive: checkActive) }
    guard let source else { return 0 }
    try token(source)
    guard try strings(db, "SELECT partition_id FROM knowledge_primary_partitions WHERE partition_id=? AND sealed=1", [source]) == [source] else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    let keys = try strings(db, "SELECT item_hash FROM knowledge_primary_refs WHERE partition_id=? ORDER BY item_hash LIMIT 8", [source])
    var moved = 0
    for key in keys {
      do {
        try Task.checkCancellation(); try checkActive()
        if try !relocate(key, source) { break }
        moved += 1
      } catch let yield as AgentKnowledgeStorageYield {
        if moved == 0 { throw yield }
        break
      }
    }
    try finishSource(db)
    return moved
  }
  private static func finishSource(_ db: OpaquePointer) throws {
    if try AgentKnowledgePrimaryCopyStore.pending(db) { return }
    guard let source = try strings(db, "SELECT source FROM knowledge_primary_compaction WHERE id=1").first else { throw AgentKnowledgeDatabaseError.corruptRecord }
    if source.isEmpty { return }
    if try strings(db, "SELECT item_hash FROM knowledge_primary_refs WHERE partition_id=? LIMIT 1", [source]).isEmpty {
      try retire(db, source)
      try run(db, "UPDATE knowledge_primary_compaction SET source='' WHERE id=1")
    }
  }

  static func pending(_ db: OpaquePointer) throws -> Bool {
    try !strings(db, "SELECT '1' FROM knowledge_primary_dirty UNION ALL SELECT '1' FROM knowledge_primary_retired UNION ALL SELECT '1' FROM knowledge_primary_copy UNION ALL SELECT '1' FROM knowledge_primary_compaction WHERE discovered=0 OR source<>'' LIMIT 1").isEmpty
  }

  private static func discover(_ db: OpaquePointer, checkActive: () throws -> Void) throws {
    guard let after = try strings(db, "SELECT after_partition FROM knowledge_primary_compaction WHERE id=1 AND discovered=0").first else { return }
    if !after.isEmpty { try token(after) }
    let keys = try strings(db, "SELECT partition_id FROM knowledge_primary_partitions WHERE partition_id>? ORDER BY partition_id LIMIT 32", [after])
    for key in keys {
      try Task.checkCancellation(); try checkActive(); try token(key)
      try run(db, "INSERT OR IGNORE INTO knowledge_primary_dirty VALUES(?)", [key])
    }
    try run(db, "UPDATE knowledge_primary_compaction SET after_partition=?,discovered=? WHERE id=1", [keys.last ?? after, keys.count < 32 ? "1" : "0"])
  }

  private static func select(_ db: OpaquePointer, checkActive: () throws -> Void) throws -> String? {
    for key in try strings(db, "SELECT partition_id FROM knowledge_primary_dirty ORDER BY partition_id LIMIT 8") {
      try Task.checkCancellation(); try checkActive(); try token(key)
      let rows = try strings(db, "SELECT records FROM knowledge_primary_partitions WHERE partition_id=?", [key])
      if let value = rows.first {
        guard let records = Int64(value), records >= 0,
              let count = try strings(db, "SELECT COUNT(*) FROM knowledge_primary_refs WHERE partition_id=?", [key]).first,
              let live = Int64(count), live >= 0, live <= records else { throw AgentKnowledgeDatabaseError.corruptRecord }
        if live == 0 { try retire(db, key); continue }
        if live <= records / 2 {
          try run(db, "UPDATE knowledge_primary_partitions SET sealed=1 WHERE partition_id=?", [key])
          try run(db, "UPDATE knowledge_primary_compaction SET source=? WHERE id=1", [key])
          return key
        }
      }
      try run(db, "DELETE FROM knowledge_primary_dirty WHERE partition_id=?", [key])
    }
    return nil
  }
  static func retire(_ db: OpaquePointer, _ key: String) throws {
    guard try !AgentKnowledgePrimaryCopyStore.references(db, key) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    guard try strings(db, "SELECT item_hash FROM knowledge_primary_refs WHERE partition_id=? LIMIT 1", [key]).isEmpty else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    try run(db, "INSERT OR IGNORE INTO knowledge_primary_retired VALUES(?)", [key])
    try run(db, "DELETE FROM knowledge_primary_partitions WHERE partition_id=?", [key])
    try run(db, "DELETE FROM knowledge_primary_dirty WHERE partition_id=?", [key])
  }
  private static func token(_ key: String) throws {
    guard UUID(uuidString: key)?.uuidString.lowercased() == key else { throw AgentKnowledgeDatabaseError.corruptRecord }
  }
  private static func execute(_ db: OpaquePointer, _ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
  }
  private static func withStatement<T>(_ db: OpaquePointer, _ sql: String, _ values: [String],
                                      _ action: (OpaquePointer) throws -> T) throws -> T {
    var raw: OpaquePointer?
    guard AgentKnowledgeSQLiteStatements.shared.prepare(db, sql, -1, &raw, nil) == SQLITE_OK, let statement = raw else {
      if let raw { AgentKnowledgeSQLiteStatements.shared.release(raw) }
      throw AgentKnowledgeDatabaseError.unavailable
    }
    defer { AgentKnowledgeSQLiteStatements.shared.release(statement) }
    for (offset, value) in values.enumerated() {
      guard value.withCString({ sqlite3_bind_text(statement, Int32(offset + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }) == SQLITE_OK else {
        AgentKnowledgeSQLiteStatements.shared.markFailed(statement); throw AgentKnowledgeDatabaseError.unavailable
      }
    }
    return try action(statement)
  }
  private static func strings(_ db: OpaquePointer, _ sql: String, _ values: [String] = []) throws -> [String] {
    try withStatement(db, sql, values) { statement in
      var result: [String] = []
      while true {
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return result }
        guard step == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw AgentKnowledgeDatabaseError.unavailable }
        result.append(String(cString: text))
      }
    }
  }
  private static func run(_ db: OpaquePointer, _ sql: String, _ values: [String] = []) throws {
    try withStatement(db, sql, values) {
      guard sqlite3_step($0) == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
    }
  }
}
