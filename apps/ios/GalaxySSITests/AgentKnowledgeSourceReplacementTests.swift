import CryptoKit
import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeSourceReplacementTests: XCTestCase {
  private enum Fault: Error { case injected }
  private func item(_ id: String, source: String = "source", body: String = "Synthetic body", time: Int64 = 10) -> AgentKnowledgeItem {
    AgentKnowledgeItem(id: id, kind: .document, title: "Synthetic title", content: body, source: source,
      summary: String(body.prefix(700)), cloudAccess: .summaryOnly, updatedAtMillis: time)
  }
  private func fixture(_ body: (AgentKnowledgeDatabase, URL, InMemorySecretStore) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("knowledge.sqlite"), secrets = InMemorySecretStore()
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    try body(database, url, secrets)
  }
  private func replace(_ database: AgentKnowledgeDatabase, _ items: [AgentKnowledgeItem], source: String = "source") throws -> Int {
    var iterator = items.makeIterator()
    let result = try database.replaceSource(source, next: { iterator.next() })
    defer { result.stage.close() }
    return result.changed
  }
  private func rows(_ url: URL, sql: String) throws -> [[Data]] {
    var raw: OpaquePointer?
    guard sqlite3_open_v2(url.path, &raw, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let raw else { throw Fault.injected }
    defer { sqlite3_close(raw) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(raw, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw Fault.injected }
    defer { sqlite3_finalize(statement) }
    var result: [[Data]] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return result }
      guard status == SQLITE_ROW else { throw Fault.injected }
      result.append((0..<sqlite3_column_count(statement)).map { column in
        guard let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
      })
    }
  }
  private func checkpoint(_ item: AgentKnowledgeItem) -> AgentKnowledgeVectorCheckpoint {
    AgentKnowledgeVectorCheckpoint(itemId: item.id, sourceRevision: AgentKnowledgeVectorCheckpoint.sourceRevision(for: item),
      chunkIndex: 0, vector: [0.6, 0.8], provenance: AgentKnowledgeVectorProvenance(modelSHA256: String(repeating: "a", count: 64),
        dimensions: 2, contextTokens: 512, chunkingContract: AgentKnowledgeEmbeddingChunker.contract), updatedAtMillis: 10,
      sourceStartUTF16: 0, sourceEndUTF16: item.content.utf16.count)
  }

  func testStagingDeduplicatesFirstValidIdentityAndEncryptsAllBodyFiles() throws {
    let stage = try AgentKnowledgeSourceStaging(source: "source")
    defer { stage.close() }
    var invalid = item("private-stable-id", body: "private-source-body-marker")
    invalid.title = " "
    XCTAssertFalse(try stage.accept(invalid))
    XCTAssertFalse(try stage.accept(item("wrong", source: "other")))
    XCTAssertTrue(try stage.accept(item("private-stable-id", body: "private-source-body-marker")))
    XCTAssertFalse(try stage.accept(item("private-stable-id", body: "must-not-win")))
    try stage.finishIncoming()
    var found: [AgentKnowledgeItem] = []
    try stage.scan(.incoming) { found.append($0) }
    XCTAssertEqual(found.map(\.content), ["private-source-body-marker"])
    for file in try FileManager.default.contentsOfDirectory(at: stage.directory, includingPropertiesForKeys: nil) {
      let bytes = try Data(contentsOf: file)
      XCTAssertNil(bytes.range(of: Data("private-stable-id".utf8)))
      XCTAssertNil(bytes.range(of: Data("private-source-body-marker".utf8)))
    }
    stage.close()
    XCTAssertFalse(FileManager.default.fileExists(atPath: stage.directory.path))
  }

  func testStagingRejectsBlankStableIdentity() throws {
    let stage = try AgentKnowledgeSourceStaging(source: "source")
    defer { stage.close() }
    XCTAssertThrowsError(try stage.accept(item(" ")))
  }

  func testTamperedIncomingFailsAuthenticationBeforeCatalogMutation() throws {
    let stage = try AgentKnowledgeSourceStaging(source: "source")
    defer { stage.close() }
    try stage.accept(item("one")); try stage.finishIncoming()
    var raw: OpaquePointer?
    XCTAssertEqual(sqlite3_open(stage.fileURL.path, &raw), SQLITE_OK)
    defer { sqlite3_close(raw) }
    XCTAssertEqual(sqlite3_exec(raw, "UPDATE records SET incoming=zeroblob(64)", nil, nil, nil), SQLITE_OK)
    XCTAssertThrowsError(try stage.scan(.incoming) { _ in XCTFail("Corrupt body escaped") })
  }

  func testProducerIsConsumedOnceAndPagesMoreThan64OldRecords() throws {
    try fixture { database, url, secrets in
      let old = (0..<130).map { item("old-\($0)") }
      XCTAssertTrue(database.replaceAll(old + [item("unrelated", source: "elsewhere")]))
      var calls = 0
      let result = try database.replaceSource("source", next: {
        calls += 1
        return calls <= 130 ? self.item("new-\(calls)") : nil
      })
      defer { result.stage.close() }
      XCTAssertEqual(calls, 131); XCTAssertEqual(result.changed, 260)
      let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
      XCTAssertEqual(try reopened.all().count, 131)
      XCTAssertEqual(try reopened.items(ids: ["unrelated"]).count, 1)
      XCTAssertEqual(try reopened.sourcePage().groups.first(where: { $0.source == "source" })?.chunkCount, 130)
    }
  }

  func testOwnershipConflictPreflightLeavesCiphertextAndRevisionUnchanged() throws {
    try fixture { database, url, _ in
      XCTAssertTrue(database.replaceAll([item("old"), item("foreign", source: "elsewhere")]))
      let before = try rows(url, sql: "SELECT * FROM knowledge_items ORDER BY item_hash")
      let revision = try rows(url, sql: "SELECT * FROM knowledge_browse_revision")
      XCTAssertThrowsError(try replace(database, [item("valid"), item("foreign")]))
      XCTAssertEqual(try rows(url, sql: "SELECT * FROM knowledge_items ORDER BY item_hash"), before)
      XCTAssertEqual(try rows(url, sql: "SELECT * FROM knowledge_browse_revision"), revision)
    }
  }

  func testFailureAfterFirstMutationRollsBackCatalogFTSAndHeaders() throws {
    try fixture { database, url, _ in
      XCTAssertTrue(database.replaceAll([item("old")]))
      let before = try rows(url, sql: "SELECT * FROM knowledge_source_headers")
      var next: AgentKnowledgeItem? = item("new")
      XCTAssertThrowsError(try database.replaceSource("source", next: { defer { next = nil }; return next }, afterMutation: { _ in throw Fault.injected }))
      XCTAssertEqual(try database.all().map(\.id), ["old"])
      XCTAssertEqual(try rows(url, sql: "SELECT * FROM knowledge_source_headers"), before)
      XCTAssertEqual(try database.searchCandidates(query: "Synthetic").map(\.id), ["old"])
    }
  }

  func testPrecommitCacheReadFailureRollsBackCanonicalMutation() throws {
    try fixture { database, _, _ in
      XCTAssertTrue(database.replaceAll([item("old")]))
      var next: AgentKnowledgeItem? = item("new")
      XCTAssertThrowsError(try database.replaceSource("source", next: { defer { next = nil }; return next }, beforeCommit: { _ in throw Fault.injected }))
      XCTAssertEqual(try database.all().map(\.id), ["old"])
    }
  }

  func testOldestPolicyNotFirstChunkControlsEntireReplacement() throws {
    try fixture { database, _, _ in
      var oldest = item("oldest", time: 1); oldest.chunkIndex = 9
      oldest.cloudAccess = .deny; oldest.agentAccess = .selectedAgents; oldest.allowedAgentIds = ["reviewed-peer"]
      let newest = item("first-chunk", time: 100)
      XCTAssertTrue(database.replaceAll([newest, oldest]))
      XCTAssertEqual(try replace(database, [item("new-a"), item("new-b")]), 4)
      for value in try database.all() {
        XCTAssertEqual(value.cloudAccess, .deny); XCTAssertEqual(value.agentAccess, .selectedAgents)
        XCTAssertEqual(value.allowedAgentIds, ["reviewed-peer"])
      }
    }
  }

  func testEqualTimestampPolicyUsesCatalogKeyTieBreak() throws {
    try fixture { database, _, secrets in
      var a = item("a"), b = item("b"); a.cloudAccess = .deny; b.cloudAccess = .full
      XCTAssertTrue(database.replaceAll([a, b]))
      let encoded = try XCTUnwrap(secrets.string(account: "agent.knowledge.index.hmac256.v1"))
      let key = SymmetricKey(data: try XCTUnwrap(Data(base64Encoded: encoded)))
      func hash(_ id: String) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(id.utf8), using: key).map { String(format: "%02x", $0) }.joined()
      }
      let expected = hash(a.id) < hash(b.id) ? a.cloudAccess : b.cloudAccess
      _ = try replace(database, [item("next")])
      XCTAssertEqual(try database.all().first?.cloudAccess, expected)
    }
  }

  func testNoopPreservesPhysicalRowsTimestampRevisionVectorsAndFeed() throws {
    try fixture { database, url, _ in
      let old = item("stable"), vector = checkpoint(old)
      XCTAssertTrue(database.replaceAll([old])); XCTAssertTrue(database.storeVectorCheckpoint(vector))
      let before = try rows(url, sql: "SELECT * FROM knowledge_items")
      let headers = try rows(url, sql: "SELECT * FROM knowledge_source_headers")
      let revision = try rows(url, sql: "SELECT * FROM knowledge_browse_revision")
      let feed = try database.vectorChangePage(modelSHA256: vector.provenance.modelSHA256)
      XCTAssertEqual(try replace(database, [item("stable", time: 999)]), 0)
      XCTAssertEqual(try database.all(), [old])
      XCTAssertEqual(try rows(url, sql: "SELECT * FROM knowledge_items"), before)
      XCTAssertEqual(try rows(url, sql: "SELECT * FROM knowledge_source_headers"), headers)
      XCTAssertEqual(try rows(url, sql: "SELECT * FROM knowledge_browse_revision"), revision)
      XCTAssertEqual(try database.vectorCheckpoints(itemId: old.id, modelSHA256: vector.provenance.modelSHA256), [vector])
      XCTAssertEqual(try database.vectorChangePage(modelSHA256: vector.provenance.modelSHA256), feed)
    }
  }

  func testReplacementInvalidatesOnlyChangedVectorsAndEnqueuesReplacement() throws {
    try fixture { database, _, _ in
      let old = item("stable"), other = item("other", source: "elsewhere")
      let vector = checkpoint(old), unrelated = checkpoint(other)
      XCTAssertTrue(database.replaceAll([old, other]))
      XCTAssertTrue(database.storeVectorCheckpoint(vector)); XCTAssertTrue(database.storeVectorCheckpoint(unrelated))
      _ = try database.maintainNativeVectorEnrollment(provenance: vector.provenance)
      XCTAssertEqual(try replace(database, [item("stable", body: "Changed content")]), 1)
      XCTAssertTrue(try database.vectorCheckpoints(itemId: old.id, modelSHA256: vector.provenance.modelSHA256).isEmpty)
      XCTAssertEqual(try database.vectorCheckpoints(itemId: other.id, modelSHA256: vector.provenance.modelSHA256), [unrelated])
      XCTAssertEqual(try database.pendingVectorItems(modelSHA256: vector.provenance.modelSHA256).map(\.id), [old.id])
      XCTAssertEqual(try database.vectorChangePage(modelSHA256: vector.provenance.modelSHA256).events.last?.operation, .removal)
    }
  }

  func testEmptyProducerDeletesOnlySelectedSource() throws {
    try fixture { database, _, _ in
      XCTAssertTrue(database.replaceAll([item("old"), item("other", source: "elsewhere")]))
      XCTAssertEqual(try replace(database, []), 1)
      XCTAssertEqual(try database.all().map(\.id), ["other"])
      XCTAssertFalse(try database.sourcePage().groups.contains { $0.source == "source" })
    }
  }

  func testThrowingProducerLeavesExistingSourceUnchanged() throws {
    try fixture { database, _, _ in
      XCTAssertTrue(database.replaceAll([item("old")]))
      var calls = 0
      XCTAssertThrowsError(try database.replaceSource("source", next: {
        calls += 1
        if calls == 1 { return self.item("new") }
        throw Fault.injected
      }))
      XCTAssertEqual(calls, 2)
      XCTAssertEqual(try database.all().map(\.id), ["old"])
    }
  }

  func testBlankSummaryNormalizesWithoutChangingIncomingOrderWinner() throws {
    try fixture { database, _, _ in
      var first = item("same", body: "First accepted body"); first.summary = " "
      XCTAssertEqual(try replace(database, [first, item("same", body: "Later duplicate")]), 1)
      let stored = try XCTUnwrap(database.all().first)
      XCTAssertEqual(stored.content, first.content); XCTAssertEqual(stored.summary, first.content)
    }
  }

  func testCancellationAfterMutationRollsBackBeforeCommit() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let database = AgentKnowledgeDatabase(fileURL: root.appendingPathComponent("knowledge.sqlite"), secrets: InMemorySecretStore())
    let old = item("old"), incoming = item("new")
    XCTAssertTrue(database.replaceAll([old]))
    let operation = Task {
      var next: AgentKnowledgeItem? = incoming
      do {
        let result = try database.replaceSource("source", next: { defer { next = nil }; return next }, afterMutation: { _ in
          withUnsafeCurrentTask { $0?.cancel() }
        })
        result.stage.close(); XCTFail("Cancelled mutation committed")
      } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
    await operation.value
    XCTAssertEqual(try database.all(), [old])
  }

  @MainActor
  func testStoreAdapterPublishesNormalizedCacheAndInvalidatesChangedVector() throws {
    let suite = "SourceReplacement-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = GalaxySSIStore(defaults: defaults, secrets: InMemorySecretStore())
    let first = try XCTUnwrap(store.replaceAgentKnowledgeSource(title: "Document", content: "First body", source: "source").first)
    let vector = checkpoint(first)
    XCTAssertTrue(store.agentKnowledgeDatabase.storeVectorCheckpoint(vector))
    let replacement = try XCTUnwrap(store.replaceAgentKnowledgeSource(title: "Document", content: "Changed body", source: "source").first)
    XCTAssertEqual(replacement.id, first.id)
    XCTAssertEqual(try store.agentKnowledgeDatabase.items(ids: [first.id]), [replacement])
    XCTAssertEqual(store.agentKnowledgeItems.filter { $0.id == first.id }, [replacement])
    XCTAssertTrue(try store.agentKnowledgeDatabase.vectorCheckpoints(itemId: first.id, modelSHA256: vector.provenance.modelSHA256).isEmpty)
    XCTAssertFalse(store.publishingCommittedKnowledgeCache)
    let replay = store.replaceAgentKnowledgeSource(title: "Document", content: "Changed body", source: "source")
    XCTAssertEqual(replay, [replacement])
  }
}
