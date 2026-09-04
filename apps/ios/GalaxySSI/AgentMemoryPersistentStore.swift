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
    self.deletionIndex = deletionIndex ?? UserDefaultsAgentMemoryDeletionIndex(defaults: defaults)
    self.nowMillis = nowMillis
    self.retractionSink = retractionSink
    let encrypted = GalaxySSIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: encryptedKey,
      secrets: secrets
    )
    let restoredItems = Self.decodeItems(encrypted ?? defaults.data(forKey: key))
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
      let changed = base.setImportant(itemId: itemId, important: important)
      if changed {
        persistUnlocked()
      }
      return changed
    }
  }

  @discardableResult
  func setPrivate(itemId: String, privateMemory: Bool) -> Bool {
    locked {
      let changed = base.setPrivate(itemId: itemId, privateMemory: privateMemory)
      if changed { persistUnlocked() }
      return changed
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
    guard let data = try? AgentMemoryJSONCodec.encodeItems(Self.normalizedItems(currentItemsUnlocked())) else {
      return
    }
    if GalaxySSIEncryptedUserDefaultsStore.write(
      data,
      defaults: defaults,
      key: encryptedKey,
      secrets: secrets
    ) {
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
