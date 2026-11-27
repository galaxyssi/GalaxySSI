import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgePrimaryCopyIntegrationTests: XCTestCase {
  private enum Fault: Error { case injected }
  private func item(_ generation: Int, large: Bool = true) -> AgentKnowledgeItem {
    let body = "needle generation \(generation) " + (large ? String(repeating: "synthetic ", count: 140_000) : "small")
    return AgentKnowledgeItem(id: "synthetic", kind: .document, title: "Synthetic", content: body,
      source: "source", summary: "generation \(generation)", updatedAtMillis: Int64(generation + 10))
  }
  private func fixture(_ body: (AgentKnowledgeDatabase, URL, InMemorySecretStore, AgentKnowledgePrimaryCopyStore.Job) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("knowledge.sqlite"), secrets = InMemorySecretStore()
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    XCTAssertTrue(database.replaceAll([item(0, large: false)]))
    try replace(database, [item(1)])
    let page = try database.reclaimPrimaryPartitions(pageSize: 8)
    XCTAssertFalse(page.deferred); XCTAssertEqual(page.moved, 0)
    let copy = try XCTUnwrap(job(url))
    try body(database, url, secrets, copy)
  }
  private func job(_ url: URL) throws -> AgentKnowledgePrimaryCopyStore.Job? {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let connection else { throw Fault.injected }
    defer { AgentKnowledgeSQLiteStatements.shared.close(connection) }
    return try AgentKnowledgePrimaryCopyStore.load(connection)
  }
  private func prepare(_ database: AgentKnowledgeDatabase, _ next: [AgentKnowledgeItem]) throws -> AgentKnowledgePreparedSourceReplacement {
    var iterator = next.makeIterator()
    return try database.prepareSourceReplacement("source", next: { iterator.next() })
  }
  private func replace(_ database: AgentKnowledgeDatabase, _ next: [AgentKnowledgeItem],
    beforeCommit: (AgentKnowledgeSourceStaging) throws -> Void = { _ in }) throws {
    var iterator = next.makeIterator()
    let mutation = try database.replaceSource("source", next: { iterator.next() }, beforeCommit: beforeCommit)
    mutation.stage.close()
  }
  @discardableResult private func finish(_ database: AgentKnowledgeDatabase) throws -> Int {
    var moved = 0
    for _ in 0..<64 {
      let page = try database.reclaimPrimaryPartitions(pageSize: 8)
      XCTAssertFalse(page.deferred); XCTAssertLessThanOrEqual(page.moved, 8)
      moved += page.moved
      if page.complete { return moved }
    }
    XCTFail("Synthetic copy job did not finish bounded pages")
    return moved
  }

  func testPreparedSourceRemainsValidAcrossCopyAndVerificationCheckpoints() throws {
    try fixture { database, url, _, copy in
      let prepared = try prepare(database, [item(2)]); defer { prepared.close() }
      let sourceRevision = try database.sourcePage().groups.first?.sourceRevision
      let receipts = try database.pendingSourceObservations().map(\.receipt)
      _ = try database.reclaimPrimaryPartitions(pageSize: 8)
      XCTAssertNotEqual(try XCTUnwrap(job(url)).checkpoint, copy.checkpoint)
      XCTAssertEqual(try XCTUnwrap(job(url)).original, copy.original)
      XCTAssertEqual(try finish(database), 1)
      XCTAssertNil(try job(url))
      XCTAssertEqual(try database.sourcePage().groups.first?.sourceRevision, sourceRevision)
      XCTAssertEqual(try database.pendingSourceObservations().map(\.receipt), receipts)
      let current = try prepare(database, [item(2)]); defer { current.close() }
      XCTAssertEqual(current.revision, prepared.revision)
      let mutation = try database.commitSourceReplacement(prepared); mutation.stage.close()
      XCTAssertEqual(try database.all(), [item(2)])
    }
  }

  func testTargetedReplacementCancelsStaleCopyWithoutPublishingOldBody() throws {
    try fixture { database, url, secrets, _ in
      _ = try database.reclaimPrimaryPartitions(pageSize: 8)
      let copied = try XCTUnwrap(job(url))
      let next = item(3, large: false)
      try replace(database, [next])
      XCTAssertNotNil(try job(url)) // User write does not unlink snapshot/copy-owned files.
      _ = try finish(database)
      XCTAssertNil(try job(url))
      XCTAssertEqual(try database.all(), [next])
      let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
      XCTAssertEqual(try reopened.all(), [next])
      XCTAssertFalse(FileManager.default.fileExists(atPath: url.path + ".primary/" + copied.destination + ".sqlite"))
    }
  }

  func testTargetedSourceDeletionDoesNotResurrectCopiedRecord() throws {
    try fixture { database, url, _, _ in
      _ = try database.reclaimPrimaryPartitions(pageSize: 8)
      try replace(database, [])
      let receipts = try database.pendingSourceObservations().map(\.receipt)
      XCTAssertTrue(try database.all().isEmpty)
      _ = try finish(database)
      XCTAssertNil(try job(url))
      XCTAssertTrue(try database.all().isEmpty)
      XCTAssertTrue(try database.sourcePage().groups.isEmpty)
      XCTAssertEqual(try database.pendingSourceObservations().map(\.receipt), receipts)
    }
  }

  func testFailedTargetedWritePreservesExactCopyCheckpointAndSource() throws {
    try fixture { database, url, _, _ in
      _ = try database.reclaimPrimaryPartitions(pageSize: 8)
      let saved = try XCTUnwrap(job(url))
      let receipts = try database.pendingSourceObservations().map(\.receipt)
      XCTAssertThrowsError(try replace(database, [item(4, large: false)], beforeCommit: { _ in throw Fault.injected }))
      let retained = try XCTUnwrap(job(url))
      XCTAssertEqual(retained.key, saved.key)
      XCTAssertEqual(retained.source, saved.source); XCTAssertEqual(retained.destination, saved.destination)
      XCTAssertEqual(retained.original, saved.original); XCTAssertEqual(retained.checkpoint, saved.checkpoint)
      XCTAssertEqual(try database.pendingSourceObservations().map(\.receipt), receipts)
      XCTAssertEqual(try finish(database), 1)
      XCTAssertNil(try job(url))
      XCTAssertEqual(try database.all(), [item(1)])
    }
  }

  func testActualReadViewDefersCopyWithoutAdvancingDurablePrefix() throws {
    try fixture { database, url, _, copy in
      let candidates = try database.searchCandidates(query: "needle", beforeValidation: {
        let page = try database.reclaimPrimaryPartitions(pageSize: 8)
        XCTAssertTrue(page.deferred); XCTAssertEqual(page.moved, 0)
        XCTAssertEqual(try XCTUnwrap(self.job(url)).checkpoint, copy.checkpoint)
      })
      XCTAssertEqual(candidates, [item(1)])
      XCTAssertEqual(try finish(database), 1)
      XCTAssertNil(try job(url))
    }
  }
}
