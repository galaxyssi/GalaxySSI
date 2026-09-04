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
    self.memoryIds = Self.clean(memoryIds, limit: AgentMemoryCausalDeletionPolicy.maxIdsPerTombstone)
    self.semanticFingerprints = Self.clean(semanticFingerprints, limit: AgentMemoryCausalDeletionPolicy.maxIdsPerTombstone)
    self.retractedEventIds = Self.clean(retractedEventIds, limit: AgentMemoryCausalDeletionPolicy.maxRetractionsPerTombstone)
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
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      memoryIds: Set(try container.decodeIfPresent([String].self, forKey: .memoryIds) ?? []),
      semanticFingerprints: Set(try container.decodeIfPresent([String].self, forKey: .semanticFingerprints) ?? []),
      retractedEventIds: Set(try container.decodeIfPresent([String].self, forKey: .retractedEventIds) ?? []),
      deletedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .deletedAtMillis) ?? 0
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

  private static func clean(_ values: Set<String>, limit: Int) -> Set<String> {
    Set(values
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .sorted()
      .prefix(limit))
  }
}

enum AgentMemoryCausalDeletionPolicy {
  static let maxTombstones = 2_000
  static let maxIdsPerTombstone = 1_000
  static let maxRetractionsPerTombstone = 2_000
  static let maxRetractionsPerEvent = 128

  static func tombstone(
    deletedItems: [AgentMemoryItem],
    deletedAtMillis: Int64 = AgentMemoryClock.nowMillis()
  ) -> AgentMemoryDeletionTombstone? {
    let memoryIds = Set(deletedItems.map(\.id).map(cleanIdentifier).filter { !$0.isEmpty })
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
    return Array(merged.suffix(maxTombstones))
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
    var relatedIds = Set([target.id])
    var changed = true
    while changed {
      changed = false
      for item in items {
        if relatedIds.contains(item.id), !item.supersedesId.isEmpty {
          changed = relatedIds.insert(item.supersedesId).inserted || changed
        }
        if relatedIds.contains(item.supersedesId) {
          changed = relatedIds.insert(item.id).inserted || changed
        }
      }
    }
    return relatedIds
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
    return tombstones.contains { tombstone in
      tombstone.memoryIds.contains(item.id) ||
        (item.timestampMillis <= tombstone.deletedAtMillis &&
          tombstone.semanticFingerprints.contains(fingerprint))
    }
  }

  private static func semanticFingerprint(
    kind: String,
    key: String,
    value: String,
    scope: String,
    scopeId: String
  ) -> String {
    let normalizedKey = normalize(key)
    let semanticIdentity = normalizedKey.isEmpty ? digest(normalize(value)) : normalizedKey
    return digest([
      kind.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
      scope.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
      normalize(scopeId),
      semanticIdentity
    ].joined(separator: "\u{0000}"))
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

  private static func tombstoneId(
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

  private let defaults: UserDefaults
  private let key: String
  private let lock = NSLock()

  init(defaults: UserDefaults = .standard, key: String = UserDefaultsAgentMemoryDeletionIndex.defaultKey) {
    self.defaults = defaults
    self.key = key
  }

  static func destroyPersistentStore(
    defaults: UserDefaults = .standard,
    key: String = UserDefaultsAgentMemoryDeletionIndex.defaultKey
  ) {
    defaults.removeObject(forKey: key)
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
    }
  }

  private func loadUnlocked() -> [AgentMemoryDeletionTombstone] {
    guard let data = defaults.data(forKey: key),
          let decoded = try? JSONDecoder().decode([AgentMemoryDeletionTombstone].self, from: data) else {
      return []
    }
    return AgentMemoryCausalDeletionPolicy.merge(current: [], incoming: decoded)
  }

  private func saveUnlocked(_ tombstones: [AgentMemoryDeletionTombstone]) {
    guard let data = try? JSONEncoder().encode(AgentMemoryCausalDeletionPolicy.merge(current: [], incoming: tombstones)) else {
      return
    }
    defaults.set(data, forKey: key)
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
