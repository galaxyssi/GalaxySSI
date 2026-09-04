import XCTest
@testable import SignalASI

final class AgentMemoryPersistentStoreTests: XCTestCase {
  func testUserDefaultsMemoryStorePersistsRecallMetadataAcrossReload() throws {
    let suiteName = "AgentMemoryPersistentStoreTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let secrets = InMemorySecretStore()
    var now: Int64 = 5_000
    let store = UserDefaultsAgentMemoryStore(defaults: defaults, secrets: secrets, nowMillis: { now })

    store.remember(memory(id: "memory-a", value: "SignalASI stores private memory on device", key: "storage", timestampMillis: 1_000))
    now = 6_000
    XCTAssertEqual(store.recall(query: "private memory").map(\.id), ["memory-a"])

    let reloaded = UserDefaultsAgentMemoryStore(defaults: defaults, secrets: secrets, nowMillis: { now })
    XCTAssertEqual(reloaded.exportItems().map(\.id), ["memory-a"])
    XCTAssertEqual(reloaded.exportItems().first?.lastAccessedAtMillis, 6_000)
    XCTAssertNil(defaults.data(forKey: UserDefaultsAgentMemoryStore.defaultKey))
    XCTAssertNotNil(defaults.data(forKey: "\(UserDefaultsAgentMemoryStore.defaultKey)-encrypted-v3.encrypted.v1"))
  }

  func testUserDefaultsMemoryStoreRecordsDeletionAndFiltersStaleRestore() throws {
    let suiteName = "AgentMemoryPersistentStoreDeletion-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let deletionIndex = UserDefaultsAgentMemoryDeletionIndex(defaults: defaults)
    var published: [GlobalConversationEvent] = []
    let store = UserDefaultsAgentMemoryStore(
      defaults: defaults,
      deletionIndex: deletionIndex,
      nowMillis: { 3_000 },
      retractionSink: { published.append(contentsOf: $0) }
    )
    let deleted = memory(id: "memory-current", value: "Prefer concise output", key: "response style", timestampMillis: 2_000)
    store.remember(deleted)

    XCTAssertTrue(store.deleteById(deleted.id))
    let stale = memory(id: "memory-old", value: "Prefer verbose output", key: "response style", timestampMillis: 1_000)
    let allowed = memory(id: "memory-new", value: "Prefer warm output", key: "response style", timestampMillis: 4_000)

    XCTAssertEqual(store.restoreBackupItems([stale, allowed], tombstones: deletionIndex.snapshot()).map(\.id), ["memory-new"])
    XCTAssertTrue(deletionIndex.snapshot().single?.memoryIds.contains("memory-current") ?? false)
    XCTAssertEqual(published.single?.metadata["projection"], "retract_only")
    XCTAssertTrue(published.single?.retractedEventIds.contains("memory-root:memory-current") ?? false)
  }

  func testUserDefaultsMemoryStorePreservesConflictAndLineageDeletes() throws {
    let suiteName = "AgentMemoryPersistentStoreLineage-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let deletionIndex = UserDefaultsAgentMemoryDeletionIndex(defaults: defaults)
    let store = UserDefaultsAgentMemoryStore(defaults: defaults, deletionIndex: deletionIndex, nowMillis: { 4_000 })
    store.remember(memory(id: "tone-a", value: "tone=brief", key: "tone", timestampMillis: 1_000))
    let second = store.remember(memory(id: "tone-b", value: "tone=warm", key: "tone", timestampMillis: 2_000))
    let conflict = try XCTUnwrap(second.conflict)
    let resolved = try XCTUnwrap(store.resolveConflict(
      groupId: conflict.groupId,
      selectedItemId: "tone-b",
      mergedValue: "tone=brief but warm"
    ))

    XCTAssertTrue(store.deleteById(resolved.id, deletedAtMillis: 5_000))

    let tombstone = try XCTUnwrap(deletionIndex.snapshot().single)
    XCTAssertTrue(tombstone.memoryIds.contains("tone-a"))
    XCTAssertTrue(tombstone.memoryIds.contains("tone-b"))
    XCTAssertTrue(tombstone.memoryIds.contains(resolved.id))
    XCTAssertTrue(store.exportItems().isEmpty)
  }

  func testDestroyPersistentStoreRemovesOnlyMemoryItems() throws {
    let suiteName = "AgentMemoryPersistentStoreDestroy-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let deletionIndex = UserDefaultsAgentMemoryDeletionIndex(defaults: defaults)
    let store = UserDefaultsAgentMemoryStore(defaults: defaults, deletionIndex: deletionIndex)
    store.remember(memory(id: "memory-a", value: "Keep this", key: "note", timestampMillis: 1_000))
    deletionIndex.record(deletedItems: [memory(id: "memory-b", value: "Delete this", key: "note", timestampMillis: 1_000)])

    UserDefaultsAgentMemoryStore.destroyPersistentStore(defaults: defaults)

    XCTAssertTrue(UserDefaultsAgentMemoryStore(defaults: defaults, deletionIndex: deletionIndex).exportItems().isEmpty)
    XCTAssertFalse(deletionIndex.snapshot().isEmpty)
  }

  private func memory(id: String, value: String, key: String, timestampMillis: Int64) -> AgentMemoryItem {
    AgentMemoryItem(
      kind: .preference,
      value: value,
      timestampMillis: timestampMillis,
      id: id,
      key: key
    )
  }
}

private extension Array {
  var single: Element? {
    count == 1 ? self[0] : nil
  }
}
