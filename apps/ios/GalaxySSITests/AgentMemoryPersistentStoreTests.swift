import CryptoKit
import XCTest
@testable import GalaxySSI

final class AgentMemoryPersistentStoreTests: XCTestCase {
  func testUserDefaultsMemoryStorePersistsRecallMetadataAcrossReload() throws {
    let suiteName = "AgentMemoryPersistentStoreTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let secrets = InMemorySecretStore()
    var now: Int64 = 5_000
    let store = UserDefaultsAgentMemoryStore(defaults: defaults, secrets: secrets, nowMillis: { now })

    store.remember(memory(id: "memory-a", value: "GalaxySSI stores private memory on device", key: "storage", timestampMillis: 1_000))
    now = 6_000
    XCTAssertEqual(store.recall(query: "private memory").map(\.id), ["memory-a"])

    let reloaded = UserDefaultsAgentMemoryStore(defaults: defaults, secrets: secrets, nowMillis: { now })
    XCTAssertEqual(reloaded.exportItems().map(\.id), ["memory-a"])
    XCTAssertEqual(reloaded.exportItems().first?.lastAccessedAtMillis, 6_000)
    XCTAssertNil(defaults.data(forKey: UserDefaultsAgentMemoryStore.defaultKey))
    XCTAssertNotNil(defaults.data(forKey: "galaxyssi_agent_memory_rows_v3-metadata.encrypted.v1"))
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

  func testPersonalMemoryRowsPersistIndependentEncryptedRecordsAtScale() throws {
    let suiteName = "AgentPersonalMemoryRowsScale-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let secrets = InMemorySecretStore()
    let rows = UserDefaultsAgentPersonalMemoryRows(defaults: defaults, secrets: secrets)
    let items = (0..<1_201).map { index in
      memory(id: "memory-\(index)", value: "Value \(index)", key: "key-\(index)", timestampMillis: Int64(index))
    }

    XCTAssertTrue(rows.replace(items))
    XCTAssertEqual(rows.read(), items)
    XCTAssertEqual(
      GalaxySSIEncryptedUserDefaultsStore.storedKeys(defaults: defaults, prefix: "galaxyssi_agent_memory_rows_v3-row-").count,
      items.count
    )
    XCTAssertFalse(rows.replace(items + [items[0]]))
  }

  func testPersonalMemoryRowDestroyRemovesMetadataAndRows() throws {
    let suiteName = "AgentPersonalMemoryRowsDestroy-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let secrets = InMemorySecretStore()
    let rows = UserDefaultsAgentPersonalMemoryRows(defaults: defaults, secrets: secrets)
    XCTAssertTrue(rows.replace([memory(id: "memory-a", value: "Value", key: "key", timestampMillis: 1_000)]))

    rows.destroy()

    XCTAssertFalse(rows.exists)
    XCTAssertTrue(GalaxySSIEncryptedUserDefaultsStore.storedKeys(
      defaults: defaults,
      prefix: "galaxyssi_agent_memory_rows_v3-row-"
    ).isEmpty)
  }

  func testPersonalMemoryPointFlagsUpdateOnlyTargetRow() throws {
    let suiteName = "AgentPersonalMemoryPointFlags-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let secrets = InMemorySecretStore()
    let rows = UserDefaultsAgentPersonalMemoryRows(defaults: defaults, secrets: secrets)
    let target = memory(id: "target", value: "Chinese", key: "language", timestampMillis: 1_000)
    let unrelated = memory(id: "unrelated", value: "English", key: "language", timestampMillis: 2_000)
    XCTAssertTrue(rows.replace([target, unrelated]))

    let important = try XCTUnwrap(rows.updateFlags(id: target.id, important: true))
    XCTAssertEqual(important.before, target)
    XCTAssertTrue(important.after.important)
    XCTAssertEqual(rows.find(id: unrelated.id), unrelated)

    let privateChange = try XCTUnwrap(rows.updateFlags(id: target.id, privateMemory: true))
    XCTAssertTrue(privateChange.after.privateMemory)
    XCTAssertTrue(rows.find(id: target.id)?.important == true)
    XCTAssertNil(rows.find(id: "missing"))
  }

  func testIncrementalRememberPreservesUnchangedRowCiphertextAndHistory() throws {
    let suiteName = "AgentPersonalMemoryIncremental-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let secrets = InMemorySecretStore()
    let store = UserDefaultsAgentMemoryStore(defaults: defaults, secrets: secrets)
    let unrelated = memory(id: "unrelated", value: "Keep ciphertext", key: "note", timestampMillis: 1_000)
    store.remember(unrelated)
    let rowKey = "galaxyssi_agent_memory_rows_v3-row-\(SHA256.hash(data: Data(unrelated.id.utf8)).map { String(format: "%02x", $0) }.joined()).encrypted.v1"
    let ciphertext = try XCTUnwrap(defaults.data(forKey: rowKey))

    store.remember(memory(id: "new", value: "New value", key: "other", timestampMillis: 2_000))

    XCTAssertEqual(defaults.data(forKey: rowKey), ciphertext)
    XCTAssertEqual(store.exportItems().count, 2)
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
