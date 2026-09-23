import CryptoKit
import Foundation

struct AgentMemoryDeletionTombstone: Codable, Equatable, Identifiable {
  var id: String
  var memoryIds: Set<String>
  var semanticFingerprints: Set<String>
  var retractedEventIds: Set<String>
  var deletedAtMillis: Int64

  init(
    id: String,
    memoryIds: Set<String>,
    semanticFingerprints: Set<String>,
    retractedEventIds: Set<String>,
    deletedAtMillis: Int64
  ) {
    self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
    self.memoryIds = Self.clean(memoryIds)
    self.semanticFingerprints = Self.clean(semanticFingerprints)
    self.retractedEventIds = Self.clean(retractedEventIds)
    self.deletedAtMillis = max(deletedAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case memoryIds = "memory_ids"
    case semanticFingerprints = "semantic_fingerprints"
    case retractedEventIds = "retracted_event_ids"
    case deletedAtMillis = "deleted_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let memoryIds = try container.decode([String].self, forKey: .memoryIds)
    let semanticFingerprints = try container.decode([String].self, forKey: .semanticFingerprints)
    let retractedEventIds = try container.decode([String].self, forKey: .retractedEventIds)
    guard Set(memoryIds).count == memoryIds.count,
          Set(semanticFingerprints).count == semanticFingerprints.count,
          Set(retractedEventIds).count == retractedEventIds.count else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Deletion ledger sets contain duplicate entries")
      )
    }
    self.init(
      id: try container.decode(String.self, forKey: .id),
      memoryIds: Set(memoryIds),
      semanticFingerprints: Set(semanticFingerprints),
      retractedEventIds: Set(retractedEventIds),
      deletedAtMillis: try container.decode(Int64.self, forKey: .deletedAtMillis)
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(memoryIds.sorted(), forKey: .memoryIds)
    try container.encode(semanticFingerprints.sorted(), forKey: .semanticFingerprints)
    try container.encode(retractedEventIds.sorted(), forKey: .retractedEventIds)
    try container.encode(deletedAtMillis, forKey: .deletedAtMillis)
  }

  private static func clean(_ values: Set<String>) -> Set<String> {
    Set(values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
  }
}

enum AgentMemoryCausalDeletionPolicy {
  static let maxRetractionsPerEvent = 128

  static func tombstone(
    deletedItems: [AgentMemoryItem],
    deletedAtMillis: Int64 = AgentMemoryClock.nowMillis()
  ) -> AgentMemoryDeletionTombstone? {
    let memoryIds = Set(deletedItems.map(\.id).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    let fingerprints = Set(deletedItems.map(semanticFingerprint).filter { !$0.isEmpty })
    let retractions = Set(deletedItems.flatMap { retractionEventIds(for: $0) }.filter { !$0.isEmpty })
    guard !memoryIds.isEmpty || !fingerprints.isEmpty || !retractions.isEmpty else { return nil }
    let id = tombstoneId(
      memoryIds: memoryIds,
      semanticFingerprints: fingerprints,
      retractedEventIds: retractions,
      deletedAtMillis: deletedAtMillis
    )
    return AgentMemoryDeletionTombstone(
      id: id,
      memoryIds: memoryIds,
      semanticFingerprints: fingerprints,
      retractedEventIds: retractions,
      deletedAtMillis: deletedAtMillis
    )
  }

  static func merge(
    current: [AgentMemoryDeletionTombstone],
    incoming: [AgentMemoryDeletionTombstone]
  ) -> [AgentMemoryDeletionTombstone] {
    let merged = (current + incoming)
      .compactMap(validated)
      .reduce(into: [String: AgentMemoryDeletionTombstone]()) { result, tombstone in
        result[tombstone.id] = tombstone
      }
      .values
      .sorted { $0.deletedAtMillis < $1.deletedAtMillis }
    return Array(merged)
  }

  static func filterRestoredItems(
    _ items: [AgentMemoryItem],
    tombstones: [AgentMemoryDeletionTombstone]
  ) -> [AgentMemoryItem] {
    let validTombstones = merge(current: [], incoming: tombstones)
    return items.filter { !isSuppressed($0, by: validTombstones) }
  }

  static func filterBackupItems(
    _ items: [AgentMemoryItem],
    tombstones: [AgentMemoryDeletionTombstone]
  ) -> [AgentMemoryItem] {
    filterRestoredItems(items, tombstones: tombstones)
  }

  static func retractionEvents(_ tombstone: AgentMemoryDeletionTombstone) -> [GlobalConversationEvent] {
    tombstone.retractedEventIds.sorted()
      .chunked(maxRetractionsPerEvent)
      .enumerated()
      .map { index, ids in
        GlobalConversationEvent(
          id: "memory-causal-deletion:\(tombstone.id):\(index)",
          type: .memoryDeleted,
          conversationId: "global-memory",
          messageId: tombstone.id,
          actor: .system,
          timestampMillis: tombstone.deletedAtMillis,
          content: "",
          contentRef: "encrypted://agent-memory-deletion/\(tombstone.id)",
          conversationTitle: "Personal memory",
          metadata: [
            "origin": "agent_memory_causal_deletion",
            "deletion_id": tombstone.id,
            "deletion_chunk": String(index),
            "projection": "retract_only"
          ],
          retractedEventIds: Set(ids)
        )
      }
  }

  static func semanticFingerprint(_ item: AgentMemoryItem) -> String {
    semanticFingerprint(
      kind: item.kind.rawValue,
      key: item.key,
      value: item.value,
      scope: item.scope.rawValue,
      scopeId: item.scopeId
    )
  }

  static func lineageIds(in items: [AgentMemoryItem], target: AgentMemoryItem) -> Set<String> {
    AgentMemoryIdentity.lineageIds(in: items, target: target)
  }

  static func items(in snapshot: AgentMemorySnapshot) -> [AgentMemoryItem] {
    var byId: [String: AgentMemoryItem] = [:]
    for item in snapshot.activeItems + snapshot.historyItems {
      byId[item.id] = item
    }
    for item in snapshot.conflicts.flatMap(\.candidates) {
      byId[item.id] = item
    }
    return byId.values.sorted { $0.timestampMillis < $1.timestampMillis }
  }

  private static func validated(_ tombstone: AgentMemoryDeletionTombstone) -> AgentMemoryDeletionTombstone? {
    guard !tombstone.id.isEmpty, tombstone.deletedAtMillis > 0 else { return nil }
    let normalized = AgentMemoryDeletionTombstone(
      id: tombstone.id,
      memoryIds: tombstone.memoryIds,
      semanticFingerprints: tombstone.semanticFingerprints,
      retractedEventIds: tombstone.retractedEventIds,
      deletedAtMillis: tombstone.deletedAtMillis
    )
    let expected = tombstoneId(
      memoryIds: normalized.memoryIds,
      semanticFingerprints: normalized.semanticFingerprints,
      retractedEventIds: normalized.retractedEventIds,
      deletedAtMillis: normalized.deletedAtMillis
    )
    return normalized.id == expected ? normalized : nil
  }

  private static func isSuppressed(
    _ item: AgentMemoryItem,
    by tombstones: [AgentMemoryDeletionTombstone]
  ) -> Bool {
    let fingerprint = semanticFingerprint(item)
    let legacyFingerprint = semanticFingerprint(
      kind: item.kind.rawValue,
      key: item.key,
      value: item.value,
      scope: item.scope.rawValue,
      scopeId: item.scopeId,
      legacyScope: true
    )
    return tombstones.contains { tombstone in
      tombstone.memoryIds.contains(item.id) ||
        (item.timestampMillis <= tombstone.deletedAtMillis &&
          (tombstone.semanticFingerprints.contains(fingerprint) ||
            tombstone.semanticFingerprints.contains(legacyFingerprint)))
    }
  }

  static func semanticFingerprint(
    kind: String,
    key: String,
    value: String,
    scope: String,
    scopeId: String,
    legacyScope: Bool = false
  ) -> String {
    let normalizedKey = normalize(key)
    let semanticIdentity = normalizedKey.isEmpty ? digest(normalize(value)) : normalizedKey
    let fields = [
      kind.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
      scope.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
      legacyScope ? normalize(scopeId) : scopeId,
      semanticIdentity
    ]
    if legacyScope {
      return digest(fields.joined(separator: "\u{0000}"))
    }
    let encoded = fields.map { "\($0.utf8.count):\($0)" }.joined()
    return "scope-v2:\(digest(encoded))"
  }

  private static func retractionEventIds(for item: AgentMemoryItem) -> Set<String> {
    var ids = Set<String>()
    let itemId = cleanIdentifier(item.id)
    if !itemId.isEmpty {
      ids.insert("memory-root:\(itemId)")
    }
    let supersedesId = cleanIdentifier(item.supersedesId)
    if !supersedesId.isEmpty {
      ids.insert("memory-root:\(supersedesId)")
    }
    return ids
  }

  static func tombstoneId(
    memoryIds: Set<String>,
    semanticFingerprints: Set<String>,
    retractedEventIds: Set<String>,
    deletedAtMillis: Int64
  ) -> String {
    digest([
      "memory-causal-deletion",
      String(deletedAtMillis),
      memoryIds.sorted().joined(separator: "|"),
      semanticFingerprints.sorted().joined(separator: "|"),
      retractedEventIds.sorted().joined(separator: "|")
    ].joined(separator: "\u{0000}"))
  }

  private static func normalize(_ value: String) -> String {
    value.lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func cleanIdentifier(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

protocol AgentMemoryDeletionIndex: AnyObject {
  @discardableResult func record(
    deletedItems: [AgentMemoryItem],
    deletedAtMillis: Int64
  ) -> AgentMemoryDeletionTombstone?
  func snapshot() -> [AgentMemoryDeletionTombstone]
  @discardableResult func mergeBackup(_ tombstones: [AgentMemoryDeletionTombstone]?) -> [AgentMemoryDeletionTombstone]
  func exportTombstones() -> [AgentMemoryDeletionTombstone]
  func filterBackupItems(_ items: [AgentMemoryItem]) -> [AgentMemoryItem]
  func clear()
}

extension AgentMemoryDeletionIndex {
  @discardableResult
  func record(deletedItems: [AgentMemoryItem]) -> AgentMemoryDeletionTombstone? {
    record(deletedItems: deletedItems, deletedAtMillis: AgentMemoryClock.nowMillis())
  }
}

final class InMemoryAgentMemoryDeletionIndex: AgentMemoryDeletionIndex {
  private let lock = NSLock()
  private var tombstones: [AgentMemoryDeletionTombstone]

  init(tombstones: [AgentMemoryDeletionTombstone] = []) {
    self.tombstones = AgentMemoryCausalDeletionPolicy.merge(current: [], incoming: tombstones)
  }

  @discardableResult
  func record(
    deletedItems: [AgentMemoryItem],
    deletedAtMillis: Int64 = AgentMemoryClock.nowMillis()
  ) -> AgentMemoryDeletionTombstone? {
    guard let tombstone = AgentMemoryCausalDeletionPolicy.tombstone(
      deletedItems: deletedItems,
      deletedAtMillis: deletedAtMillis
    ) else { return nil }
    lock.lock()
    tombstones = AgentMemoryCausalDeletionPolicy.merge(current: tombstones, incoming: [tombstone])
    lock.unlock()
    return tombstone
  }

  func snapshot() -> [AgentMemoryDeletionTombstone] {
    lock.lock()
    defer { lock.unlock() }
    return tombstones
  }

  @discardableResult
  func mergeBackup(_ tombstones: [AgentMemoryDeletionTombstone]?) -> [AgentMemoryDeletionTombstone] {
    lock.lock()
    defer { lock.unlock() }
    self.tombstones = AgentMemoryCausalDeletionPolicy.merge(
      current: self.tombstones,
      incoming: tombstones ?? []
    )
    return self.tombstones
  }

  func exportTombstones() -> [AgentMemoryDeletionTombstone] {
    snapshot()
  }

  func filterBackupItems(_ items: [AgentMemoryItem]) -> [AgentMemoryItem] {
    AgentMemoryCausalDeletionPolicy.filterBackupItems(items, tombstones: snapshot())
  }

  func clear() {
    lock.lock()
    tombstones.removeAll()
    lock.unlock()
  }
}

final class UserDefaultsAgentMemoryDeletionIndex: AgentMemoryDeletionIndex {
  static let defaultKey = "galaxyssi_agent_memory_deletions_v1"
  static let encryptedKey = "galaxyssi_agent_memory_deletions_v2"

  private let defaults: UserDefaults
  private let key: String
  private let encryptedStorageKey: String
  private let outboxStorageKey: String
  private let secrets: GalaxySSISecretStore
  private let lock = NSLock()

  init(
    defaults: UserDefaults = .standard,
    key: String = UserDefaultsAgentMemoryDeletionIndex.defaultKey,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  ) {
    self.defaults = defaults
    self.key = key
    let resolvedEncryptedKey = key == Self.defaultKey ? Self.encryptedKey : "\(key)-encrypted-v2"
    self.encryptedStorageKey = resolvedEncryptedKey
    self.outboxStorageKey = "\(resolvedEncryptedKey)-retraction-outbox-v1"
    self.secrets = secrets
    migrateLegacyIfNeeded()
  }

  static func destroyPersistentStore(
    defaults: UserDefaults = .standard,
    key: String = UserDefaultsAgentMemoryDeletionIndex.defaultKey,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  ) {
    defaults.removeObject(forKey: key)
    GalaxySSIEncryptedUserDefaultsStore.destroy(
      defaults: defaults,
      key: key == defaultKey ? encryptedKey : "\(key)-encrypted-v2",
      secrets: secrets
    )
    let encryptedStorageKey = key == defaultKey ? encryptedKey : "\(key)-encrypted-v2"
    GalaxySSIEncryptedUserDefaultsStore.destroy(
      defaults: defaults,
      key: "\(encryptedStorageKey)-retraction-outbox-v1",
      secrets: secrets
    )
  }

  @discardableResult
  func record(
    deletedItems: [AgentMemoryItem],
    deletedAtMillis: Int64 = AgentMemoryClock.nowMillis()
  ) -> AgentMemoryDeletionTombstone? {
    guard let tombstone = AgentMemoryCausalDeletionPolicy.tombstone(
      deletedItems: deletedItems,
      deletedAtMillis: deletedAtMillis
    ) else { return nil }
    locked {
      saveUnlocked(AgentMemoryCausalDeletionPolicy.merge(current: loadUnlocked(), incoming: [tombstone]))
      enqueueRetractionsUnlocked(for: [tombstone])
    }
    return tombstone
  }

  func snapshot() -> [AgentMemoryDeletionTombstone] {
    locked { loadUnlocked() }
  }

  @discardableResult
  func mergeBackup(_ tombstones: [AgentMemoryDeletionTombstone]?) -> [AgentMemoryDeletionTombstone] {
    locked {
      let merged = AgentMemoryCausalDeletionPolicy.merge(current: loadUnlocked(), incoming: tombstones ?? [])
      saveUnlocked(merged)
      enqueueRetractionsUnlocked(for: tombstones ?? [])
      return merged
    }
  }

  func exportTombstones() -> [AgentMemoryDeletionTombstone] {
    snapshot()
  }

  func filterBackupItems(_ items: [AgentMemoryItem]) -> [AgentMemoryItem] {
    AgentMemoryCausalDeletionPolicy.filterBackupItems(items, tombstones: snapshot())
  }

  func clear() {
    locked {
      defaults.removeObject(forKey: key)
      GalaxySSIEncryptedUserDefaultsStore.destroy(
        defaults: defaults,
        key: encryptedStorageKey,
        secrets: secrets
      )
      GalaxySSIEncryptedUserDefaultsStore.destroy(
        defaults: defaults,
        key: outboxStorageKey,
        secrets: secrets
      )
    }
  }

  private func loadUnlocked() -> [AgentMemoryDeletionTombstone] {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: encryptedStorageKey,
      secrets: secrets
    ),
          let decoded = try? JSONDecoder().decode([AgentMemoryDeletionTombstone].self, from: data) else {
      return []
    }
    return AgentMemoryCausalDeletionPolicy.merge(current: [], incoming: decoded)
  }

  private func saveUnlocked(_ tombstones: [AgentMemoryDeletionTombstone]) {
    guard let data = try? JSONEncoder().encode(AgentMemoryCausalDeletionPolicy.merge(current: [], incoming: tombstones)) else {
      return
    }
    if GalaxySSIEncryptedUserDefaultsStore.write(
      data,
      defaults: defaults,
      key: encryptedStorageKey,
      secrets: secrets
    ) {
      defaults.removeObject(forKey: key)
    }
  }

  private func migrateLegacyIfNeeded() {
    lock.lock()
    defer { lock.unlock() }
    guard GalaxySSIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: encryptedStorageKey,
      secrets: secrets
    ) == nil,
    let legacyData = defaults.data(forKey: key),
    let decoded = try? JSONDecoder().decode([AgentMemoryDeletionTombstone].self, from: legacyData) else {
      return
    }
    saveUnlocked(decoded)
  }

  func pendingRetractions(limit: Int = 100) -> [GlobalConversationEvent] {
    locked {
      bootstrapOutboxUnlocked()
      return Array(loadOutboxUnlocked().events.prefix(min(max(limit, 1), 250)))
    }
  }

  func pendingRetractionCount() -> Int {
    locked {
      bootstrapOutboxUnlocked()
      return loadOutboxUnlocked().events.count
    }
  }

  func acknowledgeRetractions(eventIds: Set<String>) {
    guard !eventIds.isEmpty else { return }
    locked {
      var state = loadOutboxUnlocked()
      state.events.removeAll { eventIds.contains($0.id) }
      saveOutboxUnlocked(state)
    }
  }

  @discardableResult
  func requeueAllRetractions() -> Int {
    locked {
      var state = loadOutboxUnlocked()
      state.ready = true
      state.events = mergeRetractionEvents(
        existing: state.events,
        incoming: loadUnlocked().flatMap(AgentMemoryCausalDeletionPolicy.retractionEvents)
      )
      saveOutboxUnlocked(state)
      return state.events.count
    }
  }

  private struct RetractionOutboxState: Codable {
    var ready: Bool = false
    var events: [GlobalConversationEvent] = []
  }

  private func bootstrapOutboxUnlocked() {
    var state = loadOutboxUnlocked()
    guard !state.ready else { return }
    state.ready = true
    state.events = mergeRetractionEvents(
      existing: state.events,
      incoming: loadUnlocked().flatMap(AgentMemoryCausalDeletionPolicy.retractionEvents)
    )
    saveOutboxUnlocked(state)
  }

  private func enqueueRetractionsUnlocked(for tombstones: [AgentMemoryDeletionTombstone]) {
    var state = loadOutboxUnlocked()
    state.ready = true
    state.events = mergeRetractionEvents(
      existing: state.events,
      incoming: tombstones.flatMap(AgentMemoryCausalDeletionPolicy.retractionEvents)
    )
    saveOutboxUnlocked(state)
  }

  private func mergeRetractionEvents(
    existing: [GlobalConversationEvent],
    incoming: [GlobalConversationEvent]
  ) -> [GlobalConversationEvent] {
    var known = Set<String>()
    return (existing + incoming).filter { !$0.id.isEmpty && known.insert($0.id).inserted }
  }

  private func loadOutboxUnlocked() -> RetractionOutboxState {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: outboxStorageKey,
      secrets: secrets
    ), let state = try? JSONDecoder().decode(RetractionOutboxState.self, from: data) else {
      return RetractionOutboxState()
    }
    return state
  }

  private func saveOutboxUnlocked(_ state: RetractionOutboxState) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(
      data,
      defaults: defaults,
      key: outboxStorageKey,
      secrets: secrets
    )
  }

  private func locked<T>(_ operation: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return operation()
  }
}

final class AgentMemoryDeletionRecordingStore: AgentMemoryStore {
  private let base: AgentMemoryStore
  private let deletionIndex: AgentMemoryDeletionIndex
  private let nowMillis: () -> Int64
  private let retractionSink: ([GlobalConversationEvent]) -> Void

  init(
    base: AgentMemoryStore,
    deletionIndex: AgentMemoryDeletionIndex,
    nowMillis: @escaping () -> Int64 = AgentMemoryClock.nowMillis,
    retractionSink: @escaping ([GlobalConversationEvent]) -> Void = { _ in }
  ) {
    self.base = base
    self.deletionIndex = deletionIndex
    self.nowMillis = nowMillis
    self.retractionSink = retractionSink
  }

  @discardableResult
  func remember(_ item: AgentMemoryItem) -> AgentMemoryWriteResult {
    base.remember(item)
  }

  func recall(query: String) -> [AgentMemoryItem] {
    base.recall(query: query)
  }

  func recent(limit: Int) -> [AgentMemoryItem] {
    base.recent(limit: limit)
  }

  func count() -> Int {
    base.count()
  }

  @discardableResult
  func rebindConversationScope(sourceConversationId: String, targetConversationId: String) -> Int {
    base.rebindConversationScope(
      sourceConversationId: sourceConversationId,
      targetConversationId: targetConversationId
    )
  }

  @discardableResult
  func delete(query: String) -> Int {
    let before = AgentMemoryCausalDeletionPolicy.items(in: base.snapshot())
    let deletedAtMillis = nowMillis()
    let deletedCount = base.delete(query: query)
    guard deletedCount > 0 else { return 0 }
    recordDeletedItems(before: before, after: AgentMemoryCausalDeletionPolicy.items(in: base.snapshot()), deletedAtMillis: deletedAtMillis)
    return deletedCount
  }

  func snapshot() -> AgentMemorySnapshot {
    base.snapshot()
  }

  @discardableResult
  func update(itemId: String, value: String, key: String) -> AgentMemoryWriteResult? {
    base.update(itemId: itemId, value: value, key: key)
  }

  @discardableResult
  func deleteById(_ itemId: String) -> Bool {
    let before = AgentMemoryCausalDeletionPolicy.items(in: base.snapshot())
    let deletedAtMillis = nowMillis()
    guard base.deleteById(itemId) else { return false }
    recordDeletedItems(before: before, after: AgentMemoryCausalDeletionPolicy.items(in: base.snapshot()), deletedAtMillis: deletedAtMillis)
    return true
  }

  @discardableResult
  func setImportant(itemId: String, important: Bool) -> Bool {
    base.setImportant(itemId: itemId, important: important)
  }

  @discardableResult
  func setPrivate(itemId: String, privateMemory: Bool) -> Bool {
    base.setPrivate(itemId: itemId, privateMemory: privateMemory)
  }

  @discardableResult
  func deprecate(itemId: String) -> Bool {
    base.deprecate(itemId: itemId)
  }

  @discardableResult
  func resolveConflict(groupId: String, selectedItemId: String, mergedValue: String?) -> AgentMemoryItem? {
    base.resolveConflict(groupId: groupId, selectedItemId: selectedItemId, mergedValue: mergedValue)
  }

  private func recordDeletedItems(
    before: [AgentMemoryItem],
    after: [AgentMemoryItem],
    deletedAtMillis: Int64
  ) {
    let remainingIds = Set(after.map(\.id))
    let deletedItems = before.filter { !remainingIds.contains($0.id) }
    guard let tombstone = deletionIndex.record(deletedItems: deletedItems, deletedAtMillis: deletedAtMillis) else {
      return
    }
    retractionSink(AgentMemoryCausalDeletionPolicy.retractionEvents(tombstone))
  }
}

private extension Array {
  func chunked(_ size: Int) -> [[Element]] {
    guard size > 0, !isEmpty else { return [] }
    return stride(from: 0, to: count, by: size).map { start in
      Array(self[start..<Swift.min(start + size, count)])
    }
  }
}
