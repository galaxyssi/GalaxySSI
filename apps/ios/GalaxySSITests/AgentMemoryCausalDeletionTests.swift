import XCTest
@testable import GalaxySSI

@MainActor
final class AgentMemoryCausalDeletionTests: XCTestCase {
  func testTombstoneContainsOnlyIdentifiersHashesAndRetractions() throws {
    let deleted = memory(
      id: "memory-v2",
      value: "My private preference is concise output",
      key: "response style",
      timestampMillis: 2_000
    )

    let tombstone = try XCTUnwrap(
      AgentMemoryCausalDeletionPolicy.tombstone(deletedItems: [deleted], deletedAtMillis: 3_000)
    )
    let encoded = String(decoding: try JSONEncoder().encode(tombstone), as: UTF8.self)

    XCTAssertTrue(tombstone.memoryIds.contains("memory-v2"))
    XCTAssertTrue(tombstone.retractedEventIds.contains("memory-root:memory-v2"))
    XCTAssertFalse(encoded.contains(deleted.value))
    XCTAssertFalse(encoded.contains(deleted.key))
  }

  func testDeletedSemanticIdentityCannotReturnFromOlderBackup() throws {
    let deleted = memory(
      id: "memory-current",
      value: "Prefer concise output",
      key: "response style",
      timestampMillis: 2_000
    )
    let tombstone = try XCTUnwrap(
      AgentMemoryCausalDeletionPolicy.tombstone(deletedItems: [deleted], deletedAtMillis: 3_000)
    )
    let staleBackup = memory(
      id: "memory-old-backup",
      value: "Prefer verbose output",
      key: "response style",
      timestampMillis: 1_000
    )
    let unrelated = memory(
      id: "memory-other",
      value: "Use English",
      key: "language",
      timestampMillis: 1_000
    )

    let filtered = AgentMemoryCausalDeletionPolicy.filterRestoredItems(
      [staleBackup, unrelated],
      tombstones: [tombstone]
    )

    XCTAssertEqual(filtered, [unrelated])
  }

  func testDeliberateNewMemoryAfterDeletionIsAllowed() throws {
    let deleted = memory(
      id: "memory-old",
      value: "Use light mode",
      key: "theme",
      timestampMillis: 1_000
    )
    let tombstone = try XCTUnwrap(
      AgentMemoryCausalDeletionPolicy.tombstone(deletedItems: [deleted], deletedAtMillis: 2_000)
    )
    let newMemory = memory(
      id: "memory-new",
      value: "Use dark mode",
      key: "theme",
      timestampMillis: 3_000
    )

    XCTAssertEqual(
      AgentMemoryCausalDeletionPolicy.filterRestoredItems([newMemory], tombstones: [tombstone]),
      [newMemory]
    )
  }

  func testRetractionEventRetractsEveryDeletedVersionWithoutContent() throws {
    let first = memory("memory-v1", "Use one-line answers", "response style", 1_000)
    let second = memory(
      id: "memory-v2",
      value: "Use concise verified answers",
      key: "response style",
      timestampMillis: 2_000,
      version: 2,
      supersedesId: first.id
    )
    let tombstone = try XCTUnwrap(
      AgentMemoryCausalDeletionPolicy.tombstone(deletedItems: [first, second], deletedAtMillis: 3_000)
    )

    let events = AgentMemoryCausalDeletionPolicy.retractionEvents(tombstone)
    let event = try XCTUnwrap(events.single)

    XCTAssertEqual(event.type, .memoryDeleted)
    XCTAssertEqual(event.metadata["projection"], "retract_only")
    XCTAssertTrue(event.content.isEmpty)
    XCTAssertTrue(event.retractedEventIds.contains("memory-root:memory-v1"))
    XCTAssertTrue(event.retractedEventIds.contains("memory-root:memory-v2"))
    XCTAssertEqual(event.retractedEventIds, tombstone.retractedEventIds)
  }

  func testLargeDeletionIsSplitWithoutLosingRetractions() throws {
    let deleted = (1...140).map { index in
      memory(
        id: "memory-\(index)",
        value: "Value \(index)",
        key: "key-\(index)",
        timestampMillis: Int64(index)
      )
    }
    let tombstone = try XCTUnwrap(
      AgentMemoryCausalDeletionPolicy.tombstone(deletedItems: deleted, deletedAtMillis: 2_000)
    )

    let events = AgentMemoryCausalDeletionPolicy.retractionEvents(tombstone)

    XCTAssertGreaterThan(events.count, 1)
    XCTAssertTrue(events.allSatisfy { $0.retractedEventIds.count <= AgentMemoryCausalDeletionPolicy.maxRetractionsPerEvent })
    XCTAssertEqual(Set(events.flatMap { Array($0.retractedEventIds) }), tombstone.retractedEventIds)
  }

  func testDeletionRecordingStorePublishesRetractionEvents() throws {
    let base = InMemoryAgentMemoryStore(items: [
      memory(id: "memory-a", value: "Prefer concise output", key: "response style", timestampMillis: 1_000)
    ])
    let index = InMemoryAgentMemoryDeletionIndex()
    var published: [GlobalConversationEvent] = []
    let store = AgentMemoryDeletionRecordingStore(
      base: base,
      deletionIndex: index,
      nowMillis: { 2_000 },
      retractionSink: { published.append(contentsOf: $0) }
    )

    XCTAssertEqual(store.delete(query: "concise"), 1)

    let tombstone = try XCTUnwrap(index.snapshot().single)
    XCTAssertTrue(tombstone.memoryIds.contains("memory-a"))
    XCTAssertEqual(published.single?.metadata["projection"], "retract_only")
    XCTAssertTrue(published.single?.retractedEventIds.contains("memory-root:memory-a") ?? false)
  }

  func testUserDefaultsIndexPersistsMergesAndFiltersBackupItems() throws {
    let suiteName = "AgentMemoryCausalDeletionTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let index = UserDefaultsAgentMemoryDeletionIndex(defaults: defaults)
    let deleted = memory(id: "memory-a", value: "Use light mode", key: "theme", timestampMillis: 1_000)

    let tombstone = try XCTUnwrap(index.record(deletedItems: [deleted], deletedAtMillis: 2_000))
    let restored = UserDefaultsAgentMemoryDeletionIndex(defaults: defaults)
    let stale = memory(id: "memory-old", value: "Use blue mode", key: "theme", timestampMillis: 1_500)
    let allowed = memory(id: "memory-new", value: "Use dark mode", key: "theme", timestampMillis: 3_000)

    XCTAssertEqual(restored.snapshot(), [tombstone])
    XCTAssertEqual(restored.filterBackupItems([stale, allowed]), [allowed])
    UserDefaultsAgentMemoryDeletionIndex.destroyPersistentStore(defaults: defaults)
    XCTAssertTrue(restored.snapshot().isEmpty)
  }

  func testStoreBackupRestoresDeletionIndexBeforeMemory() throws {
    let sourceSuiteName = "AgentMemoryBackupSource-\(UUID().uuidString)"
    let restoredSuiteName = "AgentMemoryBackupRestored-\(UUID().uuidString)"
    let sourceDefaults = try XCTUnwrap(UserDefaults(suiteName: sourceSuiteName))
    let restoredDefaults = try XCTUnwrap(UserDefaults(suiteName: restoredSuiteName))
    defer {
      UserDefaults.standard.removePersistentDomain(forName: sourceSuiteName)
      UserDefaults.standard.removePersistentDomain(forName: restoredSuiteName)
    }
    let source = GalaxySSIStore(defaults: sourceDefaults, secrets: InMemorySecretStore())
    let deleted = memory(id: "memory-current", value: "Prefer concise output", key: "response style", timestampMillis: 2_000)
    source.replaceAgentMemoryItems([deleted])
    XCTAssertTrue(source.deleteAgentMemory(id: deleted.id, deletedAtMillis: 3_000))
    let staleBackupMemory = memory(id: "memory-old", value: "Prefer verbose output", key: "response style", timestampMillis: 1_000)

    var payload = source.exportBackupPayload(includeContacts: true, includeMessages: false)
    payload.agentData.memory = [staleBackupMemory]
    let restored = GalaxySSIStore(defaults: restoredDefaults, secrets: InMemorySecretStore())
    try restored.restoreBackupPayload(payload)

    XCTAssertTrue(payload.agentData.memoryDeletionIndex?.isEmpty == false)
    XCTAssertTrue(restored.exportAgentMemoryItems().isEmpty)
    XCTAssertTrue(restored.agentMemoryDeletionTombstones().isEmpty == false)
  }

  private func memory(
    _ id: String,
    _ value: String,
    _ key: String,
    _ timestampMillis: Int64
  ) -> AgentMemoryItem {
    memory(id: id, value: value, key: key, timestampMillis: timestampMillis)
  }

  private func memory(
    id: String,
    value: String,
    key: String,
    timestampMillis: Int64,
    version: Int = 1,
    supersedesId: String = ""
  ) -> AgentMemoryItem {
    AgentMemoryItem(
      kind: .preference,
      value: value,
      timestampMillis: timestampMillis,
      id: id,
      key: key,
      version: version,
      supersedesId: supersedesId
    )
  }

}

private extension Array {
  var single: Element? {
    count == 1 ? self[0] : nil
  }
}
