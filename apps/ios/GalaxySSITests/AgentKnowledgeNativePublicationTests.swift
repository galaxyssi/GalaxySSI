import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeNativePublicationTests: XCTestCase {
  func testPublicationPagesTrackLatestReadyRemovalAndReaddition() throws {
    try fixture { database, url, secrets in
      let a = item("a"), b = item("b")
      XCTAssertTrue(database.replaceAll([a, b]))
      for source in [a, b] { XCTAssertTrue(database.storeVectorCheckpoint(checkpoint(source))) }
      let model = checkpoint(a).provenance.modelSHA256
      let original = try database.nativePublicationPage(modelSHA256: model).events
      XCTAssertEqual(original.count, 2)
      let first = try database.nativePublicationPage(modelSHA256: model, limit: 1)
      let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
      let second = try reopened.nativePublicationPage(modelSHA256: model, afterItemHash: XCTUnwrap(first.nextItemHash), limit: 1)
      XCTAssertNotEqual(first.events.first?.itemHash, second.events.first?.itemHash)
      XCTAssertThrowsError(try reopened.nativePublicationPage(modelSHA256: model, afterItemHash: "bad"))
      XCTAssertTrue(database.clearVectorCheckpoints(itemId: a.id, modelSHA256: model))
      XCTAssertEqual(try database.nativePublicationPage(modelSHA256: model).events.count, 1)
      XCTAssertTrue(database.storeVectorCheckpoint(checkpoint(a)))
      let current = try database.nativePublicationPage(modelSHA256: model).events
      XCTAssertEqual(current.count, 2)
      XCTAssertEqual(Set(current.map(\.itemHash)), Set(original.map(\.itemHash)))
      XCTAssertNotEqual(Set(current.map(\.sequence)), Set(original.map(\.sequence)))
    }
  }

  func testResolutionUsesAuthenticatedChunkAndCurrentPolicy() throws {
    try fixture { database, _, _ in
      let source = item("resolve")
      let vector = checkpoint(source)
      XCTAssertTrue(database.replaceAll([source]))
      XCTAssertTrue(database.storeVectorCheckpoint(vector))
      let event = try XCTUnwrap(database.nativePublicationPage(modelSHA256: vector.provenance.modelSHA256).events.first)
      let stamp = try database.vectorFeedStamp(modelSHA256: vector.provenance.modelSHA256)
      let matched = match(event, vector)
      let hits = try database.resolveNativeMatches([matched, matched], provenance: vector.provenance, stamp: stamp)
      XCTAssertEqual(hits.count, 1)
      XCTAssertEqual(hits.first?.item, source)
      XCTAssertEqual(hits.first?.excerpt, source.content)
      XCTAssertTrue(AgentKnowledgeRetriever.retrieve(hits: hits, query: "body", targetId: "cloud-models").citations.isEmpty)
      var invalid = matched
      invalid.startUTF16 = 1
      XCTAssertTrue(try database.resolveNativeMatches([invalid], provenance: vector.provenance, stamp: stamp).isEmpty)
      invalid = matched
      invalid.ordinal = 10
      XCTAssertTrue(try database.resolveNativeMatches([invalid], provenance: vector.provenance, stamp: stamp).isEmpty)
      invalid = matched
      invalid.similarity = .nan
      XCTAssertThrowsError(try database.resolveNativeMatches([invalid], provenance: vector.provenance, stamp: stamp))
      var wrongSpec = vector.provenance
      wrongSpec.contextTokens += 32
      XCTAssertTrue(try database.resolveNativeMatches([matched], provenance: wrongSpec, stamp: stamp).isEmpty)
    }
  }

  func testSourcePolicyMutationWithoutFeedAppendInvalidatesOldBatch() throws {
    try fixture { database, _, _ in
      var source = item("policy")
      let vector = checkpoint(source)
      XCTAssertTrue(database.replaceAll([source]))
      XCTAssertTrue(database.storeVectorCheckpoint(vector))
      let event = try XCTUnwrap(database.nativePublicationPage(modelSHA256: vector.provenance.modelSHA256).events.first)
      let before = try database.vectorFeedStamp(modelSHA256: vector.provenance.modelSHA256)
      source.cloudAccess = .full
      XCTAssertTrue(database.replaceAll([source]))
      let after = try database.vectorFeedStamp(modelSHA256: vector.provenance.modelSHA256)
      XCTAssertEqual(before.head, after.head)
      XCTAssertNotEqual(before.sourceRevision, after.sourceRevision)
      XCTAssertThrowsError(try database.resolveNativeMatches([match(event, vector)], provenance: vector.provenance, stamp: before))
      XCTAssertTrue(try database.resolveNativeMatches([match(event, vector)], provenance: vector.provenance, stamp: after).isEmpty)
    }
  }

  func testOldNativePublicationCannotResolveAfterRemoveAndReadd() throws {
    try fixture { database, _, _ in
      let source = item("readded")
      let vector = checkpoint(source)
      XCTAssertTrue(database.replaceAll([source]))
      XCTAssertTrue(database.storeVectorCheckpoint(vector))
      let old = try XCTUnwrap(database.nativePublicationPage(modelSHA256: vector.provenance.modelSHA256).events.first)
      let before = try database.vectorFeedStamp(modelSHA256: vector.provenance.modelSHA256)
      XCTAssertTrue(database.clearVectorCheckpoints(itemId: source.id, modelSHA256: vector.provenance.modelSHA256))
      XCTAssertTrue(database.storeVectorCheckpoint(vector))
      let after = try database.vectorFeedStamp(modelSHA256: vector.provenance.modelSHA256)
      XCTAssertThrowsError(try database.resolveNativeMatches([match(old, vector)], provenance: vector.provenance, stamp: before))
      XCTAssertTrue(try database.resolveNativeMatches([match(old, vector)], provenance: vector.provenance, stamp: after).isEmpty)
      let current = try XCTUnwrap(database.nativePublicationPage(modelSHA256: vector.provenance.modelSHA256).events.first)
      XCTAssertEqual(try database.resolveNativeMatches([match(current, vector)], provenance: vector.provenance, stamp: after).count, 1)
      XCTAssertTrue(database.replaceAll([]))
      let deleted = try database.vectorFeedStamp(modelSHA256: vector.provenance.modelSHA256)
      XCTAssertTrue(try database.resolveNativeMatches([match(current, vector)], provenance: vector.provenance, stamp: deleted).isEmpty)
    }
  }

  func testPublicationSchemaUpgradeReenrollsInsteadOfInventingHistory() throws {
    try fixture { database, url, secrets in
      let source = item("upgrade")
      let vector = checkpoint(source)
      XCTAssertTrue(database.replaceAll([source]))
      XCTAssertTrue(database.storeVectorCheckpoint(vector))
      XCTAssertTrue(try database.maintainNativeVectorEnrollment(provenance: vector.provenance))
      XCTAssertTrue(try database.pendingVectorItems(modelSHA256: vector.provenance.modelSHA256).isEmpty)
      let original = try database.vectorChangePage(modelSHA256: vector.provenance.modelSHA256)
      var raw: OpaquePointer?
      XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
      defer { sqlite3_close(raw) }
      XCTAssertEqual(sqlite3_exec(raw, "DELETE FROM knowledge_vector_publications", nil, nil, nil), SQLITE_OK)
      XCTAssertEqual(sqlite3_exec(raw, "UPDATE knowledge_metadata SET value = 0 WHERE key = 'native_publications_schema'", nil, nil, nil), SQLITE_OK)
      let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
      XCTAssertEqual(try reopened.vectorChangePage(modelSHA256: vector.provenance.modelSHA256), original)
      XCTAssertTrue(try reopened.nativePublicationPage(modelSHA256: vector.provenance.modelSHA256).events.isEmpty)
      XCTAssertTrue(try reopened.maintainNativeVectorEnrollment(provenance: vector.provenance))
      XCTAssertEqual(try reopened.pendingVectorItems(modelSHA256: vector.provenance.modelSHA256).map(\.id), [source.id])
      XCTAssertTrue(reopened.clearVectorCheckpoints(itemId: source.id, modelSHA256: vector.provenance.modelSHA256))
      XCTAssertTrue(reopened.storeVectorCheckpoint(vector))
      XCTAssertGreaterThan(try XCTUnwrap(reopened.nativePublicationPage(modelSHA256: vector.provenance.modelSHA256).events.first).sequence, original.headSequence)
    }
  }

  func testFailedFeedRegistrationThrowsWithoutRecursiveRetry() throws {
    try fixture { database, url, _ in
      var raw: OpaquePointer?
      XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
      defer { sqlite3_close(raw) }
      XCTAssertEqual(sqlite3_exec(raw, "CREATE TRIGGER reject_feed BEFORE INSERT ON knowledge_vector_feed_models BEGIN SELECT RAISE(ABORT, 'fixture'); END", nil, nil, nil), SQLITE_OK)
      XCTAssertThrowsError(try database.vectorFeedStamp(modelSHA256: String(repeating: "f", count: 64)))
    }
  }

  private func fixture(_ body: (AgentKnowledgeDatabase, URL, InMemorySecretStore) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("knowledge.sqlite")
    let secrets = InMemorySecretStore()
    try body(AgentKnowledgeDatabase(fileURL: url, secrets: secrets), url, secrets)
  }

  private func item(_ id: String) -> AgentKnowledgeItem {
    AgentKnowledgeItem(id: id, kind: .note, title: "Source", content: "body text", source: "local", updatedAtMillis: 1)
  }

  private func checkpoint(_ item: AgentKnowledgeItem) -> AgentKnowledgeVectorCheckpoint {
    AgentKnowledgeVectorCheckpoint(itemId: item.id, sourceRevision: AgentKnowledgeVectorCheckpoint.sourceRevision(for: item),
      chunkIndex: 0, vector: [0.6, 0.8], provenance: AgentKnowledgeVectorProvenance(
        modelSHA256: String(repeating: "b", count: 64), dimensions: 2, contextTokens: 512, chunkingContract: AgentKnowledgeEmbeddingChunker.contract),
      updatedAtMillis: 10, sourceStartUTF16: 0, sourceEndUTF16: item.content.utf16.count)
  }

  private func match(_ event: AgentKnowledgeVectorChange, _ vector: AgentKnowledgeVectorCheckpoint) -> AgentKnowledgeNativeMatch {
    AgentKnowledgeNativeMatch(key: event.itemHash, revision: event.sourceRevisionHash, sequence: event.sequence,
      ordinal: 0, startUTF16: vector.sourceStartUTF16!, endUTF16: vector.sourceEndUTF16!, similarity: 0.8)
  }
}
