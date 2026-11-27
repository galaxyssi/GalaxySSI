import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgePrimarySourceIntegrationTests: XCTestCase {
  private enum Fault: Error { case injected }
  private func item(_ body: String = "needle old") -> AgentKnowledgeItem {
    AgentKnowledgeItem(id: "synthetic", kind: .document, title: "Synthetic", content: body,
      source: "source", summary: body, updatedAtMillis: 10)
  }
  private func fixture(_ body: (AgentKnowledgeDatabase, URL, InMemorySecretStore) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("knowledge.sqlite"), secrets = InMemorySecretStore()
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    XCTAssertTrue(database.replaceAll([item()]))
    try body(database, url, secrets)
  }
  private func sourceReplace(_ database: AgentKnowledgeDatabase, _ next: AgentKnowledgeItem,
    beforeCommit: (AgentKnowledgeSourceStaging) throws -> Void = { _ in }) throws {
    var next: AgentKnowledgeItem? = next
    let result = try database.replaceSource("source", next: { defer { next = nil }; return next }, beforeCommit: beforeCommit)
    defer { result.stage.close() }
    XCTAssertEqual(result.changed, 1)
  }
  private func scalar(_ url: URL, _ sql: String) throws -> Int64 {
    var connection: OpaquePointer?, row: OpaquePointer?
    guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw Fault.injected }
    defer { sqlite3_finalize(row); sqlite3_close_v2(connection) }
    guard sqlite3_prepare_v2(connection, sql, -1, &row, nil) == SQLITE_OK, sqlite3_step(row) == SQLITE_ROW else { throw Fault.injected }
    return sqlite3_column_int64(row, 0)
  }

  func testTargetedSourceCommitPublishesCompletePrimaryRecordsAndReopens() throws {
    try fixture { database, url, secrets in
      let next = item("needle replacement " + String(repeating: "synthetic ", count: 20_000))
      try sourceReplace(database, next)
      XCTAssertEqual(try scalar(url, "SELECT COUNT(*) FROM knowledge_primary_refs"), 1)
      XCTAssertEqual(try scalar(url, "SELECT COUNT(*) FROM knowledge_items WHERE length(encrypted_payload)=69 AND CAST(substr(encrypted_payload,1,5) AS TEXT)='khp1:'"), 1)
      let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
      XCTAssertEqual(try reopened.all(), [next])
      XCTAssertEqual(try reopened.searchCandidates(query: "needle"), [next])
      XCTAssertFalse(try reopened.pendingSourceObservations().isEmpty)
    }
  }

  func testTargetedSourcePrecommitFailureRollsBackPrimaryReferencesAndOutbox() throws {
    try fixture { database, url, secrets in
      XCTAssertThrowsError(try sourceReplace(database, item("needle cancelled"), beforeCommit: { _ in throw Fault.injected }))
      let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
      XCTAssertEqual(try reopened.all(), [item()])
      XCTAssertEqual(try scalar(url, "SELECT COUNT(*) FROM knowledge_primary_refs"), 1)
      XCTAssertTrue(try reopened.pendingSourceObservations().isEmpty)
      try sourceReplace(database, item("needle subsequent"))
      XCTAssertEqual(try database.all(), [item("needle subsequent")])
    }
  }

  func testActualCandidateReadRetainsPhysicalLeaseThroughValidation() throws {
    try fixture { database, _, _ in
      let result = try database.searchCandidates(query: "needle", beforeValidation: {
        try self.sourceReplace(database, self.item("needle replacement"))
        XCTAssertTrue(try database.reclaimPrimaryLegacyCopies().deferred)
      })
      XCTAssertTrue(result.isEmpty)
      XCTAssertFalse(try database.reclaimPrimaryLegacyCopies().deferred)
      XCTAssertEqual(try database.searchCandidates(query: "needle"), [item("needle replacement")])
    }
  }

  func testCommittedViewRetainsLeaseUntilExplicitClose() throws {
    let fixture = try AgentKnowledgePrimaryPartitionsTests.Fixture()
    try fixture.sql("CREATE TABLE knowledge_browse_revision(id INTEGER PRIMARY KEY,revision INTEGER NOT NULL)")
    try fixture.sql("INSERT INTO knowledge_browse_revision VALUES(1,0)")
    let view = try AgentKnowledgeCommittedReadView(fileURL: fixture.url, primarySnapshotLease: fixture.store.snapshotLease(), checkActive: {})
    XCTAssertNil(try fixture.store.withExclusiveAccess(catalog: fixture.catalog) { true })
    view.close()
    XCTAssertEqual(try fixture.store.withExclusiveAccess(catalog: fixture.catalog) { true }, true)
    view.close()
  }

  func testCloseInsideActiveReadDoesNotReleasePhysicalLeaseEarly() throws {
    let fixture = try AgentKnowledgePrimaryPartitionsTests.Fixture()
    try fixture.sql("CREATE TABLE knowledge_browse_revision(id INTEGER PRIMARY KEY,revision INTEGER NOT NULL)")
    try fixture.sql("INSERT INTO knowledge_browse_revision VALUES(1,0)")
    let view = try AgentKnowledgeCommittedReadView(fileURL: fixture.url, primarySnapshotLease: fixture.store.snapshotLease(), checkActive: {})
    XCTAssertThrowsError(try view.read { _ in
      view.close()
      XCTAssertNil(try fixture.store.withExclusiveAccess(catalog: fixture.catalog) { true })
    })
    XCTAssertEqual(try fixture.store.withExclusiveAccess(catalog: fixture.catalog) { true }, true)
  }

  func testFailedViewInitializationReleasesPhysicalLease() throws {
    let fixture = try AgentKnowledgePrimaryPartitionsTests.Fixture()
    // The deliberately absent browse table fails after acquiring/opening resources.
    XCTAssertThrowsError(try AgentKnowledgeCommittedReadView(fileURL: fixture.url,
      primarySnapshotLease: fixture.store.snapshotLease(), checkActive: {}))
    XCTAssertEqual(try fixture.store.withExclusiveAccess(catalog: fixture.catalog) { true }, true)
  }

  func testPreparedReplacementReadsPrimaryRecordsAndRetainsConflictFence() throws {
    try fixture { database, _, _ in
      var next: AgentKnowledgeItem? = item("needle prepared")
      let prepared = try database.prepareSourceReplacement("source", next: { defer { next = nil }; return next })
      defer { prepared.close() }
      try sourceReplace(database, item("needle concurrent"))
      XCTAssertThrowsError(try database.commitSourceReplacement(prepared)) {
        XCTAssertEqual($0 as? AgentKnowledgeDatabaseError, .sourceReplacementChanged)
      }
      XCTAssertEqual(try database.all(), [item("needle concurrent")])
    }
  }

  func testCloseFinalizesLeakedCursorBeforeDroppingPhysicalLease() throws {
    let fixture = try AgentKnowledgePrimaryPartitionsTests.Fixture()
    try fixture.sql("CREATE TABLE knowledge_browse_revision(id INTEGER PRIMARY KEY,revision INTEGER NOT NULL)")
    try fixture.sql("INSERT INTO knowledge_browse_revision VALUES(1,0)")
    let view = try AgentKnowledgeCommittedReadView(fileURL: fixture.url, primarySnapshotLease: fixture.store.snapshotLease(), checkActive: {})
    try view.read { connection in
      var row: OpaquePointer?
      XCTAssertEqual(sqlite3_prepare_v2(connection, "SELECT revision FROM knowledge_browse_revision", -1, &row, nil), SQLITE_OK)
      XCTAssertEqual(sqlite3_step(row), SQLITE_ROW)
      // Deliberately leave the cursor to its owning view, never use it after close.
    }
    view.close()
    XCTAssertEqual(try fixture.store.withExclusiveAccess(catalog: fixture.catalog) { true }, true)
  }
}
