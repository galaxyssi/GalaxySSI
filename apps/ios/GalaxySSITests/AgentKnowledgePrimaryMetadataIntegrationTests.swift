import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgePrimaryMetadataIntegrationTests: XCTestCase {
  private enum Fault: Error { case injected }
  private func item(_ generation: Int = 1) -> AgentKnowledgeItem {
    AgentKnowledgeItem(id: "synthetic", kind: .document, title: "Synthetic", content: "needle generation \(generation)",
      source: "source", summary: "generation \(generation)", updatedAtMillis: Int64(generation + 10))
  }
  private func fixture(_ body: (AgentKnowledgeDatabase, URL, InMemorySecretStore) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("knowledge.sqlite"), secrets = InMemorySecretStore()
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    XCTAssertTrue(database.replaceAll([item()]))
    try body(database, url, secrets)
  }
  private func prepare(_ database: AgentKnowledgeDatabase) throws -> AgentKnowledgePreparedSourceReplacement {
    var next: AgentKnowledgeItem? = item(2)
    return try database.prepareSourceReplacement("source", next: { defer { next = nil }; return next })
  }
  private func sql(_ url: URL, _ sql: String) throws {
    var connection: OpaquePointer?
    guard sqlite3_open(url.path, &connection) == SQLITE_OK else { throw Fault.injected }
    defer { sqlite3_close_v2(connection) }
    guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw Fault.injected }
  }
  private func payload(_ url: URL) throws -> Data {
    var connection: OpaquePointer?, row: OpaquePointer?
    guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw Fault.injected }
    defer { sqlite3_finalize(row); sqlite3_close_v2(connection) }
    guard sqlite3_prepare_v2(connection, "SELECT encrypted_payload FROM knowledge_items", -1, &row, nil) == SQLITE_OK,
      sqlite3_step(row) == SQLITE_ROW, let bytes = sqlite3_column_blob(row, 0) else { throw Fault.injected }
    return Data(bytes: bytes, count: Int(sqlite3_column_bytes(row, 0)))
  }

  func testPreparedSourceWritesHeaderPointerAndReopensWithAuthenticatedBody() throws {
    try fixture { database, url, secrets in
      XCTAssertNotNil(try AgentKnowledgePrimaryMetadata.pointerHash(payload(url)))
      let prepared = try prepare(database); defer { prepared.close() }
      let mutation = try database.commitSourceReplacement(prepared); mutation.stage.close()
      let stored = try payload(url)
      XCTAssertEqual(stored.count, 69)
      XCTAssertNotNil(try AgentKnowledgePrimaryMetadata.pointerHash(stored))
      let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
      XCTAssertEqual(try reopened.all(), [item(2)])
      XCTAssertEqual(try reopened.searchCandidates(query: "needle"), [item(2)])
      XCTAssertFalse(try reopened.pendingSourceObservations().isEmpty)
    }
  }

  func testPreparationRejectsCatalogTimestampTamperingAgainstPhysicalHeader() throws {
    try fixture { database, url, _ in
      try sql(url, "UPDATE knowledge_items SET updated_at=999")
      XCTAssertThrowsError(try prepare(database))
      XCTAssertThrowsError(try database.searchCandidates(query: "needle"))
      XCTAssertTrue(try database.pendingSourceObservations().isEmpty)
    }
  }

  func testPostPreparationIndexMutationFailsGenerationFenceBeforePublishingHeader() throws {
    try fixture { database, url, _ in
      let prepared = try prepare(database); defer { prepared.close() }
      let stored = try payload(url)
      try sql(url, "UPDATE knowledge_items SET updated_at=999")
      XCTAssertThrowsError(try database.commitSourceReplacement(prepared)) {
        XCTAssertEqual($0 as? AgentKnowledgeDatabaseError, .sourceReplacementChanged)
      }
      XCTAssertEqual(try payload(url), stored)
      XCTAssertTrue(try database.pendingSourceObservations().isEmpty)
      // Restore only the deliberately corrupted synthetic index value.
      try sql(url, "UPDATE knowledge_items SET updated_at=11")
      XCTAssertEqual(try database.all(), [item()])
    }
  }

  func testPreparedPrecommitFailureKeepsOriginalHeaderPointerBodyAndOutbox() throws {
    try fixture { database, url, _ in
      let stored = try payload(url)
      let prepared = try prepare(database); defer { prepared.close() }
      XCTAssertThrowsError(try database.commitSourceReplacement(prepared, beforeCommit: { _ in throw Fault.injected }))
      XCTAssertEqual(try payload(url), stored)
      XCTAssertEqual(try database.all(), [item()])
      XCTAssertTrue(try database.pendingSourceObservations().isEmpty)
      let retry = try prepare(database); defer { retry.close() }
      let mutation = try database.commitSourceReplacement(retry); mutation.stage.close()
      XCTAssertEqual(try database.all(), [item(2)])
      XCTAssertNotEqual(try payload(url), stored)
    }
  }
}
