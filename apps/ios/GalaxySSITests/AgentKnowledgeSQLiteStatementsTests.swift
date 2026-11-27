import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeSQLiteStatementsTests: XCTestCase {
  private enum Fault: Error { case injected }
  private final class Fixture {
    var database: OpaquePointer!
    let pool: AgentKnowledgeStatementPool
    init(capacity: Int = 32, chars: Int = 65_536) throws {
      var raw: OpaquePointer?
      guard sqlite3_open(":memory:", &raw) == SQLITE_OK, let raw else { throw Fault.injected }
      database = raw
      do { pool = try AgentKnowledgeStatementPool(database: raw, capacity: capacity, maximumSQLCharacters: chars) }
      catch { sqlite3_close_v2(raw); throw error }
    }
    deinit { pool.close(); if let database { sqlite3_close_v2(database) } }
    func sql(_ sql: String) throws {
      guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw Fault.injected }
    }
  }

  func testReuseResetsResultsAndClearsOldBindings() throws {
    let f = try Fixture(), first = try f.pool.acquire("SELECT ?")
    try first.access {
      XCTAssertEqual(sqlite3_bind_text($0, 1, "private binding", -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)), SQLITE_OK)
      XCTAssertEqual(sqlite3_step($0), SQLITE_ROW)
    }
    XCTAssertEqual(first.close(), SQLITE_OK)
    let second = try f.pool.acquire("SELECT ?")
    try second.access { XCTAssertEqual(sqlite3_step($0), SQLITE_ROW); XCTAssertEqual(sqlite3_column_type($0, 0), SQLITE_NULL) }
    second.close()
    XCTAssertEqual(f.pool.stats.prepared, 1)
    XCTAssertEqual(f.pool.stats.reused, 1)
  }

  func testIdenticalActiveCursorsRemainExclusive() throws {
    let f = try Fixture(), first = try f.pool.acquire("SELECT ?"), second = try f.pool.acquire("SELECT ?")
    XCTAssertNotEqual(try first.access { $0 }, try second.access { $0 })
    try first.access { sqlite3_bind_int($0, 1, 11); XCTAssertEqual(sqlite3_step($0), SQLITE_ROW) }
    try second.access { sqlite3_bind_int($0, 1, 22); XCTAssertEqual(sqlite3_step($0), SQLITE_ROW) }
    XCTAssertEqual(try first.access { sqlite3_column_int($0, 0) }, 11)
    XCTAssertEqual(try second.access { sqlite3_column_int($0, 0) }, 22)
    first.close(); second.close()
    XCTAssertEqual(f.pool.stats.idle, 1)
    XCTAssertEqual(f.pool.stats.evicted, 1)
  }

  func testIdleEntryBoundEvictsTheOldestReturnedStatement() throws {
    let f = try Fixture(capacity: 2)
    for value in 1...3 { try f.pool.acquire("SELECT \(value)").close() }
    XCTAssertEqual(f.pool.stats.idle, 2)
    XCTAssertEqual(f.pool.stats.evicted, 1)
    try f.pool.acquire("SELECT 1").close()
    XCTAssertEqual(f.pool.stats.prepared, 4)
    try f.pool.acquire("SELECT 3").close()
    XCTAssertEqual(f.pool.stats.reused, 1)
  }

  func testSQLCharacterBudgetAndOversizedStatementsStayBounded() throws {
    let f = try Fixture(chars: 20)
    try f.pool.acquire("SELECT 11111").close()
    try f.pool.acquire("SELECT 22222").close()
    XCTAssertEqual(f.pool.stats.idle, 1)
    XCTAssertLessThanOrEqual(f.pool.stats.sqlChars, 20)
    try f.pool.acquire("SELECT 1 /*" + String(repeating: "x", count: 50) + "*/").close()
    XCTAssertEqual(f.pool.stats.idle, 1)
    XCTAssertLessThanOrEqual(f.pool.stats.sqlChars, 20)
  }

  func testSQLBudgetCountsUTF16UnitsLikeAndroid() throws {
    let sql = "SELECT '\u{1F680}'"
    let f = try Fixture(chars: sql.count)
    try f.pool.acquire(sql).close()
    XCTAssertEqual(f.pool.stats.idle, 0)
  }

  func testZeroCapacityDisablesReuseAndInvalidBoundsFail() throws {
    XCTAssertThrowsError(try Fixture(capacity: -1))
    XCTAssertThrowsError(try Fixture(chars: -1))
    let f = try Fixture(capacity: 0)
    try f.pool.acquire("SELECT 1").close(); try f.pool.acquire("SELECT 1").close()
    XCTAssertEqual(f.pool.stats.idle, 0)
    XCTAssertEqual(f.pool.stats.prepared, 2)
    XCTAssertEqual(f.pool.stats.reused, 0)
  }

  func testThrowingLeaseAccessDiscardsItsStatement() throws {
    let f = try Fixture(), lease = try f.pool.acquire("SELECT 1")
    XCTAssertThrowsError(try lease.access { _ in throw Fault.injected })
    lease.close()
    XCTAssertEqual(f.pool.stats.idle, 0)
    try f.pool.acquire("SELECT 1").close()
    XCTAssertEqual(f.pool.stats.prepared, 2)
  }

  func testSQLiteExecutionFailureIsDiscardedOnReset() throws {
    let f = try Fixture()
    try f.sql("CREATE TABLE rows(id INTEGER PRIMARY KEY)")
    let first = try f.pool.acquire("INSERT INTO rows VALUES(?)")
    try first.access { sqlite3_bind_int($0, 1, 1); XCTAssertEqual(sqlite3_step($0), SQLITE_DONE) }
    first.close()
    let duplicate = try f.pool.acquire("INSERT INTO rows VALUES(?)")
    try duplicate.access { sqlite3_bind_int($0, 1, 1); XCTAssertEqual(sqlite3_step($0) & 255, SQLITE_CONSTRAINT) }
    XCTAssertEqual(duplicate.close() & 255, SQLITE_CONSTRAINT)
    XCTAssertEqual(f.pool.stats.idle, 0)
  }

  func testPoolCloseInvalidatesAccessAndLateLeaseReturnIsSafe() throws {
    let f = try Fixture(), lease = try f.pool.acquire("SELECT 1")
    f.pool.close()
    XCTAssertThrowsError(try lease.access { sqlite3_step($0) })
    XCTAssertThrowsError(try f.pool.acquire("SELECT 2"))
    lease.close(); lease.close()
    XCTAssertNil(sqlite3_next_stmt(f.database, nil))
    XCTAssertEqual(f.pool.stats.active, 0)
  }

  func testOldLeaseCannotReturnAnEntryTwiceAfterReuse() throws {
    let f = try Fixture(), old = try f.pool.acquire("SELECT 1")
    old.close()
    let current = try f.pool.acquire("SELECT 1")
    old.close()
    XCTAssertEqual(f.pool.stats.active, 1)
    XCTAssertEqual(try current.access { sqlite3_step($0) }, SQLITE_ROW)
    XCTAssertThrowsError(try old.access { sqlite3_step($0) })
    current.close()
  }

  func testPragmaAndTransactionProgramsAreNeverRetainedIdle() throws {
    let f = try Fixture(), first = try f.pool.acquire("PRAGMA user_version")
    XCTAssertEqual(try first.access { sqlite3_step($0) }, SQLITE_ROW)
    first.close()
    try f.sql("PRAGMA user_version=7")
    let next = try f.pool.acquire("PRAGMA user_version")
    XCTAssertEqual(try next.access { sqlite3_step($0) }, SQLITE_ROW)
    XCTAssertEqual(try next.access { sqlite3_column_int($0, 0) }, 7)
    next.close()
    for sql in ["BEGIN", "ROLLBACK"] {
      let control = try f.pool.acquire(sql)
      XCTAssertEqual(try control.access { sqlite3_step($0) }, SQLITE_DONE)
      control.close()
    }
    XCTAssertEqual(f.pool.stats.idle, 0)
    XCTAssertEqual(f.pool.stats.reused, 0)
  }

  func testCompatibilityCloseDrainsOutstandingRawBorrows() throws {
    let f = try Fixture(), driver = AgentKnowledgeSQLiteStatements()
    let database = try XCTUnwrap(f.database)
    var statement: OpaquePointer?
    XCTAssertEqual(driver.prepare(database, "SELECT ?", -1, &statement, nil), SQLITE_OK)
    XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
    XCTAssertEqual(driver.close(database), SQLITE_OK)
    f.database = nil
    XCTAssertNil(driver.stats(for: database))
    XCTAssertEqual(driver.release(statement), SQLITE_MISUSE)
  }

  func testCompatibilityHandlesEmptySQLByteSpansAndBindingFailure() throws {
    let f = try Fixture(), driver = AgentKnowledgeSQLiteStatements()
    let database = try XCTUnwrap(f.database)
    var statement: OpaquePointer?
    XCTAssertEqual(driver.prepare(database, "", -1, &statement, nil), SQLITE_OK)
    XCTAssertNil(statement)
    XCTAssertNotEqual(driver.prepare(database, "INVALID SQL", -1, &statement, nil), SQLITE_OK)
    XCTAssertEqual(driver.prepare(database, "SELECT 1; SELECT 2", 8, &statement, nil), SQLITE_OK)
    XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
    XCTAssertEqual(sqlite3_column_int(statement, 0), 1)
    driver.release(statement)
    XCTAssertEqual(driver.prepare(database, "SELECT ?", -1, &statement, nil), SQLITE_OK)
    XCTAssertEqual(sqlite3_bind_int(statement, 2, 1), SQLITE_RANGE)
    driver.markFailed(statement); driver.release(statement)
    XCTAssertEqual(driver.stats(for: database)?.idle, 0)
    driver.close(database); f.database = nil
  }

  func testActualPrimaryCatalogQueriesReuseTheConnectionPool() throws {
    let f = try AgentKnowledgePrimaryPartitionsTests.Fixture(), body = Data("Owned body".utf8)
    try f.write(body)
    let before = try XCTUnwrap(AgentKnowledgeSQLiteStatements.shared.stats(for: f.catalog))
    for _ in 0..<2 { XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), body) }
    let after = try XCTUnwrap(AgentKnowledgeSQLiteStatements.shared.stats(for: f.catalog))
    XCTAssertGreaterThan(after.reused, before.reused)
    XCTAssertLessThanOrEqual(after.idle, 32)
    XCTAssertLessThanOrEqual(after.sqlChars, 65_536)
  }

  func testOwnedCloseDrainsIdleManagedAndUnmanagedPrograms() throws {
    let f = try Fixture(), driver = AgentKnowledgeSQLiteStatements()
    let database = try XCTUnwrap(f.database)
    var cached: OpaquePointer?, borrowed: OpaquePointer?, unmanaged: OpaquePointer?
    XCTAssertEqual(driver.prepare(database, "SELECT 1", -1, &cached, nil), SQLITE_OK)
    driver.release(cached)
    XCTAssertEqual(driver.prepare(database, "SELECT 2", -1, &borrowed, nil), SQLITE_OK)
    XCTAssertEqual(sqlite3_prepare_v2(database, "SELECT 3", -1, &unmanaged, nil), SQLITE_OK)
    XCTAssertEqual(sqlite3_step(unmanaged), SQLITE_ROW)
    XCTAssertEqual(driver.close(database, finalizingUnmanaged: true), SQLITE_OK)
    f.database = nil
    XCTAssertNil(driver.stats(for: database))
    XCTAssertEqual(driver.release(borrowed), SQLITE_MISUSE)
    // All pointers above belong to the closed connection and must not be used.
  }

  func testGenericCloseDoesNotFinalizeAnUnrelatedStandalonePoolLease() throws {
    let f = try Fixture(), driver = AgentKnowledgeSQLiteStatements()
    let database = try XCTUnwrap(f.database), independent = try f.pool.acquire("SELECT 66")
    var borrowed: OpaquePointer?
    XCTAssertEqual(driver.prepare(database, "SELECT 77", -1, &borrowed, nil), SQLITE_OK)
    XCTAssertEqual(driver.close(database), SQLITE_OK)
    f.database = nil
    try independent.access {
      XCTAssertEqual(sqlite3_step($0), SQLITE_ROW)
      XCTAssertEqual(sqlite3_column_int($0, 0), 66)
    }
    f.pool.close(); independent.close()
  }

  func testActualCommittedViewReusesInitializationQueryAndDrainsOnClose() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("knowledge.sqlite")
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: InMemorySecretStore())
    XCTAssertTrue(database.replaceAll([]))
    let view = try AgentKnowledgeCommittedReadView(fileURL: url, checkActive: {})
    var handle: OpaquePointer?
    try view.read { connection in
      handle = connection
      let before = try XCTUnwrap(AgentKnowledgeSQLiteStatements.shared.stats(for: connection))
      var row: OpaquePointer?
      XCTAssertEqual(AgentKnowledgeSQLiteStatements.shared.prepare(connection,
        "SELECT revision FROM knowledge_browse_revision WHERE id=1", -1, &row, nil), SQLITE_OK)
      XCTAssertEqual(sqlite3_step(row), SQLITE_ROW)
      AgentKnowledgeSQLiteStatements.shared.release(row)
      let after = try XCTUnwrap(AgentKnowledgeSQLiteStatements.shared.stats(for: connection))
      XCTAssertGreaterThan(after.reused, before.reused)
    }
    view.close()
    XCTAssertNil(AgentKnowledgeSQLiteStatements.shared.stats(for: try XCTUnwrap(handle)))
  }

  func testActualSourceStagingReuseKeepsIdentityAndBindingIsolation() throws {
    let stage = try AgentKnowledgeSourceStaging(source: "synthetic")
    defer { stage.close() }
    let first = AgentKnowledgeItem(id: "first", kind: .document, title: "First", content: "body one", source: "synthetic", updatedAtMillis: 1)
    let second = AgentKnowledgeItem(id: "second", kind: .document, title: "Second", content: "body two", source: "synthetic", updatedAtMillis: 2)
    XCTAssertTrue(try stage.accept(first)); XCTAssertTrue(try stage.accept(second))
    XCTAssertFalse(try stage.accept(first))
    try stage.finishIncoming()
    for _ in 0..<3 {
      var found: [AgentKnowledgeItem] = []
      try stage.scan(.incoming) { found.append($0) }
      XCTAssertEqual(Set(found.map(\.id)), Set(["first", "second"]))
      XCTAssertEqual(found.first { $0.id == "first" }, first)
      XCTAssertEqual(found.first { $0.id == "second" }, second)
    }
  }

  func testSourceStagingCallbackFailureDoesNotPoisonLaterReads() throws {
    let stage = try AgentKnowledgeSourceStaging(source: "synthetic")
    defer { stage.close() }
    let item = AgentKnowledgeItem(id: "first", kind: .document, title: "First", content: "body", source: "synthetic", updatedAtMillis: 1)
    XCTAssertTrue(try stage.accept(item)); try stage.finishIncoming()
    XCTAssertThrowsError(try stage.scan(.incoming) { _ in throw Fault.injected })
    var found: [AgentKnowledgeItem] = []
    try stage.scan(.incoming) { found.append($0) }
    XCTAssertEqual(found, [item])
  }
}
