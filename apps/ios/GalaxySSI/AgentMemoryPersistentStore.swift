import CryptoKit
import Foundation

final class UserDefaultsAgentMemoryStore: AgentMemoryStore {
  static let defaultKey = "galaxyssi_agent_memory_v2"

  private let defaults: UserDefaults
  private let key: String
  private let encryptedKey: String
  private let secrets: GalaxySSISecretStore
  private let deletionIndex: AgentMemoryDeletionIndex
  private let nowMillis: () -> Int64
  private let retractionSink: ([GlobalConversationEvent]) -> Void
  private let lock = NSLock()
  private let rows: UserDefaultsAgentPersonalMemoryRows
  private var base: InMemoryAgentMemoryStore

  init(
    defaults: UserDefaults = .standard,
    key: String = UserDefaultsAgentMemoryStore.defaultKey,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    deletionIndex: AgentMemoryDeletionIndex? = nil,
    nowMillis: @escaping () -> Int64 = AgentMemoryClock.nowMillis,
    retractionSink: @escaping ([GlobalConversationEvent]) -> Void = { _ in }
  ) {
    self.defaults = defaults
    self.key = key
    self.encryptedKey = "\(key)-encrypted-v3"
    self.secrets = secrets
    self.deletionIndex = deletionIndex ?? UserDefaultsAgentMemoryDeletionIndex(defaults: defaults, secrets: secrets)
    self.nowMillis = nowMillis
    self.retractionSink = retractionSink
    let rows = UserDefaultsAgentPersonalMemoryRows(defaults: defaults, secrets: secrets)
    self.rows = rows
    let encrypted = GalaxySSIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: encryptedKey,
      secrets: secrets
    )
    let restoredItems = rows.read() ?? Self.decodeItems(encrypted ?? defaults.data(forKey: key))
    let filtered = AgentMemoryCausalDeletionPolicy.filterRestoredItems(
      restoredItems,
      tombstones: self.deletionIndex.snapshot()
    )
    self.base = InMemoryAgentMemoryStore(
      items: Self.normalizedItems(filtered),
      nowMillis: nowMillis
    )
    persist()
  }

  static func destroyPersistentStore(
    defaults: UserDefaults = .standard,
    key: String = UserDefaultsAgentMemoryStore.defaultKey,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  ) {
    defaults.removeObject(forKey: key)
    UserDefaultsAgentPersonalMemoryRows(defaults: defaults, secrets: secrets).destroy()
    GalaxySSIEncryptedUserDefaultsStore.destroy(
      defaults: defaults,
      key: "\(key)-encrypted-v3",
      secrets: secrets
    )
  }

  @discardableResult
  func remember(_ item: AgentMemoryItem) -> AgentMemoryWriteResult {
    locked {
      let result = base.remember(item)
      persistUnlocked()
      return result
    }
  }

  func recall(query: String) -> [AgentMemoryItem] {
    locked {
      let result = base.recall(query: query)
      persistUnlocked()
      return result
    }
  }

  func recent(limit: Int = 10) -> [AgentMemoryItem] {
    locked {
      base.recent(limit: limit)
    }
  }

  func count() -> Int {
    locked {
      base.count()
    }
  }

  @discardableResult
  func rebindConversationScope(sourceConversationId: String, targetConversationId: String) -> Int {
    locked {
      let changed = base.rebindConversationScope(
        sourceConversationId: sourceConversationId,
        targetConversationId: targetConversationId
      )
      if changed > 0 {
        persistUnlocked()
      }
      return changed
    }
  }

  @discardableResult
  func delete(query: String) -> Int {
    var events: [GlobalConversationEvent] = []
    let deletedCount = locked {
      let before = currentItemsUnlocked()
      let deletedAtMillis = nowMillis()
      let count = base.delete(query: query)
      guard count > 0 else { return 0 }
      persistUnlocked()
      events = recordDeletedItemsUnlocked(
        before: before,
        after: currentItemsUnlocked(),
        deletedAtMillis: deletedAtMillis
      )
      return count
    }
    publish(events)
    return deletedCount
  }

  func snapshot() -> AgentMemorySnapshot {
    locked {
      base.snapshot()
    }
  }

  @discardableResult
  func update(itemId: String, value: String, key: String) -> AgentMemoryWriteResult? {
    locked {
      let result = base.update(itemId: itemId, value: value, key: key)
      if result != nil {
        persistUnlocked()
      }
      return result
    }
  }

  @discardableResult
  func deleteById(_ itemId: String) -> Bool {
    deleteById(itemId, deletedAtMillis: nowMillis())
  }

  @discardableResult
  func deleteById(_ itemId: String, deletedAtMillis: Int64) -> Bool {
    var events: [GlobalConversationEvent] = []
    let deleted = locked {
      let before = currentItemsUnlocked()
      guard base.deleteById(itemId) else { return false }
      persistUnlocked()
      events = recordDeletedItemsUnlocked(
        before: before,
        after: currentItemsUnlocked(),
        deletedAtMillis: deletedAtMillis
      )
      return true
    }
    publish(events)
    return deleted
  }

  @discardableResult
  func setImportant(itemId: String, important: Bool) -> Bool {
    locked {
      guard rows.updateFlags(id: itemId, important: important) != nil else { return false }
      return base.setImportant(itemId: itemId, important: important)
    }
  }

  @discardableResult
  func setPrivate(itemId: String, privateMemory: Bool) -> Bool {
    locked {
      guard rows.updateFlags(id: itemId, privateMemory: privateMemory) != nil else { return false }
      return base.setPrivate(itemId: itemId, privateMemory: privateMemory)
    }
  }

  @discardableResult
  func deprecate(itemId: String) -> Bool {
    locked {
      let changed = base.deprecate(itemId: itemId)
      if changed { persistUnlocked() }
      return changed
    }
  }

  @discardableResult
  func resolveConflict(groupId: String, selectedItemId: String, mergedValue: String?) -> AgentMemoryItem? {
    locked {
      let resolved = base.resolveConflict(
        groupId: groupId,
        selectedItemId: selectedItemId,
        mergedValue: mergedValue
      )
      if resolved != nil {
        persistUnlocked()
      }
      return resolved
    }
  }

  func exportItems() -> [AgentMemoryItem] {
    locked {
      deletionIndex.filterBackupItems(currentItemsUnlocked())
    }
  }

  @discardableResult
  func replaceAll(_ items: [AgentMemoryItem]) -> Int {
    locked {
      let filtered = deletionIndex.filterBackupItems(items)
      base = InMemoryAgentMemoryStore(
        items: Self.normalizedItems(filtered),
        nowMillis: nowMillis
      )
      persistUnlocked()
      return currentItemsUnlocked().count
    }
  }

  @discardableResult
  func restoreBackupItems(
    _ items: [AgentMemoryItem]?,
    tombstones: [AgentMemoryDeletionTombstone]?
  ) -> [AgentMemoryItem] {
    let merged = deletionIndex.mergeBackup(tombstones)
    return locked {
      if let items {
        base = InMemoryAgentMemoryStore(
          items: Self.normalizedItems(
            AgentMemoryCausalDeletionPolicy.filterRestoredItems(items, tombstones: merged)
          ),
          nowMillis: nowMillis
        )
      } else if tombstones != nil {
        base = InMemoryAgentMemoryStore(
          items: Self.normalizedItems(
            AgentMemoryCausalDeletionPolicy.filterRestoredItems(currentItemsUnlocked(), tombstones: merged)
          ),
          nowMillis: nowMillis
        )
      }
      persistUnlocked()
      return exportItemsUnlocked()
    }
  }

  func clear() {
    locked {
      base = InMemoryAgentMemoryStore(nowMillis: nowMillis)
      GalaxySSIEncryptedUserDefaultsStore.destroy(
        defaults: defaults,
        key: encryptedKey,
        secrets: secrets
      )
      defaults.removeObject(forKey: key)
      rows.destroy()
    }
  }

  static func normalizedItems(_ items: [AgentMemoryItem]) -> [AgentMemoryItem] {
    var byId: [String: AgentMemoryItem] = [:]
    for item in items where !item.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      byId[item.id] = item
    }
    return Array(byId.values)
      .sorted { $0.timestampMillis < $1.timestampMillis }
      .suffix(AgentMemoryPolicy.maxItems)
      .map { $0 }
  }

  private static func decodeItems(_ data: Data?) -> [AgentMemoryItem] {
    guard let data,
          let decoded = try? AgentMemoryJSONCodec.decodeItems(data) else {
      return []
    }
    return normalizedItems(decoded)
  }

  private func currentItemsUnlocked() -> [AgentMemoryItem] {
    AgentMemoryCausalDeletionPolicy.items(in: base.snapshot())
  }

  private func exportItemsUnlocked() -> [AgentMemoryItem] {
    deletionIndex.filterBackupItems(currentItemsUnlocked())
  }

  private func recordDeletedItemsUnlocked(
    before: [AgentMemoryItem],
    after: [AgentMemoryItem],
    deletedAtMillis: Int64
  ) -> [GlobalConversationEvent] {
    let remainingIds = Set(after.map(\.id))
    let deletedItems = before.filter { !remainingIds.contains($0.id) }
    guard let tombstone = deletionIndex.record(
      deletedItems: deletedItems,
      deletedAtMillis: deletedAtMillis
    ) else {
      return []
    }
    return AgentMemoryCausalDeletionPolicy.retractionEvents(tombstone)
  }

  private func persist() {
    lock.lock()
    persistUnlocked()
    lock.unlock()
  }

  private func persistUnlocked() {
    let items = Self.normalizedItems(currentItemsUnlocked())
    if rows.replace(items) {
      GalaxySSIEncryptedUserDefaultsStore.destroy(
        defaults: defaults,
        key: encryptedKey,
        secrets: secrets
      )
      defaults.removeObject(forKey: key)
    }
  }

  private func publish(_ events: [GlobalConversationEvent]) {
    if !events.isEmpty {
      retractionSink(events)
    }
  }

  private func locked<T>(_ operation: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return operation()
  }
}

final class UserDefaultsAgentPersonalMemoryRows {
  private struct Metadata: Codable {
    var schema: Int
    var orderedIds: [String]
    var activeCount: Int
    var revision: String
  }

  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let prefix: String
  private let metadataKey: String

  init(
    defaults: UserDefaults,
    secrets: GalaxySSISecretStore,
    prefix: String = "galaxyssi_agent_memory_rows_v3"
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.prefix = prefix
    self.metadataKey = "\(prefix)-metadata"
  }

  var exists: Bool {
    GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: metadataKey, secrets: secrets) != nil
  }

  func find(id: String) -> AgentMemoryItem? {
    guard !id.isEmpty,
          let data = GalaxySSIEncryptedUserDefaultsStore.load(
            defaults: defaults,
            key: rowKey(id),
            secrets: secrets
          ), let item = try? JSONDecoder().decode(AgentMemoryItem.self, from: data),
          item.id == id,
          !item.value.agentMemoryTrimmed.isEmpty else { return nil }
    return item
  }

  @discardableResult
  func updateFlags(
    id: String,
    important: Bool? = nil,
    privateMemory: Bool? = nil
  ) -> (before: AgentMemoryItem, after: AgentMemoryItem)? {
    guard important != nil || privateMemory != nil,
          let before = find(id: id),
          before.status == .active else { return nil }
    let after = before.copy(
      important: important ?? before.important,
      privateMemory: privateMemory ?? before.privateMemory
    )
    if before != after {
      guard let data = try? JSONEncoder().encode(after),
            GalaxySSIEncryptedUserDefaultsStore.write(
              data,
              defaults: defaults,
              key: rowKey(id),
              secrets: secrets
            ) else { return nil }
      refreshMetadataRevision()
    }
    return (before, after)
  }

  func read() -> [AgentMemoryItem]? {
    guard let metadataData = GalaxySSIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: metadataKey,
      secrets: secrets
    ), let metadata = try? JSONDecoder().decode(Metadata.self, from: metadataData),
    metadata.schema == 3,
    metadata.activeCount >= 0,
    metadata.activeCount <= metadata.orderedIds.count,
    Set(metadata.orderedIds).count == metadata.orderedIds.count,
    !metadata.revision.isEmpty else { return nil }
    var items: [AgentMemoryItem] = []
    for id in metadata.orderedIds {
      guard let data = GalaxySSIEncryptedUserDefaultsStore.load(
        defaults: defaults,
        key: rowKey(id),
        secrets: secrets
      ), let item = try? JSONDecoder().decode(AgentMemoryItem.self, from: data),
      item.id == id,
      !item.value.agentMemoryTrimmed.isEmpty else { return nil }
      items.append(item)
    }
    guard items.filter({ $0.status == .active }).count == metadata.activeCount else { return nil }
    return items
  }

  @discardableResult
  func replace(_ items: [AgentMemoryItem]) -> Bool {
    guard Set(items.map(\.id)).count == items.count,
          items.allSatisfy({ !$0.id.isEmpty && !$0.value.agentMemoryTrimmed.isEmpty }) else { return false }
    let previousIds = read()?.map(\.id) ?? []
    for item in items {
      guard let data = try? JSONEncoder().encode(item),
            GalaxySSIEncryptedUserDefaultsStore.write(
              data,
              defaults: defaults,
              key: rowKey(item.id),
              secrets: secrets
            ) else { return false }
    }
    let metadata = Metadata(
      schema: 3,
      orderedIds: items.map(\.id),
      activeCount: items.filter { $0.status == .active }.count,
      revision: UUID().uuidString
    )
    guard let data = try? JSONEncoder().encode(metadata),
          GalaxySSIEncryptedUserDefaultsStore.write(
            data,
            defaults: defaults,
            key: metadataKey,
            secrets: secrets
          ) else { return false }
    for id in Set(previousIds).subtracting(items.map(\.id)) {
      GalaxySSIEncryptedUserDefaultsStore.remove(defaults: defaults, key: rowKey(id))
    }
    return true
  }

  func destroy() {
    let ids = read()?.map(\.id) ?? []
    for id in ids {
      GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: rowKey(id), secrets: secrets)
    }
    GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: metadataKey, secrets: secrets)
  }

  private func rowKey(_ id: String) -> String {
    let digest = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    return "\(prefix)-row-\(digest)"
  }

  private func refreshMetadataRevision() {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: metadataKey,
      secrets: secrets
    ), var metadata = try? JSONDecoder().decode(Metadata.self, from: data) else { return }
    metadata.revision = UUID().uuidString
    guard let updated = try? JSONEncoder().encode(metadata) else { return }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(
      updated,
      defaults: defaults,
      key: metadataKey,
      secrets: secrets
    )
  }
}
