import Foundation
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeDatabaseTests: XCTestCase {
  @MainActor
  func testStableIdsKeepSameNamedSourcesAndRejectReassignment() throws {
    let suite = "AgentKnowledgeIdentityTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.removePersistentDomain(forName: suite)
    let store = GalaxySSIStore(defaults: defaults, secrets: InMemorySecretStore())
    let first = AgentKnowledgeItem(id: "first", kind: .note, title: "Shared", content: "One", source: "source-a")
    let second = AgentKnowledgeItem(id: "second", kind: .note, title: "Shared", content: "Two", source: "source-b")

    store.upsertAgentKnowledge(first)
    store.upsertAgentKnowledge(second)
    XCTAssertEqual(Set(store.agentKnowledgeItems.map(\.id)), ["first", "second"])

    let reassigned = AgentKnowledgeItem(id: "first", kind: .note, title: "Moved", content: "Three", source: "source-c")
    XCTAssertEqual(store.upsertAgentKnowledge(reassigned), first)
    XCTAssertEqual(store.agentKnowledgeItems.first { $0.id == "first" }?.source, "source-a")

    let blank = AgentKnowledgeItem(id: "", kind: .note, title: "Blank", content: "Body", source: "source-d")
    store.upsertAgentKnowledge(blank)
    XCTAssertFalse(store.agentKnowledgeItems.contains { $0.id.isBlank })
  }

  @MainActor
  func testExactSourceReplayPreservesIdsAndVectorCheckpoints() throws {
    let suite = "AgentKnowledgeReplayTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.removePersistentDomain(forName: suite)
    let store = GalaxySSIStore(defaults: defaults, secrets: InMemorySecretStore())
    let first = try XCTUnwrap(store.replaceAgentKnowledgeSource(
      title: "Stable",
      content: "The same normalized content",
      source: "file://stable"
    ).first)
    let provenance = AgentKnowledgeVectorProvenance(
      modelSHA256: String(repeating: "b", count: 64),
      dimensions: 2,
      contextTokens: 512,
      chunkingContract: AgentKnowledgeEmbeddingChunker.contract
    )
    let checkpoint = AgentKnowledgeVectorCheckpoint(
      itemId: first.id,
      sourceRevision: AgentKnowledgeVectorCheckpoint.sourceRevision(for: first),
      chunkIndex: 0,
      vector: [0.6, 0.8],
      provenance: provenance,
      updatedAtMillis: 10
    )
    XCTAssertTrue(store.agentKnowledgeDatabase.storeVectorCheckpoint(checkpoint))

    let replay = try XCTUnwrap(store.replaceAgentKnowledgeSource(
      title: "Stable",
      content: "The same normalized content",
      source: "file://stable"
    ).first)

    XCTAssertEqual(replay, first)
    XCTAssertEqual(
      try store.agentKnowledgeDatabase.vectorCheckpoints(itemId: first.id, modelSHA256: provenance.modelSHA256),
      [checkpoint]
    )
  }

  func testEncryptedDatabaseRetainsMoreThanLegacyCapAcrossReopen() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentKnowledgeDatabaseTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("knowledge.sqlite")
    let secrets = InMemorySecretStore()
    let items = (0..<1_201).map { index in
      AgentKnowledgeItem(
        id: "item-\(index)",
        kind: .document,
        title: "Title \(index)",
        content: index == 1_200 ? "Private body 1200 with unique marker and \u{72ec}\u{7279}\u{77e5}\u{8bc6}" : "Private body \(index)",
        source: "source-\(index / 10)",
        updatedAtMillis: Int64(index)
      )
    }

    XCTAssertTrue(AgentKnowledgeDatabase(fileURL: url, secrets: secrets).replaceAll(items))
    let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    let restored = try reopened.all()

    XCTAssertEqual(restored.count, 1_201)
    XCTAssertEqual(Set(restored.map(\.id)), Set(items.map(\.id)))
    XCTAssertEqual(try reopened.searchCandidates(query: "1200").map(\.id), ["item-1200"])
    XCTAssertEqual(try reopened.searchCandidates(query: "\u{72ec}\u{7279}\u{77e5}\u{8bc6}").map(\.id), ["item-1200"])
    let raw = String(decoding: try Data(contentsOf: url), as: UTF8.self)
    XCTAssertFalse(raw.contains("Private body 1200"))
    XCTAssertFalse(raw.contains("source-120"))
    XCTAssertFalse(raw.contains("item-1200"))
  }

  func testEncryptedSourcePagesTraverseBeyondFiveHundredAndFenceStaleCursors() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentKnowledgeSourcePageTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = AgentKnowledgeDatabase(
      fileURL: directory.appendingPathComponent("knowledge.sqlite"),
      secrets: InMemorySecretStore()
    )
    let items = (0..<601).map { index in
      AgentKnowledgeItem(
        id: "item-\(index)",
        kind: .document,
        title: "Source \(index)",
        content: "Private body \(index)",
        source: "source-\(index)",
        updatedAtMillis: Int64(index)
      )
    }
    XCTAssertTrue(database.replaceAll(items))

    var cursor: AgentKnowledgeSourceCursor?
    var firstCursor: AgentKnowledgeSourceCursor?
    var sources: [String] = []
    repeat {
      let page = try database.sourcePage(cursor: cursor)
      XCTAssertEqual(page.total, 601)
      XCTAssertLessThanOrEqual(page.groups.count, 50)
      XCTAssertTrue(page.groups.allSatisfy { $0.itemIds.isEmpty })
      sources += page.groups.map(\.source)
      cursor = page.next
      if firstCursor == nil { firstCursor = cursor }
    } while cursor != nil
    XCTAssertEqual(Set(sources).count, 601)

    var changed = items
    changed[0].title = "Changed"
    changed[0].updatedAtMillis = 10_000
    XCTAssertTrue(database.replaceAll(changed))
    XCTAssertThrowsError(try database.sourcePage(cursor: try XCTUnwrap(firstCursor))) { error in
      XCTAssertEqual(error as? AgentKnowledgeDatabaseError, .staleCursor)
    }

    let oneSource = (0..<601).map { index in
      AgentKnowledgeItem(
        id: "member-\(index)",
        kind: .document,
        title: "Large source [\(index + 1)/601]",
        content: "Chunk \(index)",
        source: "large-source"
      )
    }
    XCTAssertTrue(database.replaceAll(oneSource))
    XCTAssertEqual(try database.sourceItemIds(sourceIdentity: "large-source").count, 601)
  }

  func testEncryptedDatabaseRejectsIdentityCollisionsAndWrongKeys() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentKnowledgeDatabaseTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("knowledge.sqlite")
    let secrets = InMemorySecretStore()
    let first = AgentKnowledgeItem(id: "same", kind: .note, title: "First", content: "one", source: "a")
    let collision = AgentKnowledgeItem(id: "same", kind: .note, title: "Second", content: "two", source: "b")
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)

    XCTAssertTrue(database.replaceAll([first]))
    XCTAssertFalse(database.replaceAll([first, collision]))
    XCTAssertEqual(try database.all(), [first])
    XCTAssertThrowsError(try AgentKnowledgeDatabase(fileURL: url, secrets: InMemorySecretStore()).all())
  }

  func testEncryptedVectorCheckpointPersistsProvenanceAndInvalidatesChangedSource() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentKnowledgeDatabaseTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("knowledge.sqlite")
    let secrets = InMemorySecretStore()
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    let item = AgentKnowledgeItem(id: "item", kind: .note, title: "Title", content: "Body", source: "source")
    let modelSHA = String(repeating: "a", count: 64)
    let provenance = AgentKnowledgeVectorProvenance(
      modelSHA256: modelSHA,
      dimensions: 2,
      contextTokens: 512,
      chunkingContract: AgentKnowledgeEmbeddingChunker.contract
    )
    let checkpoint = AgentKnowledgeVectorCheckpoint(
      itemId: item.id,
      sourceRevision: AgentKnowledgeVectorCheckpoint.sourceRevision(for: item),
      chunkIndex: 0,
      vector: [0.6, 0.8],
      provenance: provenance,
      updatedAtMillis: 10
    )

    XCTAssertTrue(database.replaceAll([item]))
    XCTAssertTrue(database.storeVectorCheckpoint(checkpoint))
    XCTAssertFalse(database.storeVectorCheckpoint(checkpoint))
    XCTAssertEqual(try database.vectorCheckpoints(itemId: item.id, modelSHA256: modelSHA), [checkpoint])
    XCTAssertTrue(try database.pendingVectorItems(modelSHA256: modelSHA).isEmpty)

    let changed = AgentKnowledgeItem(id: "item", kind: .note, title: "Title", content: "Changed", source: "source")
    XCTAssertTrue(database.replaceAll([changed]))
    XCTAssertEqual(try database.pendingVectorItems(modelSHA256: modelSHA).map(\.id), ["item"])
    let raw = String(decoding: try Data(contentsOf: url), as: UTF8.self)
    XCTAssertFalse(raw.contains(modelSHA))
    XCTAssertFalse(raw.contains(checkpoint.sourceRevision))
  }

  func testVectorChangeFeedPublishesReadyAndRemovalWithDurableChain() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentKnowledgeVectorFeed-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("knowledge.sqlite")
    let secrets = InMemorySecretStore()
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    let item = AgentKnowledgeItem(id: "feed-item", kind: .note, title: "Title", content: "Body", source: "source")
    let modelSHA = String(repeating: "b", count: 64)
    let checkpoint = AgentKnowledgeVectorCheckpoint(
      itemId: item.id,
      sourceRevision: AgentKnowledgeVectorCheckpoint.sourceRevision(for: item),
      chunkIndex: 0,
      vector: [0.6, 0.8],
      provenance: AgentKnowledgeVectorProvenance(
        modelSHA256: modelSHA,
        dimensions: 2,
        contextTokens: 512,
        chunkingContract: AgentKnowledgeEmbeddingChunker.contract
      ),
      updatedAtMillis: 10
    )

    XCTAssertTrue(database.replaceAll([item]))
    XCTAssertTrue(database.storeVectorCheckpoint(checkpoint))
    let ready = try database.vectorChangePage(modelSHA256: modelSHA)
    XCTAssertEqual(ready.events.map(\.operation), [.ready])
    XCTAssertEqual(ready.events[0].previousSequence, 0)
    XCTAssertNotEqual(ready.events[0].itemHash, item.id)
    XCTAssertNotEqual(ready.events[0].sourceRevisionHash, checkpoint.sourceRevision)

    XCTAssertTrue(database.clearVectorCheckpoints(itemId: item.id, modelSHA256: modelSHA))
    let removal = try database.vectorChangePage(
      modelSHA256: modelSHA,
      epoch: ready.epoch,
      afterSequence: ready.events[0].sequence
    )
    XCTAssertEqual(removal.events.map(\.operation), [.removal])
    XCTAssertEqual(removal.events[0].previousSequence, ready.events[0].sequence)
    XCTAssertEqual(removal.headSequence, removal.events[0].sequence)

    let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    XCTAssertEqual(try reopened.vectorChangePage(modelSHA256: modelSHA).epoch, ready.epoch)
    XCTAssertThrowsError(try reopened.vectorChangePage(modelSHA256: modelSHA, epoch: "stale"))
  }

  func testEmbeddingChunkerUsesTokenizerWindowAndPreservesOrder() async throws {
    let chunks = try await AgentKnowledgeEmbeddingChunker.chunks(
      "abcdefghij",
      maximumTokens: 3,
      tokenCount: { $0.count }
    )

    XCTAssertEqual(chunks, ["abc", "def", "ghi", "j"])
    XCTAssertTrue(chunks.allSatisfy { $0.count <= 3 })
  }
}
