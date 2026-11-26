import Foundation
import SQLite3

enum AgentKnowledgePrimaryCopyStore {
  struct Job { let key: String; let source: String; let destination: String; let original: Data; var checkpoint: Data }
  private enum Value { case text(String), blob(Data), integer(Int64) }
  static func setup(_ db: OpaquePointer) throws {
    guard sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS knowledge_primary_copy(id INTEGER PRIMARY KEY CHECK(id=1),item_hash TEXT NOT NULL,source_partition TEXT NOT NULL REFERENCES knowledge_primary_partitions(partition_id),destination_partition TEXT NOT NULL REFERENCES knowledge_primary_partitions(partition_id),original BLOB NOT NULL,checkpoint BLOB NOT NULL,CHECK(source_partition<>destination_partition))", nil, nil, nil) == SQLITE_OK else {
      throw AgentKnowledgeDatabaseError.unavailable
    }
  }
  static func load(_ db: OpaquePointer) throws -> Job? {
    try statement(db, "SELECT item_hash,source_partition,destination_partition,substr(original,1,8193),substr(checkpoint,1,8193) FROM knowledge_primary_copy WHERE id=1", []) {
      let status = sqlite3_step($0)
      if status == SQLITE_DONE { return nil }
      guard status == SQLITE_ROW else { throw AgentKnowledgeDatabaseError.unavailable }
      let job = try Job(key: text($0, 0), source: text($0, 1), destination: text($0, 2), original: blob($0, 3), checkpoint: blob($0, 4))
      guard job.key.utf8.count == 64, job.key.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
            UUID(uuidString: job.source)?.uuidString.lowercased() == job.source,
            UUID(uuidString: job.destination)?.uuidString.lowercased() == job.destination,
            job.source != job.destination else { throw AgentKnowledgeDatabaseError.corruptRecord }
      return job
    }
  }
  static func pending(_ db: OpaquePointer) throws -> Bool {
    try statement(db, "SELECT 1 FROM knowledge_primary_copy LIMIT 1", []) { try row($0) }
  }
  static func references(_ db: OpaquePointer, _ id: String) throws -> Bool {
    try statement(db, "SELECT 1 FROM knowledge_primary_copy WHERE source_partition=? OR destination_partition=? LIMIT 1", [.text(id), .text(id)]) { try row($0) }
  }
  static func original(_ db: OpaquePointer, key: String, source: String) throws -> Data? {
    try statement(db, "SELECT substr(sealed_ref,1,8193) FROM knowledge_primary_refs WHERE item_hash=? AND partition_id=?", [.text(key), .text(source)]) {
      guard try row($0) else { return nil }
      return try blob($0, 0)
    }
  }
  static func insert(_ db: OpaquePointer, _ job: Job) throws {
    try run(db, "INSERT INTO knowledge_primary_copy VALUES(1,?,?,?,?,?)", [.text(job.key), .text(job.source), .text(job.destination), .blob(job.original), .blob(job.checkpoint)])
  }
  static func validateOwnership(_ db: OpaquePointer, _ job: Job, bytes: Int64) throws {
    try statement(db, "SELECT 1 FROM knowledge_primary_partitions s JOIN knowledge_primary_partitions d ON d.partition_id=? JOIN knowledge_primary_compaction c ON c.id=1 AND c.source=s.partition_id WHERE s.partition_id=? AND s.sealed=1 AND d.sealed=1 AND d.records=1 AND d.bytes=?", [.text(job.destination), .text(job.source), .integer(bytes)]) {
      guard try row($0) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    }
  }
  static func checkpoint(_ db: OpaquePointer, _ job: Job, sealed: Data, bytes: Int64) throws {
    try run(db, "UPDATE knowledge_primary_partitions SET bytes=? WHERE partition_id=? AND sealed=1 AND records=1", [.integer(bytes), .text(job.destination)])
    try run(db, "UPDATE knowledge_primary_copy SET checkpoint=? WHERE id=1 AND checkpoint=?", [.blob(sealed), .blob(job.checkpoint)])
  }
  static func remove(_ db: OpaquePointer, _ job: Job) throws {
    try run(db, "DELETE FROM knowledge_primary_copy WHERE id=1 AND checkpoint=?", [.blob(job.checkpoint)])
  }
  static func publish(_ db: OpaquePointer, _ job: Job, reference: Data) throws {
    try run(db, "UPDATE knowledge_primary_refs SET partition_id=?,sealed_ref=? WHERE item_hash=? AND partition_id=? AND sealed_ref=?",
      [.text(job.destination), .blob(reference), .text(job.key), .text(job.source), .blob(job.original)])
  }
  private static func run(_ db: OpaquePointer, _ sql: String, _ values: [Value]) throws {
    try statement(db, sql, values) {
      guard sqlite3_step($0) == SQLITE_DONE, sqlite3_changes(db) == 1 else { throw AgentKnowledgeDatabaseError.corruptRecord }
    }
  }
  private static func row(_ statement: OpaquePointer) throws -> Bool {
    let status = sqlite3_step(statement)
    guard status == SQLITE_ROW || status == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
    return status == SQLITE_ROW
  }
  private static func text(_ statement: OpaquePointer, _ column: Int32) throws -> String {
    guard let text = sqlite3_column_text(statement, column) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    return String(cString: text)
  }
  private static func blob(_ statement: OpaquePointer, _ column: Int32) throws -> Data {
    let count = sqlite3_column_bytes(statement, column)
    guard (1...8192).contains(count), let value = sqlite3_column_blob(statement, column) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    return Data(bytes: value, count: Int(count))
  }
  private static func statement<T>(_ db: OpaquePointer, _ sql: String, _ values: [Value], _ action: (OpaquePointer) throws -> T) throws -> T {
    var raw: OpaquePointer?
    guard AgentKnowledgeSQLiteStatements.shared.prepare(db, sql, -1, &raw, nil) == SQLITE_OK, let statement = raw else {
      if let raw { AgentKnowledgeSQLiteStatements.shared.release(raw) }; throw AgentKnowledgeDatabaseError.unavailable
    }
    defer { AgentKnowledgeSQLiteStatements.shared.release(statement) }
    for (offset, value) in values.enumerated() {
      let index = Int32(offset + 1), code: Int32
      switch value {
      case .text(let text): code = text.withCString { sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
      case .blob(let data): code = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
      case .integer(let number): code = sqlite3_bind_int64(statement, index, number)
      }
      guard code == SQLITE_OK else { AgentKnowledgeSQLiteStatements.shared.markFailed(statement); throw AgentKnowledgeDatabaseError.unavailable }
    }
    return try action(statement)
  }
}
