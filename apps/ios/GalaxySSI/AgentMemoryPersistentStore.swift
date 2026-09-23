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
      _ = rows.refreshAccess(result)
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

private enum AgentMemorySegmentedRowPayload {
  private struct Manifest: Codable {
    var version: Int
    var generation: String
    var segmentCount: Int
    var plaintextByteCount: Int
    var plaintextSHA256: String
  }

  static let segmentByteCount = 64 * 1024

  static func load(
    defaults: UserDefaults,
    key: String,
    secrets: GalaxySSISecretStore
  ) -> Data? {
    guard let manifest = manifest(defaults: defaults, key: key, secrets: secrets) else {
      return GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets)
    }
    guard manifest.version == 1,
          manifest.segmentCount > 0,
          manifest.segmentCount <= 16_384,
          manifest.plaintextByteCount > segmentByteCount,
          manifest.plaintextByteCount <= manifest.segmentCount * segmentByteCount else { return nil }
    var plaintext = Data()
    plaintext.reserveCapacity(manifest.plaintextByteCount)
    for index in 0..<manifest.segmentCount {
      guard let segment = GalaxySSIEncryptedUserDefaultsStore.load(
        defaults: defaults,
        key: segmentKey(key: key, generation: manifest.generation, index: index),
        keyMaterialKey: key,
        secrets: secrets
      ), !segment.isEmpty,
      segment.count <= segmentByteCount else { return nil }
      plaintext.append(segment)
    }
    guard plaintext.count == manifest.plaintextByteCount,
          Data(SHA256.hash(data: plaintext)).hexString() == manifest.plaintextSHA256 else { return nil }
    return plaintext
  }

  @discardableResult
  static func write(
    _ plaintext: Data,
    defaults: UserDefaults,
    key: String,
    secrets: GalaxySSISecretStore
  ) -> Bool {
    let previous = manifest(defaults: defaults, key: key, secrets: secrets)
    guard plaintext.count > segmentByteCount else {
      guard GalaxySSIEncryptedUserDefaultsStore.write(
        plaintext,
        defaults: defaults,
        key: key,
        secrets: secrets
      ) else { return false }
      removeGeneration(previous, defaults: defaults, key: key)
      GalaxySSIEncryptedUserDefaultsStore.remove(defaults: defaults, key: manifestKey(key))
      return true
    }

    let generation = UUID().uuidString.lowercased()
    let segmentCount = (plaintext.count / segmentByteCount) + (plaintext.count % segmentByteCount == 0 ? 0 : 1)
    for index in 0..<segmentCount {
      let lower = index * segmentByteCount
      let upper = min(lower + segmentByteCount, plaintext.count)
      guard GalaxySSIEncryptedUserDefaultsStore.write(
        plaintext.subdata(in: lower..<upper),
        defaults: defaults,
        key: segmentKey(key: key, generation: generation, index: index),
        keyMaterialKey: key,
        secrets: secrets
      ) else {
        removeGeneration(
          Manifest(version: 1, generation: generation, segmentCount: index, plaintextByteCount: 0, plaintextSHA256: ""),
          defaults: defaults,
          key: key
        )
        return false
      }
    }
    let next = Manifest(
      version: 1,
      generation: generation,
      segmentCount: segmentCount,
      plaintextByteCount: plaintext.count,
      plaintextSHA256: Data(SHA256.hash(data: plaintext)).hexString()
    )
    guard let encoded = try? JSONEncoder().encode(next),
          GalaxySSIEncryptedUserDefaultsStore.write(
            encoded,
            defaults: defaults,
            key: manifestKey(key),
            keyMaterialKey: key,
            secrets: secrets
          ) else {
      removeGeneration(next, defaults: defaults, key: key)
      return false
    }
    GalaxySSIEncryptedUserDefaultsStore.remove(defaults: defaults, key: key)
    removeGeneration(previous, defaults: defaults, key: key)
    return true
  }

  static func destroy(defaults: UserDefaults, key: String, secrets: GalaxySSISecretStore) {
    removeGeneration(manifest(defaults: defaults, key: key, secrets: secrets), defaults: defaults, key: key)
    GalaxySSIEncryptedUserDefaultsStore.remove(defaults: defaults, key: manifestKey(key))
    GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: key, secrets: secrets)
  }

  private static func manifest(
    defaults: UserDefaults,
    key: String,
    secrets: GalaxySSISecretStore
  ) -> Manifest? {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: manifestKey(key),
      keyMaterialKey: key,
      secrets: secrets
    ) else { return nil }
    return try? JSONDecoder().decode(Manifest.self, from: data)
  }

  private static func removeGeneration(_ manifest: Manifest?, defaults: UserDefaults, key: String) {
    guard let manifest, manifest.segmentCount > 0, manifest.segmentCount <= 16_384 else { return }
    for index in 0..<manifest.segmentCount {
      GalaxySSIEncryptedUserDefaultsStore.remove(
        defaults: defaults,
        key: segmentKey(key: key, generation: manifest.generation, index: index)
      )
    }
  }

  private static func manifestKey(_ key: String) -> String {
    "\(key)-segments-v1"
  }

  private static func segmentKey(key: String, generation: String, index: Int) -> String {
    "\(key)-segment-\(generation)-\(index)"
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
          let data = AgentMemorySegmentedRowPayload.load(
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
            AgentMemorySegmentedRowPayload.write(
              data,
              defaults: defaults,
              key: rowKey(id),
              secrets: secrets
            ) else { return nil }
      refreshMetadataRevision()
    }
    return (before, after)
  }

  @discardableResult
  func refreshAccess(_ recalled: [AgentMemoryItem]) -> Int {
    guard !recalled.isEmpty,
          Set(recalled.map(\.id)).count == recalled.count,
          recalled.allSatisfy({ !$0.id.isEmpty }) else { return 0 }
    var changed = 0
    for candidate in recalled {
      guard let before = find(id: candidate.id),
            before.status == .active,
            !before.privateMemory,
            candidate.lastAccessedAtMillis > before.lastAccessedAtMillis else { continue }
      let after = before.copy(lastAccessedAtMillis: candidate.lastAccessedAtMillis)
      guard let data = try? JSONEncoder().encode(after),
            AgentMemorySegmentedRowPayload.write(
              data,
              defaults: defaults,
              key: rowKey(candidate.id),
              secrets: secrets
            ) else { continue }
      changed += 1
    }
    if changed > 0 {
      refreshMetadataRevision()
    }
    return changed
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
      guard let data = AgentMemorySegmentedRowPayload.load(
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
      if find(id: item.id) == item { continue }
      guard let data = try? JSONEncoder().encode(item),
            AgentMemorySegmentedRowPayload.write(
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
      AgentMemorySegmentedRowPayload.destroy(defaults: defaults, key: rowKey(id), secrets: secrets)
    }
    return true
  }

  func destroy() {
    let ids = read()?.map(\.id) ?? []
    for id in ids {
      AgentMemorySegmentedRowPayload.destroy(defaults: defaults, key: rowKey(id), secrets: secrets)
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
