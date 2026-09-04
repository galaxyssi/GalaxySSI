import Foundation

enum GalaxySSIMemoryLifecycleState: String, CaseIterable, Identifiable {
  case current
  case planned
  case historical
  case deprecated
  case pending
  case conflicted

  var id: String { rawValue }
}

struct GalaxySSIMemoryCategoryDescriptor: Identifiable {
  var id: String
  var titleKey: String
  var titleFallback: String
  var subtitleKey: String
  var subtitleFallback: String
  var systemImage: String
  var tone: GalaxySSIMemoryTone
  var kinds: Set<AgentMemoryKind>
}

enum GalaxySSIMemoryTone {
  case accent
  case blue
  case green
  case purple
  case amber
  case neutral
}

struct GalaxySSIMemoryControlSnapshot {
  var agentMemory: AgentMemorySnapshot
  var knowledgeStats: AgentKnowledgeStats
  var inbox: GlobalMemoryInbox
  var evolutionRecords: [GlobalMemoryEvolutionRecord]
  var auditReport: GlobalMemoryAuditReport
  var nowMillis: Int64

  static func make(
    agentMemory: AgentMemorySnapshot,
    knowledgeStats: AgentKnowledgeStats,
    inbox: GlobalMemoryInbox,
    evolutionRecords: [GlobalMemoryEvolutionRecord],
    auditReport: GlobalMemoryAuditReport,
    nowMillis: Int64 = GlobalMemoryClock.nowMillis()
  ) -> GalaxySSIMemoryControlSnapshot {
    GalaxySSIMemoryControlSnapshot(
      agentMemory: agentMemory,
      knowledgeStats: knowledgeStats,
      inbox: inbox,
      evolutionRecords: Array(evolutionRecords.suffix(100)),
      auditReport: auditReport,
      nowMillis: nowMillis
    )
  }

  var world: PersonalWorldModel {
    PersonalWorldModel(
      items: Self.worldItems(from: allAgentItems, nowMillis: nowMillis),
      updatedAtMillis: allAgentItems.map(\.timestampMillis).max() ?? 0
    )
  }

  var temporal: GlobalMemoryTemporalSnapshot {
    GlobalMemoryTemporalPolicy.snapshot(world: world, inbox: inbox)
  }

  var pendingCandidates: [GlobalMemoryCandidate] {
    inbox.pending()
  }

  var activeCount: Int {
    agentMemory.activeCount
  }

  var historyCount: Int {
    agentMemory.historyCount
  }

  var conflictCount: Int {
    agentMemory.conflicts.count + temporal.count(.conflicted)
  }

  var graph: GalaxySSIMemoryGraphSnapshot {
    GalaxySSIMemoryGraphSnapshot.make(
      items: allAgentItems,
      conflicts: agentMemory.conflicts,
      candidates: inbox.candidates
    )
  }

  func activeCount(for kinds: Set<AgentMemoryKind>) -> Int {
    agentMemory.activeItems.filter { kinds.contains($0.kind) }.count
  }

  func items(for state: GalaxySSIMemoryLifecycleState) -> [AgentMemoryItem] {
    switch state {
    case .current:
      return agentMemory.activeItems
        .filter { !$0.isExpired(nowMillis: nowMillis) && $0.status == .active }
        .sorted { $0.timestampMillis > $1.timestampMillis }
    case .planned:
      return agentMemory.activeItems
        .filter { [.task, .workflow].contains($0.kind) && $0.autoLearned }
        .sorted { $0.timestampMillis > $1.timestampMillis }
    case .historical:
      return agentMemory.historyItems
        .filter { $0.status != .superseded }
        .sorted { $0.timestampMillis > $1.timestampMillis }
    case .deprecated:
      return (agentMemory.historyItems.filter { $0.status == .superseded } +
        agentMemory.activeItems.filter { $0.isExpired(nowMillis: nowMillis) })
        .sorted { $0.timestampMillis > $1.timestampMillis }
    case .pending:
      return []
    case .conflicted:
      return agentMemory.conflicts.flatMap(\.candidates)
        .sorted { $0.timestampMillis > $1.timestampMillis }
    }
  }

  func candidates(for state: GalaxySSIMemoryLifecycleState) -> [GlobalMemoryCandidate] {
    switch state {
    case .planned:
      return inbox.candidates
        .filter { $0.temporalState == .planned }
        .sorted { $0.createdAtMillis > $1.createdAtMillis }
    case .pending:
      return inbox.candidates
        .filter { $0.status == .pendingReview }
        .sorted { $0.createdAtMillis > $1.createdAtMillis }
    case .conflicted:
      return inbox.candidates
        .filter { $0.status == .conflicted }
        .sorted { $0.createdAtMillis > $1.createdAtMillis }
    default:
      return []
    }
  }

  private var allAgentItems: [AgentMemoryItem] {
    Self.uniqueItems(agentMemory.activeItems + agentMemory.historyItems + agentMemory.conflicts.flatMap(\.candidates))
  }

  private static func uniqueItems(_ items: [AgentMemoryItem]) -> [AgentMemoryItem] {
    var seen = Set<String>()
    var result: [AgentMemoryItem] = []
    for item in items where seen.insert(item.id).inserted {
      result.append(item)
    }
    return result
  }

  private static func worldItems(from items: [AgentMemoryItem], nowMillis: Int64) -> [GlobalWorldItem] {
    items.map { item in
      let state = temporalState(for: item, nowMillis: nowMillis)
      return GlobalWorldItem(
        id: item.id,
        stableKey: stableKey(for: item),
        kind: worldKind(for: item.kind),
        layer: worldLayer(for: item),
        namespace: namespace(for: item),
        namespaceId: item.scopeId,
        topic: memoryTopic(item),
        value: item.value,
        confidence: item.confidence,
        contextVisibility: item.kind == .safety ? .localOnly : .shareable,
        evidenceCount: item.evidenceCount,
        conversationIds: item.scope == .conversation && !item.scopeId.isEmpty ? Set([item.scopeId]) : [],
        evidenceEventIds: [],
        evidenceProvenance: [],
        status: worldStatus(for: item),
        temporalState: state,
        conflictGroupId: item.conflictGroupId,
        supersedesItemIds: item.supersedesId.isEmpty ? [] : [item.supersedesId],
        firstSeenAtMillis: item.timestampMillis,
        lastSeenAtMillis: max(item.lastAccessedAtMillis, item.timestampMillis),
        expiresAtMillis: item.expiresAtMillis
      )
    }
  }

  private static func stableKey(for item: AgentMemoryItem) -> String {
    let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
    return key.isEmpty ? GlobalAgentText.stableKey("ios-agent-memory", item.kind.rawValue, item.value) : key
  }

  private static func memoryTopic(_ item: AgentMemoryItem) -> String {
    let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
    if !key.isEmpty { return key }
    return String(item.value.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func temporalState(for item: AgentMemoryItem, nowMillis: Int64) -> GlobalMemoryTemporalState {
    if item.isExpired(nowMillis: nowMillis) || item.status == .superseded { return .deprecated }
    if item.status == .conflicted { return .conflicted }
    if item.autoLearned && [.task, .workflow].contains(item.kind) { return .planned }
    return .current
  }

  private static func worldStatus(for item: AgentMemoryItem) -> GlobalWorldItemStatus {
    switch item.status {
    case .active:
      return item.isExpired() ? .superseded : .active
    case .conflicted:
      return .conflicted
    case .superseded:
      return .superseded
    }
  }

  private static func worldKind(for kind: AgentMemoryKind) -> GlobalWorldItemKind {
    switch kind {
    case .identity, .preference:
      return .preference
    case .task:
      return .task
    case .workflow:
      return .decision
    case .safety:
      return .risk
    case .contact, .knowledge:
      return .fact
    }
  }

  private static func worldLayer(for item: AgentMemoryItem) -> GlobalWorldLayer {
    switch item.scope {
    case .conversation:
      return .conversation
    case .contact, .device:
      return .user
    case .workspace, .application:
      return .topic
    case .global:
      return [.identity, .preference, .contact, .safety].contains(item.kind) ? .user : .topic
    }
  }

  private static func namespace(for item: AgentMemoryItem) -> GlobalMemoryNamespace {
    switch item.kind {
    case .identity, .preference, .contact:
      return .user
    case .task, .workflow:
      return .project
    case .safety:
      return .security
    case .knowledge:
      return .general
    }
  }
}

struct GalaxySSIMemoryGraphSnapshot {
  var nodes: [GalaxySSIMemoryGraphNode]
  var relations: [GalaxySSIMemoryGraphRelation]

  static func make(
    items: [AgentMemoryItem],
    conflicts: [AgentMemoryConflict],
    candidates: [GlobalMemoryCandidate]
  ) -> GalaxySSIMemoryGraphSnapshot {
    var nodes: [GalaxySSIMemoryGraphNode] = items.prefix(80).map { item in
      GalaxySSIMemoryGraphNode(
        id: item.id,
        title: item.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? String(item.value.prefix(54)).trimmingCharacters(in: .whitespacesAndNewlines)
          : item.key,
        subtitle: String(item.value.prefix(120)),
        badge: item.kind.rawValue,
        systemImage: item.important ? "pin.fill" : "brain",
        tone: item.status == .conflicted ? .amber : .purple
      )
    }

    nodes += candidates.prefix(40).map { candidate in
      GalaxySSIMemoryGraphNode(
        id: "candidate:\(candidate.id)",
        title: candidate.item.topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? candidate.kind.rawValue
          : candidate.item.topic,
        subtitle: candidate.risk == .privateBlocked ? "Private content blocked" : candidate.item.value,
        badge: candidate.status.rawValue,
        systemImage: "tray",
        tone: candidate.status == .conflicted ? .amber : .blue
      )
    }

    var relations: [GalaxySSIMemoryGraphRelation] = []
    for item in items where !item.supersedesId.isEmpty {
      relations.append(GalaxySSIMemoryGraphRelation(
        id: "supersedes:\(item.id):\(item.supersedesId)",
        title: "Supersession",
        subtitle: "\(item.id) -> \(item.supersedesId)",
        tone: .neutral
      ))
    }
    for conflict in conflicts where conflict.candidates.count > 1 {
      relations.append(GalaxySSIMemoryGraphRelation(
        id: "conflict:\(conflict.groupId)",
        title: conflict.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Conflict group" : conflict.key,
        subtitle: "\(conflict.candidates.count) versions disagree",
        tone: .amber
      ))
    }
    for candidate in candidates where !candidate.targetItemIds.isEmpty {
      relations.append(GalaxySSIMemoryGraphRelation(
        id: "candidate-target:\(candidate.id)",
        title: candidate.action.rawValue,
        subtitle: "\(candidate.targetItemIds.count) linked memories",
        tone: .blue
      ))
    }
    return GalaxySSIMemoryGraphSnapshot(nodes: nodes, relations: relations)
  }
}

struct GalaxySSIMemoryGraphNode: Identifiable {
  var id: String
  var title: String
  var subtitle: String
  var badge: String
  var systemImage: String
  var tone: GalaxySSIMemoryTone
}

struct GalaxySSIMemoryGraphRelation: Identifiable {
  var id: String
  var title: String
  var subtitle: String
  var tone: GalaxySSIMemoryTone
}
