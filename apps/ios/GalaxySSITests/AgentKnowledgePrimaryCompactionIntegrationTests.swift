import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgePrimaryCompactionIntegrationTests: XCTestCase {
  private enum Fault: Error { case injected }
  private func items(_ generation: Int, count: Int = 20) -> [AgentKnowledgeItem] {
    (0..<count).map { index in
      AgentKnowledgeItem(id: "synthetic-\(index)", kind: .document, title: "Synthetic",
        content: "needle generation \(generation) body \(index)", source: "source",
        summary: "summary \(generation) \(index)", chunkIndex: index, chunkCount: count,
        updatedAtMillis: Int64(generation + 10))
    }
  }
  private func fixture(_ body: (AgentKnowledgeDatabase, URL, InMemorySecretStore) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("knowledge.sqlite"), secrets = InMemorySecretStore()
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    XCTAssertTrue(database.replaceAll(items(0)))
    // Two complete generations leave each original bucket at half-live or less.
    try replace(database, items(1))
    try body(database, url, secrets)
  }
  private func prepare(_ database: AgentKnowledgeDatabase, _ items: [AgentKnowledgeItem]) throws -> AgentKnowledgePreparedSourceReplacement {
    var iterator = items.makeIterator()
    return try database.prepareSourceReplacement("source", next: { iterator.next() })
  }
  private func replace(_ database: AgentKnowledgeDatabase, _ items: [AgentKnowledgeItem],
    beforeCommit: (AgentKnowledgeSourceStaging) throws -> Void = { _ in }) throws {
    var iterator = items.makeIterator()
    let mutation = try database.replaceSource("source", next: { iterator.next() }, beforeCommit: beforeCommit)
    mutation.stage.close()
  }
  @discardableResult private func drain(_ database: AgentKnowledgeDatabase) throws -> Int {
    var moved = 0
    for _ in 0..<64 {
      let page = try database.reclaimPrimaryPartitions(pageSize: 8)
      XCTAssertFalse(page.deferred); XCTAssertLessThanOrEqual(page.moved, 8)
      moved += page.moved
      if page.complete { return moved }
    }
    XCTFail("Synthetic compaction did not complete its bounded pages")
    return moved
  }
  private func rows(_ url: URL, _ sql: String) throws -> [[String]] {
    var database: OpaquePointer?, row: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw Fault.injected }
    defer { sqlite3_finalize(row); sqlite3_close_v2(database) }
    guard sqlite3_prepare_v2(database, sql, -1, &row, nil) == SQLITE_OK else { throw Fault.injected }
    var result: [[String]] = []
    while true {
      let code = sqlite3_step(row)
      if code == SQLITE_DONE { return result }
      guard code == SQLITE_ROW else { throw Fault.injected }
      result.append(try (0..<sqlite3_column_count(row)).map { column in
        guard let text = sqlite3_column_text(row, column) else { throw Fault.injected }
        return String(cString: text)
      })
    }
  }
  private func assertItems(_ database: AgentKnowledgeDatabase, _ expected: [AgentKnowledgeItem]) throws {
    XCTAssertEqual(try database.all().sorted { $0.id < $1.id }, expected.sorted { $0.id < $1.id })
  }

  func testPreparedSourceSurvivesPhysicalCompactionWithoutChangingLogicalRevisionOrFeed() throws {
    try fixture { database, url, _ in
      let prepared = try prepare(database, items(2)); defer { prepared.close() }
      let generation = prepared.revision
      let sourceRevision = try database.sourcePage().groups.first?.sourceRevision
      let model = String(repeating: "a", count: 64)
      let feed = try database.vectorFeedStamp(modelSHA256: model)
      let receipts = try database.pendingSourceObservations().map(\.receipt)
      XCTAssertGreaterThan(try drain(database), 0)
      XCTAssertEqual(try database.sourcePage().groups.first?.sourceRevision, sourceRevision)
      XCTAssertEqual(try database.vectorFeedStamp(modelSHA256: model), feed)
      XCTAssertEqual(try database.pendingSourceObservations().map(\.receipt), receipts)
      let current = try prepare(database, items(2)); defer { current.close() }
      XCTAssertEqual(current.revision, generation)
      let mutation = try database.commitSourceReplacement(prepared); mutation.stage.close()
      try assertItems(database, items(2))
      XCTAssertEqual(try rows(url, "SELECT COUNT(*) FROM knowledge_primary_refs"), [["20"]])
    }
  }

  func testActualCandidateValidationDefersCompactionUntilViewCloses() throws {
    try fixture { database, _, _ in
      let revision = try database.sourcePage().groups.first?.sourceRevision
      let candidates = try database.searchCandidates(query: "needle", beforeValidation: {
        let page = try database.reclaimPrimaryPartitions(pageSize: 8)
        XCTAssertTrue(page.deferred); XCTAssertEqual(page.moved, 0)
      })
      XCTAssertEqual(Set(candidates.map(\.id)), Set(items(1).map(\.id)))
      XCTAssertGreaterThan(try drain(database), 0)
      try assertItems(database, items(1))
      XCTAssertEqual(try database.sourcePage().groups.first?.sourceRevision, revision)
    }
  }

  func testTargetedReplacementBetweenCompactionPagesWinsWithoutResurrection() throws {
    try fixture { database, url, secrets in
      let first = try database.reclaimPrimaryPartitions(pageSize: 8)
      XCTAssertFalse(first.deferred); XCTAssertLessThanOrEqual(first.moved, 8)
      let next = items(3, count: 5)
      try replace(database, next)
      let receipts = try database.pendingSourceObservations().map(\.receipt)
      _ = try drain(database)
      XCTAssertEqual(try database.pendingSourceObservations().map(\.receipt), receipts)
      try assertItems(database, next)
      let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
      try assertItems(reopened, next)
      XCTAssertEqual(try rows(url, "SELECT COUNT(*) FROM knowledge_primary_refs"), [["5"]])
    }
  }

  func testFailedTargetedWritePreservesCompactionQueueReferencesAndOutbox() throws {
    try fixture { database, url, _ in
      _ = try database.reclaimPrimaryPartitions(pageSize: 8)
      let refsSQL = "SELECT item_hash,partition_id,hex(sealed_ref) FROM knowledge_primary_refs ORDER BY item_hash"
      let dirtySQL = "SELECT partition_id FROM knowledge_primary_dirty ORDER BY partition_id"
      let stateSQL = "SELECT after_partition,discovered,source FROM knowledge_primary_compaction WHERE id=1"
      let refs = try rows(url, refsSQL), dirty = try rows(url, dirtySQL), state = try rows(url, stateSQL)
      let receipts = try database.pendingSourceObservations().map(\.receipt)
      XCTAssertThrowsError(try replace(database, items(4), beforeCommit: { _ in throw Fault.injected }))
      XCTAssertEqual(try rows(url, refsSQL), refs)
      XCTAssertEqual(try rows(url, dirtySQL), dirty)
      XCTAssertEqual(try rows(url, stateSQL), state)
      XCTAssertEqual(try database.pendingSourceObservations().map(\.receipt), receipts)
      _ = try drain(database)
      try assertItems(database, items(1))
    }
  }
}
