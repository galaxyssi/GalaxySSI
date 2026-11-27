import Foundation
import SQLite3

// Thread-confined: each query owns its views. Pins committed WAL without entering
// the canonical connection's writer lock.
// The owner supplies its lifecycle generation check; this is not an immutable
// database URI, which would ignore live WAL commits.
final class AgentKnowledgeCommittedReadView {
  private var database: OpaquePointer?
  private var primarySnapshotLease: AgentKnowledgePrimaryPartitions.SnapshotLease?
  private let checkActive: () throws -> Void
  private let indexMemoScope: AgentKnowledgeIndexOperationScope?
  private var activeReads = 0, closing = false
  private(set) var revision: Int64 = 0

  init(fileURL: URL, primarySnapshotLease: AgentKnowledgePrimaryPartitions.SnapshotLease? = nil,
    indexMemoScope: AgentKnowledgeIndexOperationScope? = nil,
    checkActive: @escaping () throws -> Void) throws {
    self.primarySnapshotLease = primarySnapshotLease
    self.checkActive = checkActive
    self.indexMemoScope = indexMemoScope
    do {
      try Task.checkCancellation(); try checkActive()
      guard sqlite3_open_v2(fileURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
        let database else { throw AgentKnowledgeDatabaseError.unavailable }
      sqlite3_busy_timeout(database, 5_000)
      for sql in ["PRAGMA query_only=ON", "PRAGMA cache_size=-2048", "PRAGMA mmap_size=0", "BEGIN DEFERRED TRANSACTION"] {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
      }
      var row: OpaquePointer?
      guard AgentKnowledgeSQLiteStatements.shared.prepare(database, "SELECT revision FROM knowledge_browse_revision WHERE id=1", -1, &row, nil) == SQLITE_OK, let row else {
        if let row { AgentKnowledgeSQLiteStatements.shared.release(row) }; throw AgentKnowledgeDatabaseError.unavailable
      }
      defer { AgentKnowledgeSQLiteStatements.shared.release(row) }
      guard sqlite3_step(row) == SQLITE_ROW, sqlite3_column_type(row, 0) == SQLITE_INTEGER else { throw AgentKnowledgeDatabaseError.unavailable }
      revision = sqlite3_column_int64(row, 0)
      guard revision >= 0, sqlite3_step(row) == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.corruptRecord }
      try Task.checkCancellation(); try checkActive()
    } catch { close(); throw error }
  }
  deinit { close() }
  func read<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
    guard let indexMemoScope else { return try readWithinOperation(body) }
    return try indexMemoScope.withOperation { try readWithinOperation(body) }
  }
  private func readWithinOperation<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
    guard let database, !closing else { throw AgentKnowledgeDatabaseError.unavailable }
    try Task.checkCancellation(); try checkActive()
    activeReads += 1
    defer { activeReads -= 1; if closing { close() } }
    let value = try body(database)
    guard !closing else { throw AgentKnowledgeDatabaseError.unavailable }
    try Task.checkCancellation(); try checkActive()
    return value
  }
  func close() {
    if activeReads > 0 { closing = true; return }
    if let database {
      _ = sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
      // This private view owns the handle, including any escaped raw cursors.
      AgentKnowledgeSQLiteStatements.shared.close(database, finalizingUnmanaged: true); self.database = nil
    }
    // Release physical retention only after statements, WAL and handle are closed.
    primarySnapshotLease = nil
    closing = true
  }
}
