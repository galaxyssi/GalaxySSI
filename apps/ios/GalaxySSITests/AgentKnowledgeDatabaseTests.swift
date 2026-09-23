import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeDatabaseTests: XCTestCase {
  func testAdaptiveVectorStorageCompactsAndRestoresDirection() throws {
    let dimensions = 512
    let raw = (0..<dimensions).map { Float(sin(Double($0 + 1))) }
    let norm = sqrt(raw.reduce(0.0) { $0 + Double($1) * Double($1) })
    let vector = raw.map { Float(Double($0) / norm) }
    let checkpoint = AgentKnowledgeVectorCheckpoint(
      itemId: "compact-vector",
      sourceRevision: String(repeating: "a", count: 64),
      chunkIndex: 0,
      vector: vector,
      provenance: AgentKnowledgeVectorProvenance(
        modelSHA256: String(repeating: "b", count: 64),
        dimensions: dimensions,
        contextTokens: 512,
        chunkingContract: AgentKnowledgeEmbeddingChunker.contract
      )
    )

    let compact = try AgentKnowledgeVectorStorage.encode(checkpoint)
    let legacy = try JSONEncoder.galaxySSI.encode(checkpoint)
    let restored = try AgentKnowledgeVectorStorage.decode(compact)
    let squaredError = zip(vector, restored.vector).reduce(0.0) { result, values in
      let delta = Double(values.0) - Double(values.1)
      return result + delta * delta
    }

    XCTAssertEqual(AgentKnowledgeVectorStorage.codec(in: compact), .scalar8)
    XCTAssertLessThan(compact.count, legacy.count / 2)
    XCTAssertLessThanOrEqual(squaredError, 0.0001)
    XCTAssertEqual(restored.itemId, checkpoint.itemId)
    XCTAssertEqual(restored.provenance, checkpoint.provenance)
  }

  func testAdaptiveVectorStorageFallsBackAndReadsLegacyCheckpoint() throws {
    let checkpoint = AgentKnowledgeVectorCheckpoint(
      itemId: "legacy-vector",
      sourceRevision: String(repeating: "c", count: 64),
      chunkIndex: 0,
      vector: [0.6, 0.8],
      provenance: AgentKnowledgeVectorProvenance(
        modelSHA256: String(repeating: "d", count: 64),
        dimensions: 2,
        contextTokens: 512,
        chunkingContract: AgentKnowledgeEmbeddingChunker.contract
      )
    )

    let packed = try AgentKnowledgeVectorStorage.encode(checkpoint)
    let legacy = try JSONEncoder.galaxySSI.encode(checkpoint)

    XCTAssertEqual(AgentKnowledgeVectorStorage.codec(in: packed), .float32)
    XCTAssertEqual(try AgentKnowledgeVectorStorage.decode(packed), checkpoint)
    XCTAssertEqual(try AgentKnowledgeVectorStorage.decode(legacy), checkpoint)
  }

  func testAdaptiveVectorStorageUsesFloat16WhenScalarErrorIsTooLarge() throws {
    var sparse = [Float](repeating: 0, count: 512)
    sparse[37] = 1
    let checkpoint = AgentKnowledgeVectorCheckpoint(
      itemId: "sparse-vector",
      sourceRevision: String(repeating: "e", count: 64),
      chunkIndex: 0,
      vector: sparse,
      provenance: AgentKnowledgeVectorProvenance(
        modelSHA256: String(repeating: "f", count: 64),
        dimensions: sparse.count,
        contextTokens: 512,
        chunkingContract: AgentKnowledgeEmbeddingChunker.contract
      )
    )

    let packed = try AgentKnowledgeVectorStorage.encode(checkpoint)

    XCTAssertEqual(AgentKnowledgeVectorStorage.codec(in: packed), .float16)
    XCTAssertEqual(try AgentKnowledgeVectorStorage.decode(packed), checkpoint)
  }

  func testVectorEnrollmentPagesPersistAcrossReopenWithoutWholeCorpusScan() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentKnowledgeEnrollment-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("knowledge.sqlite")
    let secrets = InMemorySecretStore()
    let modelSHA = String(repeating: "9", count: 64)
    let items = (0..<131).map { index in
      AgentKnowledgeItem(
        id: "enrollment-item-\(index)",
        kind: .document,
        title: "Enrollment \(index)",
        content: "Private source body \(index)",
        source: "source-\(index)"
      )
    }
    func finish(_ page: [AgentKnowledgeItem], in database: AgentKnowledgeDatabase) {
      for item in page {
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
          )
        )
        XCTAssertTrue(database.storeVectorCheckpoint(checkpoint))
      }
    }

    let initial = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    XCTAssertTrue(initial.replaceAll(items))
    let first = try initial.pendingVectorItems(modelSHA256: modelSHA, limit: 64)
    XCTAssertEqual(first.count, 64)
    XCTAssertEqual(
      try initial.vectorCountSnapshot(modelSHA256: modelSHA),
      AgentKnowledgeVectorCountSnapshot(chunks: 0, pending: 64, complete: true)
    )
    XCTAssertTrue(try initial.vectorEnrollmentPending(modelSHA256: modelSHA))
    finish(first, in: initial)

    let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    let second = try reopened.pendingVectorItems(modelSHA256: modelSHA, limit: 64)
    XCTAssertEqual(second.count, 64)
    XCTAssertTrue(Set(first.map(\.id)).isDisjoint(with: Set(second.map(\.id))))
    finish(second, in: reopened)
    let third = try reopened.pendingVectorItems(modelSHA256: modelSHA, limit: 64)
    XCTAssertEqual(third.count, 3)
    finish(third, in: reopened)

    XCTAssertEqual(Set((first + second + third).map(\.id)), Set(items.map(\.id)))
    XCTAssertFalse(try reopened.vectorEnrollmentPending(modelSHA256: modelSHA))
    XCTAssertTrue(try reopened.pendingVectorItems(modelSHA256: modelSHA).isEmpty)
    XCTAssertEqual(
      try reopened.vectorCountSnapshot(modelSHA256: modelSHA),
      AgentKnowledgeVectorCountSnapshot(chunks: 131, pending: 0, complete: true)
    )
    let raw = String(decoding: try Data(contentsOf: url), as: UTF8.self)
    XCTAssertFalse(raw.contains("enrollment-item-"))
    XCTAssertFalse(raw.contains(modelSHA))
  }

  func testVectorCountMaintenanceIsRestartableAndBounded() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentKnowledgeCounts-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("knowledge.sqlite")
    let secrets = InMemorySecretStore()
    let modelSHA = String(repeating: "8", count: 64)
    var legacy: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &legacy), SQLITE_OK)
    defer { if let legacy { sqlite3_close_v2(legacy) } }
    func executeLegacy(_ sql: String) {
      XCTAssertEqual(sqlite3_exec(legacy, sql, nil, nil, nil), SQLITE_OK)
    }
    executeLegacy("CREATE TABLE knowledge_metadata(key TEXT PRIMARY KEY, value INTEGER NOT NULL)")
    executeLegacy("INSERT INTO knowledge_metadata VALUES('source_header_schema', 2)")
    executeLegacy("""
      CREATE TABLE knowledge_vectors(
        vector_key TEXT PRIMARY KEY NOT NULL, item_hash TEXT NOT NULL, model_hash TEXT NOT NULL,
        source_revision_hash TEXT NOT NULL, updated_at INTEGER NOT NULL, encrypted_payload BLOB NOT NULL
      )
      """)
    executeLegacy("""
      CREATE TABLE knowledge_vector_queue(
        model_hash TEXT NOT NULL, item_hash TEXT NOT NULL, PRIMARY KEY(model_hash, item_hash)
      )
      """)
    for index in 1...70 {
      let vector = String(format: "%064x", index)
      let item = String(format: "%064x", index + 1_000)
      executeLegacy("""
        INSERT INTO knowledge_vectors VALUES(
          '\(vector)', '\(item)', '\(modelSHA)', '\(String(repeating: "7", count: 64))', \(index), X'00'
        )
        """)
      executeLegacy("INSERT INTO knowledge_vector_queue VALUES('\(modelSHA)', '\(item)')")
    }
    sqlite3_close_v2(legacy)
    legacy = nil

    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    XCTAssertEqual(
      try database.vectorCountSnapshot(modelSHA256: modelSHA),
      AgentKnowledgeVectorCountSnapshot(chunks: 0, pending: 0, complete: false)
    )
    XCTAssertFalse(try database.maintainVectorCounts(pageSize: 16))
    let partial = try database.vectorCountSnapshot(modelSHA256: modelSHA)
    XCTAssertEqual(partial.chunks, 16)
    XCTAssertEqual(partial.pending, 16)
    XCTAssertFalse(partial.complete)

    let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    while true {
      if try reopened.maintainVectorCounts(pageSize: 16) { break }
    }
    XCTAssertEqual(
      try reopened.vectorCountSnapshot(modelSHA256: modelSHA),
      AgentKnowledgeVectorCountSnapshot(chunks: 70, pending: 70, complete: true)
    )
  }

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
    let secrets = InMemorySecretStore()
    let database = AgentKnowledgeDatabase(
      fileURL: directory.appendingPathComponent("knowledge.sqlite"),
      secrets: secrets
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
    let reopened = AgentKnowledgeDatabase(
      fileURL: directory.appendingPathComponent("knowledge.sqlite"),
      secrets: secrets
    )
    XCTAssertEqual(try reopened.sourcePage().total, 601)

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

  func testSourcePreviewsArePersistedLazilyAndRejectHeaderMismatch() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentKnowledgeSourcePreviewTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("knowledge.sqlite")
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: InMemorySecretStore())
    let items = (0..<3).map { index in
      AgentKnowledgeItem(
        id: "preview-item-\(index)",
        kind: .document,
        title: "Preview \(index)",
        content: "Private preview body \(index)",
        source: "preview-source-\(index)",
        updatedAtMillis: Int64(index + 1)
      )
    }
    XCTAssertTrue(database.replaceAll(items))

    var raw: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
    XCTAssertEqual(sqlite3_exec(raw, "DELETE FROM knowledge_source_previews", nil, nil, nil), SQLITE_OK)
    sqlite3_close_v2(raw)
    raw = nil

    XCTAssertEqual(try database.sourcePage().groups.count, 3)
    XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
    var count: OpaquePointer?
    XCTAssertEqual(sqlite3_prepare_v2(raw, "SELECT COUNT(*) FROM knowledge_source_previews", -1, &count, nil), SQLITE_OK)
    XCTAssertEqual(sqlite3_step(count), SQLITE_ROW)
    XCTAssertEqual(sqlite3_column_int64(count, 0), 3)
    sqlite3_finalize(count)
    XCTAssertEqual(
      sqlite3_exec(raw, "UPDATE knowledge_source_previews SET header_fingerprint = zeroblob(32)", nil, nil, nil),
      SQLITE_OK
    )
    sqlite3_close_v2(raw)

    XCTAssertThrowsError(try database.sourcePage()) { error in
      XCTAssertEqual(error as? AgentKnowledgeDatabaseError, .corruptRecord)
    }
  }

  func testSourceSnapshotPagesMembersAndRejectsStaleRevision() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentKnowledgeSourceSnapshotTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = AgentKnowledgeDatabase(
      fileURL: directory.appendingPathComponent("knowledge.sqlite"),
      secrets: InMemorySecretStore()
    )
    var items = (0..<130).map { index in
      AgentKnowledgeItem(
        id: "snapshot-member-\(index)",
        kind: .document,
        title: "Snapshot source [\(index + 1)/130]",
        content: "Authenticated body \(index)",
        source: "snapshot-source",
        chunkIndex: index,
        chunkCount: 130,
        updatedAtMillis: Int64(1_000 - index)
      )
    }
    XCTAssertTrue(database.replaceAll(items))
    let group = try XCTUnwrap(try database.sourcePage().groups.first)
    let snapshot = try database.sourceSnapshotItems(group)
    XCTAssertEqual(snapshot.count, 130)
    XCTAssertEqual(snapshot.map(\.chunkIndex), Array(0..<130))
    XCTAssertEqual(snapshot.first?.content, "Authenticated body 0")

    items[0].content = "Changed after revision capture"
    items[0].updatedAtMillis = 2_000
    XCTAssertTrue(database.replaceAll(items))
    XCTAssertThrowsError(try database.sourceSnapshotItems(group)) { error in
      XCTAssertEqual(error as? AgentKnowledgeDatabaseError, .staleCursor)
    }
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
