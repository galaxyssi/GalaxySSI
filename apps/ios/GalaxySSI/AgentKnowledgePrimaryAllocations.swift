import Darwin
import Foundation
import SQLite3

// Separate from the catalog transaction: rolling that transaction back must not
// erase the only durable ownership record for a newly created physical file.
final class AgentKnowledgePrimaryAllocations {
  struct Page { var visited: Int; var orphaned: Int; var complete: Bool }
  private let root: URL
  private var file: URL { root.appendingPathComponent(".allocations.sqlite") }
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  init(root: URL) { self.root = root }

  func remember(_ id: String, syncParent: () throws -> Void) throws {
    try validate(id)
    do {
      let db = try open(writable: true)
      defer { AgentKnowledgeSQLiteStatements.shared.close(db) }
      let insert = try prepare(db, "INSERT INTO pending(partition_id) VALUES(?)")
      defer { AgentKnowledgeSQLiteStatements.shared.release(insert) }
      try bind(id, insert)
      guard sqlite3_step(insert) == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
      try AgentKnowledgePrimaryDurability.verify(db, role: .primary)
    }
    try syncParent()
  }

  func hasPending() throws -> Bool {
    guard try regularOrMissing(file) else { return false }
    let db = try open(writable: false)
    defer { AgentKnowledgeSQLiteStatements.shared.close(db) }
    if try version(db) == 0 { return false }
    return try pending(db)
  }

  // Caller owns the existing cross-process EX payload lease and no catalog transaction.
  func replay(limit: Int, referenced: (String) throws -> Bool, verify: (String) throws -> Void,
              remove: (String) throws -> Void, checkActive: () throws -> Void) throws -> Page {
    guard (1...64).contains(limit) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    try checkActive()
    guard try regularOrMissing(file) else { return Page(visited: 0, orphaned: 0, complete: true) }
    let db = try open(writable: true)
    defer { AgentKnowledgeSQLiteStatements.shared.close(db) }
    try execute(db, "BEGIN IMMEDIATE TRANSACTION")
    var committed = false
    defer { if !committed { try? execute(db, "ROLLBACK") } }
    let select = try prepare(db, "SELECT partition_id FROM pending ORDER BY partition_id LIMIT ?")
    defer { AgentKnowledgeSQLiteStatements.shared.release(select) }
    sqlite3_bind_int(select, 1, Int32(limit))
    var ids: [String] = []
    while true {
      let step = sqlite3_step(select)
      if step == SQLITE_DONE { break }
      guard step == SQLITE_ROW, let text = sqlite3_column_text(select, 0) else { throw AgentKnowledgeDatabaseError.corruptRecord }
      let id = String(cString: text)
      try validate(id)
      ids.append(id)
    }
    var orphaned = 0
    for id in ids {
      try Task.checkCancellation()
      try checkActive()
      if try referenced(id) { try verify(id) }
      else { try remove(id); orphaned += 1 }
      let delete = try prepare(db, "DELETE FROM pending WHERE partition_id=?")
      defer { AgentKnowledgeSQLiteStatements.shared.release(delete) }
      try bind(id, delete)
      guard sqlite3_step(delete) == SQLITE_DONE, sqlite3_changes(db) == 1 else { throw AgentKnowledgeDatabaseError.unavailable }
    }
    let complete = try !pending(db)
    try Task.checkCancellation()
    try checkActive()
    try AgentKnowledgePrimaryDurability.verify(db, role: .primary)
    try execute(db, "COMMIT")
    committed = true
    return Page(visited: ids.count, orphaned: orphaned, complete: complete)
  }

  private func open(writable: Bool) throws -> OpaquePointer {
    for suffix in ["", "-wal", "-shm", "-journal"] { _ = try regularOrMissing(URL(fileURLWithPath: file.path + suffix)) }
    var handle: OpaquePointer?
    let flags = SQLITE_OPEN_FULLMUTEX | (writable ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY)
    guard sqlite3_open_v2(file.path, &handle, flags, nil) == SQLITE_OK, let db = handle else {
      if let handle { AgentKnowledgeSQLiteStatements.shared.close(handle) }; throw AgentKnowledgeDatabaseError.unavailable
    }
    var ready = false
    defer { if !ready { AgentKnowledgeSQLiteStatements.shared.close(db) } }
    sqlite3_busy_timeout(db, 5_000)
    try execute(db, "PRAGMA cache_size=-256")
    try execute(db, "PRAGMA mmap_size=0")
    if writable {
      try AgentKnowledgePrimaryDurability.configure(db, role: .primary)
      try execute(db, "BEGIN IMMEDIATE TRANSACTION")
      var committed = false
      defer { if !committed { try? execute(db, "ROLLBACK") } }
      let current = try version(db)
      if current == 0 {
        try execute(db, "CREATE TABLE pending(partition_id TEXT PRIMARY KEY NOT NULL) WITHOUT ROWID")
        try execute(db, "PRAGMA user_version=1")
      }
      try execute(db, "COMMIT")
      committed = true
      for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: file.path + suffix) {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
          .posixPermissions: 0o600], ofItemAtPath: file.path + suffix)
      }
    } else { _ = try version(db) }
    ready = true
    return db
  }

  private func version(_ db: OpaquePointer) throws -> Int32 {
    let statement = try prepare(db, "PRAGMA user_version")
    defer { AgentKnowledgeSQLiteStatements.shared.release(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw AgentKnowledgeDatabaseError.corruptRecord }
    let value = sqlite3_column_int(statement, 0)
    guard (0...1).contains(value) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    return value
  }
  private func pending(_ db: OpaquePointer) throws -> Bool {
    let statement = try prepare(db, "SELECT 1 FROM pending LIMIT 1")
    defer { AgentKnowledgeSQLiteStatements.shared.release(statement) }
    let state = sqlite3_step(statement)
    guard state == SQLITE_ROW || state == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
    return state == SQLITE_ROW
  }
  private func regularOrMissing(_ url: URL) throws -> Bool {
    var info = stat()
    if Darwin.lstat(url.path, &info) != 0 {
      if errno == ENOENT { return false }
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    return true
  }
  private func validate(_ id: String) throws {
    guard UUID(uuidString: id)?.uuidString.lowercased() == id else { throw AgentKnowledgeDatabaseError.corruptRecord }
  }
  private func prepare(_ db: OpaquePointer, _ sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard AgentKnowledgeSQLiteStatements.shared.prepare(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      if let statement { AgentKnowledgeSQLiteStatements.shared.release(statement) }; throw AgentKnowledgeDatabaseError.unavailable
    }
    return statement
  }
  private func execute(_ db: OpaquePointer, _ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
  }
  private func bind(_ id: String, _ statement: OpaquePointer) throws {
    guard id.withCString({ sqlite3_bind_text(statement, 1, $0, -1, Self.transient) }) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
  }
}
