import Foundation

enum AgentMemoryKind: String, Codable, CaseIterable, Identifiable {
  case identity = "IDENTITY"
  case contact = "CONTACT"
  case task = "TASK"
  case preference = "PREFERENCE"
  case workflow = "WORKFLOW"
  case knowledge = "KNOWLEDGE"
  case safety = "SAFETY"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentMemoryKind {
    let normalized = AgentMemoryWire.token(value)
    return AgentMemoryKind(rawValue: normalized) ?? .knowledge
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = AgentMemoryKind.fromWireValue(try? container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentMemoryScope: String, Codable, CaseIterable, Identifiable {
  case global = "GLOBAL"
  case conversation = "CONVERSATION"
  case application = "APPLICATION"
  case contact = "CONTACT"
  case workspace = "WORKSPACE"
  case device = "DEVICE"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentMemoryScope {
    let normalized = AgentMemoryWire.token(value)
    return AgentMemoryScope(rawValue: normalized) ?? .global
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = AgentMemoryScope.fromWireValue(try? container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentMemoryStatus: String, Codable, CaseIterable, Identifiable {
  case active = "ACTIVE"
  case conflicted = "CONFLICTED"
  case superseded = "SUPERSEDED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentMemoryStatus {
    let normalized = AgentMemoryWire.token(value)
    return AgentMemoryStatus(rawValue: normalized) ?? .active
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = AgentMemoryStatus.fromWireValue(try? container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentMemoryItem: Codable, Equatable, Identifiable {
  var kind: AgentMemoryKind
  var value: String
  var timestampMillis: Int64
  var id: String
  var source: String
  var key: String
  var version: Int
  var supersedesId: String
  var important: Bool
  var status: AgentMemoryStatus
  var conflictGroupId: String
  var scope: AgentMemoryScope
  var scopeId: String
  var confidence: Double
  var evidenceCount: Int
  var autoLearned: Bool
  var lastConfirmedAtMillis: Int64
  var lastAccessedAtMillis: Int64
  var expiresAtMillis: Int64
  var whyRemembered: String
  var originConversationId: String
  var originEventId: String
  var privateMemory: Bool

  enum CodingKeys: String, CodingKey {
    case id
    case kind
    case value
    case key
    case source
    case timestampMillis = "timestamp_millis"
    case version
    case supersedesId = "supersedes_id"
    case important
    case status
    case conflictGroupId = "conflict_group_id"
    case scope
    case scopeId = "scope_id"
    case confidence
    case evidenceCount = "evidence_count"
    case autoLearned = "auto_learned"
    case lastConfirmedAtMillis = "last_confirmed_at_millis"
    case lastAccessedAtMillis = "last_accessed_at_millis"
    case expiresAtMillis = "expires_at_millis"
    case whyRemembered = "why_remembered"
    case originConversationId = "origin_conversation_id"
    case originEventId = "origin_event_id"
    case privateMemory = "private_memory"
  }

  init(
    kind: AgentMemoryKind,
    value: String,
    timestampMillis: Int64 = AgentMemoryClock.nowMillis(),
    id: String = UUID().uuidString,
    source: String = "agent",
    key: String = "",
    version: Int = 1,
    supersedesId: String = "",
    important: Bool = false,
    status: AgentMemoryStatus = .active,
    conflictGroupId: String = "",
    scope: AgentMemoryScope = .global,
    scopeId: String = "",
    confidence: Double = 0.65,
    evidenceCount: Int = 1,
    autoLearned: Bool = false,
    lastConfirmedAtMillis: Int64 = 0,
    lastAccessedAtMillis: Int64 = 0,
    expiresAtMillis: Int64 = 0,
    whyRemembered: String = "",
    originConversationId: String = "",
    originEventId: String = "",
    privateMemory: Bool = false
  ) {
    self.kind = kind
    self.value = value
    self.timestampMillis = timestampMillis
    self.id = id
    self.source = source
    self.key = key
    self.version = max(version, 1)
    self.supersedesId = supersedesId
    self.important = important
    self.status = status
    self.conflictGroupId = conflictGroupId
    self.scope = scope
    self.scopeId = scopeId
    self.confidence = min(max(confidence, 0), 1)
    self.evidenceCount = min(max(evidenceCount, 1), AgentMemoryPolicy.maxEvidenceCount)
    self.autoLearned = autoLearned
    self.lastConfirmedAtMillis = max(lastConfirmedAtMillis, 0)
    self.lastAccessedAtMillis = max(lastAccessedAtMillis, 0)
    self.expiresAtMillis = max(expiresAtMillis, 0)
    self.whyRemembered = String(whyRemembered.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000))
    self.originConversationId = String(originConversationId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
    self.originEventId = String(originEventId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
    self.privateMemory = privateMemory
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      kind: try container.decodeIfPresent(AgentMemoryKind.self, forKey: .kind) ?? .task,
      value: (try container.decodeIfPresent(String.self, forKey: .value) ?? "").agentMemoryTrimmed,
      timestampMillis: max(try container.decodeIfPresent(Int64.self, forKey: .timestampMillis) ?? AgentMemoryClock.nowMillis(), 0),
      id: (try container.decodeIfPresent(String.self, forKey: .id) ?? "").agentMemoryNonBlankOr(UUID().uuidString),
      source: try container.decodeIfPresent(String.self, forKey: .source) ?? "agent",
      key: AgentMemoryKeyPolicy.normalize(try container.decodeIfPresent(String.self, forKey: .key) ?? ""),
      version: try container.decodeIfPresent(Int.self, forKey: .version) ?? 1,
      supersedesId: try container.decodeIfPresent(String.self, forKey: .supersedesId) ?? "",
      important: try container.decodeIfPresent(Bool.self, forKey: .important) ?? false,
      status: try container.decodeIfPresent(AgentMemoryStatus.self, forKey: .status) ?? .active,
      conflictGroupId: try container.decodeIfPresent(String.self, forKey: .conflictGroupId) ?? "",
      scope: try container.decodeIfPresent(AgentMemoryScope.self, forKey: .scope) ?? .global,
      scopeId: try container.decodeIfPresent(String.self, forKey: .scopeId) ?? "",
      confidence: try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.65,
      evidenceCount: try container.decodeIfPresent(Int.self, forKey: .evidenceCount) ?? 1,
      autoLearned: try container.decodeIfPresent(Bool.self, forKey: .autoLearned) ?? false,
      lastConfirmedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .lastConfirmedAtMillis) ?? 0,
      lastAccessedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .lastAccessedAtMillis) ?? 0,
      expiresAtMillis: try container.decodeIfPresent(Int64.self, forKey: .expiresAtMillis) ?? 0,
      whyRemembered: try container.decodeIfPresent(String.self, forKey: .whyRemembered) ?? "",
      originConversationId: try container.decodeIfPresent(String.self, forKey: .originConversationId) ?? "",
      originEventId: try container.decodeIfPresent(String.self, forKey: .originEventId) ?? "",
      privateMemory: try container.decodeIfPresent(Bool.self, forKey: .privateMemory) ?? false
    )
  }

  func isExpired(nowMillis: Int64 = AgentMemoryClock.nowMillis()) -> Bool {
    expiresAtMillis > 0 && expiresAtMillis <= nowMillis
  }
}

struct AgentMemoryWriteResult: Equatable {
  var item: AgentMemoryItem?
  var conflict: AgentMemoryConflict?
  var duplicate: Bool

  init(
    item: AgentMemoryItem?,
    conflict: AgentMemoryConflict? = nil,
    duplicate: Bool = false
  ) {
    self.item = item
    self.conflict = conflict
    self.duplicate = duplicate
  }
}

struct AgentMemoryConflict: Codable, Equatable, Identifiable {
  var groupId: String
  var kind: AgentMemoryKind
  var key: String
  var candidates: [AgentMemoryItem]

  var id: String { groupId }

  enum CodingKeys: String, CodingKey {
    case groupId = "group_id"
    case kind
    case key
    case candidates
  }
}

struct AgentMemorySnapshot: Codable, Equatable {
  var activeItems: [AgentMemoryItem]
  var conflicts: [AgentMemoryConflict]
  var historyItems: [AgentMemoryItem]

  enum CodingKeys: String, CodingKey {
    case activeItems = "active_items"
    case conflicts
    case historyItems = "history_items"
  }

  init(
    activeItems: [AgentMemoryItem] = [],
    conflicts: [AgentMemoryConflict] = [],
    historyItems: [AgentMemoryItem] = []
  ) {
    self.activeItems = activeItems
    self.conflicts = conflicts
    self.historyItems = historyItems
  }

  var activeCount: Int { activeItems.count }
  var historyCount: Int { historyItems.count }
}

enum AgentMemoryIdentity {
  private struct Key: Hashable {
    var kind: AgentMemoryKind
    var scope: AgentMemoryScope
    var scopeId: String
    var key: String
  }

  static func sameNamespace(_ first: AgentMemoryItem, _ second: AgentMemoryItem) -> Bool {
    first.kind == second.kind && first.scope == second.scope && first.scopeId == second.scopeId
  }

  static func sameKey(_ first: AgentMemoryItem, _ second: AgentMemoryItem) -> Bool {
    sameNamespace(first, second) && first.key == second.key
  }

  static func normalizeConflicts(_ items: [AgentMemoryItem]) -> [AgentMemoryItem] {
    var replacements: [String: AgentMemoryItem] = [:]
    let groups = Dictionary(grouping: items.filter { $0.status == .conflicted }, by: \.conflictGroupId)
    for (groupId, group) in groups {
      let partitions = Dictionary(grouping: group) {
        Key(kind: $0.kind, scope: $0.scope, scopeId: $0.scopeId, key: $0.key)
      }
      for candidates in partitions.values {
        if candidates.count == 1, let item = candidates.first {
          replacements[item.id] = item.copy(status: .active, conflictGroupId: "")
        } else if partitions.count > 1 || groupId.isEmpty {
          let scopedGroupId = UUID().uuidString
          for item in candidates {
            replacements[item.id] = item.copy(conflictGroupId: scopedGroupId)
          }
        }
      }
    }
    guard !replacements.isEmpty else { return items }
    return items.map { replacements[$0.id] ?? $0 }
  }

  static func conflictCandidates(
    in items: [AgentMemoryItem],
    groupId: String,
    selectedItemId: String
  ) -> [AgentMemoryItem] {
    guard let selected = items.first(where: {
      $0.id == selectedItemId && $0.conflictGroupId == groupId && $0.status == .conflicted
    }) else { return [] }
    return items.filter {
      $0.conflictGroupId == groupId && $0.status == .conflicted && sameKey($0, selected)
    }
  }

  static func lineageIds(in items: [AgentMemoryItem], target: AgentMemoryItem) -> Set<String> {
    let scoped = items
      .filter { sameNamespace($0, target) }
      .reduce(into: [String: AgentMemoryItem]()) { $0[$1.id] = $1 }
    let children = Dictionary(grouping: scoped.values, by: \.supersedesId)
    var pending = [target.id]
    var visited = Set<String>()
    while let id = pending.popLast() {
      guard visited.insert(id).inserted, let item = scoped[id] else { continue }
      if scoped[item.supersedesId] != nil {
        pending.append(item.supersedesId)
      }
      pending.append(contentsOf: (children[id] ?? []).map(\.id))
    }
    return visited
  }
}

enum AgentMemorySection: String, Codable {
  case active
  case conflicts
  case history
}

struct AgentMemoryBrowseCounts: Equatable {
  var active: Int
  var conflicts: Int
  var history: Int
}

struct AgentMemoryBrowseCursor: Equatable {
  var position: Int
  var itemId: String
  var revision: String
  var scope: String
}

struct AgentMemoryBrowseRequest {
  var section: AgentMemorySection = .active
  var kinds: Set<AgentMemoryKind> = []
  var cursor: AgentMemoryBrowseCursor?
  var limit: Int = 25
  var publicOnly: Bool = false
  var nowMillis: Int64 = 0
  var backwards: Bool = false
}

struct AgentMemoryBrowseEntry: Equatable {
  var item: AgentMemoryItem
  var conflictSize: Int = 0
}

struct AgentMemoryBrowsePage: Equatable {
  var entries: [AgentMemoryBrowseEntry]
  var counts: AgentMemoryBrowseCounts
  var next: AgentMemoryBrowseCursor?
  var previous: AgentMemoryBrowseCursor?
}

enum AgentMemoryBrowseError: Error, Equatable {
  case invalidRequest
  case pageChanged
}

extension AgentMemorySnapshot {
  func browse(_ request: AgentMemoryBrowseRequest) throws -> AgentMemoryBrowsePage {
    guard (1...100).contains(request.limit),
          !request.publicOnly || request.section == .active,
          !request.backwards || request.cursor != nil else { throw AgentMemoryBrowseError.invalidRequest }
    let includes: (AgentMemoryItem) -> Bool = { request.kinds.isEmpty || request.kinds.contains($0.kind) }
    let active = activeItems.filter(includes)
    let groups = conflicts.filter { request.kinds.isEmpty || request.kinds.contains($0.kind) }
    let history = historyItems.filter(includes)
    let entries: [AgentMemoryBrowseEntry]
    switch request.section {
    case .active:
      entries = active
        .filter { !request.publicOnly || (!$0.privateMemory && !$0.isExpired(nowMillis: request.nowMillis)) }
        .sorted {
          if $0.important != $1.important { return $0.important && !$1.important }
          if $0.timestampMillis != $1.timestampMillis { return $0.timestampMillis > $1.timestampMillis }
          return $0.id < $1.id
        }
        .map { AgentMemoryBrowseEntry(item: $0) }
    case .conflicts:
      entries = groups.compactMap { group in
        group.candidates.max(by: { $0.timestampMillis < $1.timestampMillis }).map {
          AgentMemoryBrowseEntry(item: $0, conflictSize: group.candidates.count)
        }
      }.sorted { $0.item.timestampMillis > $1.item.timestampMillis }
    case .history:
      entries = history.sorted {
        if $0.timestampMillis != $1.timestampMillis { return $0.timestampMillis > $1.timestampMillis }
        return $0.id < $1.id
      }.map { AgentMemoryBrowseEntry(item: $0) }
    }
    let revision = (activeItems + historyItems + conflicts.flatMap(\.candidates))
      .map { "\($0.id):\($0.status.rawValue):\($0.timestampMillis)" }
      .joined(separator: "|")
    let scope = "\(request.section.rawValue):\(request.kinds.map(\.rawValue).sorted().joined(separator: ",")):\(request.publicOnly):\(request.nowMillis)"
    if let cursor = request.cursor {
      guard cursor.scope == scope else { throw AgentMemoryBrowseError.invalidRequest }
      guard cursor.revision == revision else { throw AgentMemoryBrowseError.pageChanged }
    }
    let start = request.backwards
      ? max((request.cursor?.position ?? 0) - request.limit, 0)
      : (request.cursor.map { $0.position + 1 } ?? 0)
    let shown = Array(entries.dropFirst(start).prefix(request.limit))
    let makeCursor: (Int, String) -> AgentMemoryBrowseCursor = {
      AgentMemoryBrowseCursor(position: $0, itemId: $1, revision: revision, scope: scope)
    }
    let next = start + shown.count < entries.count && !shown.isEmpty
      ? makeCursor(start + shown.count - 1, shown.last!.item.id) : nil
    let previous = start > 0 && !shown.isEmpty ? makeCursor(start, shown[0].item.id) : nil
    return AgentMemoryBrowsePage(
      entries: shown,
      counts: AgentMemoryBrowseCounts(active: active.count, conflicts: groups.count, history: history.count),
      next: next,
      previous: previous
    )
  }
}

protocol AgentMemoryStore {
  @discardableResult func remember(_ item: AgentMemoryItem) -> AgentMemoryWriteResult
  func recall(query: String) -> [AgentMemoryItem]
  func recent(limit: Int) -> [AgentMemoryItem]
  func count() -> Int
  @discardableResult func rebindConversationScope(sourceConversationId: String, targetConversationId: String) -> Int
  @discardableResult func delete(query: String) -> Int
  func snapshot() -> AgentMemorySnapshot
  @discardableResult func update(itemId: String, value: String, key: String) -> AgentMemoryWriteResult?
  @discardableResult func deleteById(_ itemId: String) -> Bool
  @discardableResult func setImportant(itemId: String, important: Bool) -> Bool
  @discardableResult func setPrivate(itemId: String, privateMemory: Bool) -> Bool
  @discardableResult func deprecate(itemId: String) -> Bool
  @discardableResult func resolveConflict(groupId: String, selectedItemId: String, mergedValue: String?) -> AgentMemoryItem?
}

extension AgentMemoryStore {
  func browse(_ request: AgentMemoryBrowseRequest) throws -> AgentMemoryBrowsePage {
    try snapshot().browse(request)
  }

  func browseCounts(kinds: Set<AgentMemoryKind> = []) -> AgentMemoryBrowseCounts {
    (try? browse(AgentMemoryBrowseRequest(kinds: kinds, limit: 1)).counts) ??
      AgentMemoryBrowseCounts(active: 0, conflicts: 0, history: 0)
  }

  func browseKindCounts() -> [AgentMemoryKind: Int] {
    Dictionary(grouping: snapshot().activeItems, by: \.kind).mapValues(\.count)
  }
}

final class InMemoryAgentMemoryStore: AgentMemoryStore {
  static let accessRefreshIntervalMillis: Int64 = 5 * 60 * 1_000

  private var allItems: [AgentMemoryItem]
  private let nowMillis: () -> Int64
  private var recallIndex = AgentMemoryRecallCandidateIndex()
  private var recallIndexDirty = true
  private(set) var lastRecallCandidateCount = 0

  init(items: [AgentMemoryItem] = [], nowMillis: @escaping () -> Int64 = AgentMemoryClock.nowMillis) {
    self.allItems = AgentMemoryIdentity.normalizeConflicts(items)
    self.nowMillis = nowMillis
  }

  private func normalizeConflicts() {
    let normalized = AgentMemoryIdentity.normalizeConflicts(allItems)
    if normalized != allItems {
      allItems = normalized
      recallIndexDirty = true
    }
  }

  @discardableResult
  func remember(_ item: AgentMemoryItem) -> AgentMemoryWriteResult {
    normalizeConflicts()
    defer { recallIndexDirty = true }
    let cleanValue = item.value.agentMemoryTrimmed
    if cleanValue.isEmpty {
      return AgentMemoryWriteResult(item: nil)
    }

    let normalizedKey = AgentMemoryKeyPolicy.normalize(
      item.key.isEmpty ? AgentMemoryKeyPolicy.inferKey(from: cleanValue) : item.key
    )
    let nextItem = item.copy(
      value: cleanValue,
      timestampMillis: item.timestampMillis,
      key: normalizedKey,
      status: .active,
      conflictGroupId: ""
    )

    if let duplicateIndex = allItems.firstIndex(where: {
      $0.status != .superseded &&
        AgentMemoryIdentity.sameKey($0, nextItem) &&
        $0.value.agentMemoryEquals(nextItem.value)
    }) {
      let existing = allItems[duplicateIndex]
      let merged = existing.copy(
        confidence: max(existing.confidence, nextItem.confidence),
        evidenceCount: min(existing.evidenceCount + nextItem.evidenceCount, AgentMemoryPolicy.maxEvidenceCount),
        lastConfirmedAtMillis: max(existing.lastConfirmedAtMillis, nextItem.lastConfirmedAtMillis, nowMillis()),
        expiresAtMillis: max(existing.expiresAtMillis, nextItem.expiresAtMillis)
      )
      allItems[duplicateIndex] = merged
      return AgentMemoryWriteResult(item: merged, duplicate: true)
    }

    if normalizedKey.isEmpty {
      allItems.append(nextItem)
      allItems = trimHistory(allItems)
      return AgentMemoryWriteResult(item: nextItem)
    }

    let competing = allItems.filter {
      AgentMemoryIdentity.sameKey($0, nextItem) &&
        $0.status != .superseded
    }
    if competing.isEmpty {
      allItems.append(nextItem)
      allItems = trimHistory(allItems)
      return AgentMemoryWriteResult(item: nextItem)
    }

    let groupId = competing.first(where: { !$0.conflictGroupId.isEmpty })?.conflictGroupId ?? UUID().uuidString
    let latest = competing.max { $0.version < $1.version }
    let maxVersion = competing.map(\.version).max() ?? 0
    for existing in competing {
      if let index = allItems.firstIndex(where: { $0.id == existing.id }) {
        allItems[index] = existing.copy(status: .conflicted, conflictGroupId: groupId)
      }
    }

    let conflicted = nextItem.copy(
      version: maxVersion + 1,
      supersedesId: latest?.id ?? "",
      status: .conflicted,
      conflictGroupId: groupId
    )
    allItems.append(conflicted)
    allItems = trimHistory(allItems)
    return AgentMemoryWriteResult(item: conflicted, conflict: buildConflict(groupId: groupId, items: allItems))
  }

  func recall(query: String) -> [AgentMemoryItem] {
    normalizeConflicts()
    let cleanQuery = query.agentMemoryTrimmed
    if cleanQuery.isEmpty { return [] }
    let now = nowMillis()
    if recallIndexDirty {
      recallIndex.rebuild(allItems)
      recallIndexDirty = false
    }
    let candidates = recallIndex.candidates(query: cleanQuery)
    lastRecallCandidateCount = candidates.count
    let selected = Array(candidates
      .filter { $0.status == .active && !$0.privateMemory && !$0.isExpired(nowMillis: now) }
      .filter { lexicalScore($0, query: cleanQuery) > 0 }
      .map { ($0, score($0, query: cleanQuery, nowMillis: now)) }
      .sorted {
        if $0.1 != $1.1 { return $0.1 > $1.1 }
        if $0.0.important != $1.0.important { return $0.0.important && !$1.0.important }
        return $0.0.timestampMillis > $1.0.timestampMillis
      }
      .map(\.0)
      .prefix(AgentMemoryPolicy.maxRecallItems))

    let recalledIds = Set(selected.map(\.id))
    if !recalledIds.isEmpty {
      allItems = allItems.map { item in
        guard recalledIds.contains(item.id),
              item.lastAccessedAtMillis == 0 ||
                now - item.lastAccessedAtMillis >= Self.accessRefreshIntervalMillis else { return item }
        return item.copy(lastAccessedAtMillis: now)
      }
    }
    let refreshedById = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
    return selected.compactMap { refreshedById[$0.id] }
  }

  func recent(limit: Int = 10) -> [AgentMemoryItem] {
    normalizeConflicts()
    let now = nowMillis()
    return allItems
      .filter { $0.status == .active && !$0.privateMemory && !$0.isExpired(nowMillis: now) }
      .sorted {
        if $0.important != $1.important { return $0.important && !$1.important }
        return $0.timestampMillis > $1.timestampMillis
      }
      .prefix(max(limit, 0))
      .map { $0 }
  }

  func count() -> Int {
    normalizeConflicts()
    return allItems.filter { $0.status == .active }.count
  }

  @discardableResult
  func rebindConversationScope(sourceConversationId: String, targetConversationId: String) -> Int {
    let source = sourceConversationId.agentMemoryTrimmed
    let target = targetConversationId.agentMemoryTrimmed
    if source.isEmpty || target.isEmpty || source == target { return 0 }

    var changed = 0
    allItems = allItems.map { item in
      if item.scope == .conversation && item.scopeId == source {
        changed += 1
        return item.copy(scopeId: target)
      }
      return item
    }
    return changed
  }

  @discardableResult
  func delete(query: String) -> Int {
    normalizeConflicts()
    let cleanQuery = query.agentMemoryTrimmed
    if cleanQuery.isEmpty { return 0 }
    let before = allItems.count
    allItems.removeAll { lexicalScore($0, query: cleanQuery) > 0 }
    if allItems.count != before { recallIndexDirty = true }
    return before - allItems.count
  }

  func snapshot() -> AgentMemorySnapshot {
    normalizeConflicts()
    let active = allItems
      .filter { $0.status == .active }
      .sorted {
        if $0.important != $1.important { return $0.important && !$1.important }
        return $0.timestampMillis > $1.timestampMillis
      }
    let conflicts = Dictionary(grouping: allItems.filter {
      $0.status == .conflicted && !$0.conflictGroupId.isEmpty
    }, by: \.conflictGroupId)
      .values
      .compactMap { candidates -> AgentMemoryConflict? in
        guard candidates.count > 1 else { return nil }
        let ordered = candidates.sorted { $0.version < $1.version }
        return AgentMemoryConflict(
          groupId: ordered[0].conflictGroupId,
          kind: ordered[0].kind,
          key: ordered[0].key,
          candidates: ordered
        )
      }
      .sorted {
        ($0.candidates.map(\.timestampMillis).max() ?? 0) > ($1.candidates.map(\.timestampMillis).max() ?? 0)
      }
    let history = allItems
      .filter { $0.status == .superseded }
      .sorted { $0.timestampMillis > $1.timestampMillis }
    return AgentMemorySnapshot(activeItems: active, conflicts: conflicts, historyItems: history)
  }

  @discardableResult
  func update(itemId: String, value: String, key: String = "") -> AgentMemoryWriteResult? {
    normalizeConflicts()
    let cleanValue = value.agentMemoryTrimmed
    if cleanValue.isEmpty { return nil }
    guard let index = allItems.firstIndex(where: { $0.id == itemId && $0.status == .active }) else {
      return nil
    }
    let previous = allItems[index]
    allItems[index] = previous.copy(status: .superseded)
    return remember(previous.copy(
      value: cleanValue,
      timestampMillis: nowMillis(),
      id: UUID().uuidString,
      source: "memory_edit",
      key: key.agentMemoryTrimmed.isEmpty ? previous.key : key,
      version: previous.version + 1,
      supersedesId: previous.id,
      status: .active,
      conflictGroupId: ""
    ))
  }

  @discardableResult
  func deleteById(_ itemId: String) -> Bool {
    normalizeConflicts()
    guard let target = allItems.first(where: { $0.id == itemId }) else { return false }
    let relatedIds = AgentMemoryIdentity.lineageIds(in: allItems, target: target)
    allItems.removeAll { candidate in
      relatedIds.contains(candidate.id) ||
        (!target.key.isEmpty && AgentMemoryIdentity.sameKey(candidate, target))
    }
    if !target.conflictGroupId.isEmpty {
      let remaining = allItems.filter {
        $0.conflictGroupId == target.conflictGroupId && $0.status == .conflicted &&
          AgentMemoryIdentity.sameKey($0, target)
      }
      if remaining.count == 1, let index = allItems.firstIndex(where: { $0.id == remaining[0].id }) {
        allItems[index] = remaining[0].copy(status: .active, conflictGroupId: "")
      }
    }
    allItems = trimHistory(allItems)
    recallIndexDirty = true
    return true
  }

  @discardableResult
  func setImportant(itemId: String, important: Bool) -> Bool {
    guard let index = allItems.firstIndex(where: { $0.id == itemId && $0.status == .active }) else {
      return false
    }
    allItems[index] = allItems[index].copy(important: important)
    recallIndexDirty = true
    return true
  }

  @discardableResult
  func setPrivate(itemId: String, privateMemory: Bool) -> Bool {
    guard let index = allItems.firstIndex(where: { $0.id == itemId && $0.status == .active }) else {
      return false
    }
    allItems[index] = allItems[index].copy(privateMemory: privateMemory)
    recallIndexDirty = true
    return true
  }

  @discardableResult
  func deprecate(itemId: String) -> Bool {
    guard let index = allItems.firstIndex(where: { $0.id == itemId && $0.status == .active }) else {
      return false
    }
    allItems[index] = allItems[index].copy(status: .superseded)
    recallIndexDirty = true
    return true
  }

  @discardableResult
  func resolveConflict(
    groupId: String,
    selectedItemId: String,
    mergedValue: String? = nil
  ) -> AgentMemoryItem? {
    normalizeConflicts()
    let candidates = AgentMemoryIdentity.conflictCandidates(
      in: allItems,
      groupId: groupId,
      selectedItemId: selectedItemId
    )
    guard candidates.count >= 2, let selected = candidates.first(where: { $0.id == selectedItemId }) else {
      return nil
    }
    for candidate in candidates {
      if let index = allItems.firstIndex(where: { $0.id == candidate.id }) {
        allItems[index] = candidate.copy(status: .superseded)
      }
    }
    let cleanMergedValue = mergedValue?.agentMemoryTrimmed ?? ""
    let resolved = selected.copy(
      value: cleanMergedValue.isEmpty ? selected.value : cleanMergedValue,
      timestampMillis: nowMillis(),
      id: UUID().uuidString,
      source: cleanMergedValue.isEmpty ? "memory_conflict_selection" : "memory_conflict_merge",
      version: (candidates.map(\.version).max() ?? selected.version) + 1,
      supersedesId: selected.id,
      status: .active,
      conflictGroupId: ""
    )
    allItems.append(resolved)
    allItems = trimHistory(allItems)
    recallIndexDirty = true
    return resolved
  }

  private func score(_ item: AgentMemoryItem, query: String, nowMillis: Int64) -> Double {
    let lexicalScore = lexicalScore(item, query: query)
    let ageDays = Double(max(nowMillis - item.timestampMillis, 0)) / Double(AgentMemoryPolicy.dayMillis)
    let recency = 1.0 / (1.0 + ageDays / 30.0)
    let evidence = log(1.0 + Double(max(item.evidenceCount, 1)))
    return lexicalScore * (0.5 + min(max(item.confidence, 0), 1)) +
      recency + evidence + (item.important ? 2.0 : 0.0)
  }

  private func lexicalScore(_ item: AgentMemoryItem, query: String) -> Double {
    let value = item.value.lowercased()
    let searchable = "\(item.key) \(value)".lowercased()
    let cleanQuery = query.lowercased()
    if cleanQuery.agentMemoryTrimmed.isEmpty { return 0 }
    var lexicalScore = 0.0
    if value == cleanQuery { lexicalScore += 12.0 }
    if value.agentMemoryContains(cleanQuery) || cleanQuery.agentMemoryContains(value) {
      lexicalScore += 8.0
    }
    for token in AgentMemoryKeyPolicy.queryTokens(cleanQuery) {
      if searchable.agentMemoryContains(token) { lexicalScore += 1.0 }
    }
    return lexicalScore
  }

  private func buildConflict(groupId: String, items: [AgentMemoryItem]) -> AgentMemoryConflict? {
    let candidates = items
      .filter { $0.conflictGroupId == groupId && $0.status == .conflicted }
      .sorted { $0.version < $1.version }
    guard candidates.count >= 2 else { return nil }
    return AgentMemoryConflict(
      groupId: groupId,
      kind: candidates[0].kind,
      key: candidates[0].key,
      candidates: candidates
    )
  }

  private func trimHistory(_ items: [AgentMemoryItem]) -> [AgentMemoryItem] {
    items.sorted { $0.timestampMillis < $1.timestampMillis }
  }
}

private struct AgentMemoryRecallCandidateIndex {
  private var postings: [String: Set<String>] = [:]
  private var itemsById: [String: AgentMemoryItem] = [:]
  private var orderById: [String: Int] = [:]

  mutating func rebuild(_ items: [AgentMemoryItem]) {
    postings.removeAll(keepingCapacity: true)
    itemsById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    orderById = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
    for item in items where item.status == .active && !item.privateMemory {
      for term in documentTerms(item) {
        postings[term, default: []].insert(item.id)
      }
    }
  }

  func candidates(query: String) -> [AgentMemoryItem] {
    let clean = query.lowercased().agentMemoryTrimmed
    guard !clean.isEmpty else { return [] }
    var ids = Set<String>()
    for term in queryTerms(clean) {
      ids.formUnion(postings[term] ?? [])
    }
    return ids
      .sorted { (orderById[$0] ?? .max) < (orderById[$1] ?? .max) }
      .compactMap { itemsById[$0] }
  }

  private func documentTerms(_ item: AgentMemoryItem) -> Set<String> {
    let value = item.value.lowercased()
    let searchable = "\(item.key) \(value)".lowercased()
    var terms: Set<String> = ["v:\(value)"]
    value.forEach { terms.insert("c:\($0)") }
    characterWindows(searchable, size: 2).forEach { terms.insert("g:\($0)") }
    return terms
  }

  private func queryTerms(_ query: String) -> Set<String> {
    let characters = Array(query)
    var terms = Set<String>()
    if characters.count == 1 {
      terms.insert("c:\(query)")
    } else if let gram = characterWindows(query, size: 2).first {
      terms.insert("g:\(gram)")
    }
    for token in AgentMemoryKeyPolicy.queryTokens(query) {
      if let gram = characterWindows(token, size: 2).first {
        terms.insert("g:\(gram)")
      } else {
        terms.insert("c:\(token)")
      }
    }
    if characters.count <= 90 {
      for start in characters.indices {
        for end in (start + 1)...characters.count {
          terms.insert("v:\(String(characters[start..<end]))")
        }
      }
    } else {
      characters.forEach { terms.insert("c:\($0)") }
    }
    return terms
  }

  private func characterWindows(_ value: String, size: Int) -> [String] {
    let characters = Array(value)
    guard size > 0, characters.count >= size else { return [] }
    return (0...(characters.count - size)).map { offset in
      String(characters[offset..<(offset + size)])
    }
  }
}

enum AgentMemoryCommandParser {
  static func memoryValue(fromGoal goal: String) -> String? {
    let prefixes = [
      "remember ",
      "save note ",
      "save memory ",
      "memorize ",
      "\u{8bb0}\u{4f4f}",
      "\u{4fdd}\u{5b58}\u{8bb0}\u{5fc6}",
      "\u{4fdd}\u{5b58}\u{7b14}\u{8bb0}"
    ]
    guard let prefix = prefixes.first(where: { goal.agentMemoryHasPrefix($0) }) else {
      return nil
    }
    let value = String(goal.dropFirst(prefix.count)).agentMemoryTrimmed
    return value.isEmpty ? nil : value
  }

  static func memoryCaptureValue(fromGoal goal: String) -> Bool? {
    switch goal.agentMemoryTrimmed.lowercased() {
    case "pause memory", "stop memory", "disable memory capture",
         "\u{6682}\u{505c}\u{8bb0}\u{5fc6}", "\u{505c}\u{6b62}\u{8bb0}\u{5fc6}", "\u{5173}\u{95ed}\u{8bb0}\u{5fc6}\u{6355}\u{83b7}":
      return false
    case "resume memory", "enable memory capture",
         "\u{6062}\u{590d}\u{8bb0}\u{5fc6}", "\u{5f00}\u{542f}\u{8bb0}\u{5fc6}\u{6355}\u{83b7}":
      return true
    default:
      return nil
    }
  }

  static func item(fromCommand rawValue: String, nowMillis: Int64 = AgentMemoryClock.nowMillis()) -> AgentMemoryItem {
    let cleanValue = rawValue.agentMemoryTrimmed
    let typedPrefixes: [(String, AgentMemoryKind)] = [
      ("profile", .identity),
      ("identity", .identity),
      ("contact", .contact),
      ("preference", .preference),
      ("workflow", .workflow),
      ("security", .safety),
      ("safety", .safety),
      ("knowledge", .knowledge),
      ("\u{8eab}\u{4efd}", .identity),
      ("\u{8054}\u{7cfb}\u{4eba}", .contact),
      ("\u{504f}\u{597d}", .preference),
      ("\u{5de5}\u{4f5c}\u{6d41}", .workflow),
      ("\u{5b89}\u{5168}", .safety),
      ("\u{77e5}\u{8bc6}", .knowledge)
    ]
    let typed = typedPrefixes.first { entry in
      cleanValue.agentMemoryHasPrefix(entry.0 + ":")
    }
    let typedContent = typed.map { entry in
      String(cleanValue.dropFirst(entry.0.count + 1)).agentMemoryTrimmed
    }
    let content = typedContent?.isEmpty == false ? typedContent! : cleanValue
    return AgentMemoryItem(
      kind: typed?.1 ?? .knowledge,
      value: content,
      timestampMillis: nowMillis,
      source: "agent_memory_command",
      key: AgentMemoryKeyPolicy.explicitKey(from: content)
    )
  }
}

enum AgentMemoryJSONCodec {
  static func encodeItems(_ items: [AgentMemoryItem]) throws -> Data {
    try JSONEncoder().encode(items)
  }

  static func decodeItems(_ data: Data) throws -> [AgentMemoryItem] {
    try JSONDecoder().decode([AgentMemoryItem].self, from: data)
      .filter { !$0.value.agentMemoryTrimmed.isEmpty }
  }

  static func encodeSnapshot(_ snapshot: AgentMemorySnapshot) throws -> Data {
    try JSONEncoder().encode(snapshot)
  }

  static func decodeSnapshot(_ data: Data) throws -> AgentMemorySnapshot {
    try JSONDecoder().decode(AgentMemorySnapshot.self, from: data)
  }
}

enum AgentMemoryKeyPolicy {
  static func explicitKey(from value: String) -> String {
    for (offset, character) in value.enumerated() where (character == "=" || character == ":") && (1...64).contains(offset) {
      let index = value.index(value.startIndex, offsetBy: offset)
      return String(value[..<index]).agentMemoryTrimmed
    }
    return ""
  }

  static func inferKey(from value: String) -> String {
    let explicit = explicitKey(from: value)
    if !explicit.isEmpty { return explicit }

    let lowered = value.agentMemoryTrimmed.lowercased()
    let prefixes = ["my ", "preferred ", "default "]
    for prefix in prefixes where lowered.hasPrefix(prefix) {
      let remaining = lowered.dropFirst(prefix.count)
      guard let range = remaining.range(of: " is ") else { continue }
      let candidate = String(remaining[..<range.lowerBound]).agentMemoryTrimmed
      if (2...40).contains(candidate.count) {
        return candidate
      }
    }
    return ""
  }

  static func normalize(_ value: String) -> String {
    var filtered = ""
    for scalar in value.agentMemoryTrimmed.lowercased().unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) ||
        scalar == " " ||
        scalar == "_" ||
        scalar == ":" ||
        scalar == "." ||
        scalar == "-" {
        filtered.unicodeScalars.append(scalar)
      }
    }
    let collapsed = filtered
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
    return String(collapsed.prefix(AgentMemoryPolicy.maxKeyLength))
  }

  static func queryTokens(_ value: String) -> Set<String> {
    var tokens = Set(
      value
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.count >= AgentMemoryPolicy.minTokenLength }
    )
    let cjkCharacters = value
      .map(String.init)
      .filter { character in
        character.unicodeScalars.allSatisfy { (0x3400...0x9FFF).contains($0.value) }
      }
    if cjkCharacters.count >= 2 {
      for index in 0..<(cjkCharacters.count - 1) {
        tokens.insert(cjkCharacters[index] + cjkCharacters[index + 1])
      }
    }
    return tokens
  }
}

enum AgentMemoryWire {
  static func token(_ value: String?) -> String {
    (value ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased()
  }
}

enum AgentMemoryClock {
  static func nowMillis() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }
}

enum AgentMemoryPolicy {
  static let maxItems = 1_000
  static let maxRecallItems = 8
  static let maxEvidenceCount = 10_000
  static let minTokenLength = 3
  static let maxKeyLength = 80
  static let dayMillis: Int64 = 86_400_000
}

extension AgentMemoryItem {
  func copy(
    kind: AgentMemoryKind? = nil,
    value: String? = nil,
    timestampMillis: Int64? = nil,
    id: String? = nil,
    source: String? = nil,
    key: String? = nil,
    version: Int? = nil,
    supersedesId: String? = nil,
    important: Bool? = nil,
    status: AgentMemoryStatus? = nil,
    conflictGroupId: String? = nil,
    scope: AgentMemoryScope? = nil,
    scopeId: String? = nil,
    confidence: Double? = nil,
    evidenceCount: Int? = nil,
    autoLearned: Bool? = nil,
    lastConfirmedAtMillis: Int64? = nil,
    lastAccessedAtMillis: Int64? = nil,
    expiresAtMillis: Int64? = nil,
    whyRemembered: String? = nil,
    originConversationId: String? = nil,
    originEventId: String? = nil,
    privateMemory: Bool? = nil
  ) -> AgentMemoryItem {
    AgentMemoryItem(
      kind: kind ?? self.kind,
      value: value ?? self.value,
      timestampMillis: timestampMillis ?? self.timestampMillis,
      id: id ?? self.id,
      source: source ?? self.source,
      key: key ?? self.key,
      version: version ?? self.version,
      supersedesId: supersedesId ?? self.supersedesId,
      important: important ?? self.important,
      status: status ?? self.status,
      conflictGroupId: conflictGroupId ?? self.conflictGroupId,
      scope: scope ?? self.scope,
      scopeId: scopeId ?? self.scopeId,
      confidence: confidence ?? self.confidence,
      evidenceCount: evidenceCount ?? self.evidenceCount,
      autoLearned: autoLearned ?? self.autoLearned,
      lastConfirmedAtMillis: lastConfirmedAtMillis ?? self.lastConfirmedAtMillis,
      lastAccessedAtMillis: lastAccessedAtMillis ?? self.lastAccessedAtMillis,
      expiresAtMillis: expiresAtMillis ?? self.expiresAtMillis,
      whyRemembered: whyRemembered ?? self.whyRemembered,
      originConversationId: originConversationId ?? self.originConversationId,
      originEventId: originEventId ?? self.originEventId,
      privateMemory: privateMemory ?? self.privateMemory
    )
  }
}

extension String {
  var agentMemoryTrimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func agentMemoryNonBlankOr(_ fallback: String) -> String {
    let clean = agentMemoryTrimmed
    return clean.isEmpty ? fallback : clean
  }

  func agentMemoryEquals(_ other: String) -> Bool {
    compare(other, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
  }

  func agentMemoryContains(_ needle: String) -> Bool {
    range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
  }

  func agentMemoryHasPrefix(_ prefix: String) -> Bool {
    range(of: prefix, options: [.caseInsensitive, .anchored]) != nil
  }
}
