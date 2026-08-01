import Foundation

enum GlobalWorldItemStatus: String, Codable, CaseIterable, Identifiable {
  case active = "ACTIVE"
  case conflicted = "CONFLICTED"
  case superseded = "SUPERSEDED"
  case completed = "COMPLETED"

  var id: String { rawValue }
}

enum GlobalMemoryTemporalState: String, Codable, CaseIterable, Identifiable {
  case historical = "HISTORICAL"
  case current = "CURRENT"
  case planned = "PLANNED"
  case deprecated = "DEPRECATED"
  case pending = "PENDING"
  case conflicted = "CONFLICTED"

  var id: String { rawValue }
}

enum GlobalMemoryNamespace: String, Codable, CaseIterable, Identifiable {
  case general = "GENERAL"
  case user = "USER"
  case project = "PROJECT"
  case device = "DEVICE"
  case security = "SECURITY"

  var id: String { rawValue }
}

struct GlobalMemoryNamespaceRef: Codable, Equatable, Hashable {
  var namespace: GlobalMemoryNamespace
  var scopeId: String

  init(namespace: GlobalMemoryNamespace, scopeId: String = "") {
    self.namespace = namespace
    self.scopeId = GlobalMemoryNamespacePolicy.normalizeScope(scopeId)
  }

  var key: String {
    let base = namespace.rawValue.lowercased()
    return scopeId.isEmpty ? base : "\(base):\(scopeId)"
  }

  enum CodingKeys: String, CodingKey {
    case namespace
    case scopeId = "scope_id"
  }
}

enum GlobalEntityRelationKind: String, Codable, CaseIterable, Identifiable {
  case owns = "OWNS"
  case uses = "USES"
  case supports = "SUPPORTS"
  case hasComponent = "HAS_COMPONENT"
  case hasState = "HAS_STATE"
  case namedAs = "NAMED_AS"
  case dependsOn = "DEPENDS_ON"
  case connectedTo = "CONNECTED_TO"
  case prefers = "PREFERS"
  case removed = "REMOVED"
  case relatedTo = "RELATED_TO"

  var id: String { rawValue }
}

struct GlobalEvidenceRef: Codable, Equatable, Hashable {
  var eventId: String
  var causalEventIds: Set<String>
  var conversationId: String
  var timestampMillis: Int64

  enum CodingKeys: String, CodingKey {
    case eventId = "event_id"
    case causalEventIds = "causal_event_ids"
    case conversationId = "conversation_id"
    case timestampMillis = "timestamp_millis"
  }

  init(
    eventId: String,
    causalEventIds: Set<String> = [],
    conversationId: String = "",
    timestampMillis: Int64 = 0
  ) {
    self.eventId = eventId
    self.causalEventIds = causalEventIds
    self.conversationId = conversationId
    self.timestampMillis = max(timestampMillis, 0)
  }

  func invalidated(by eventIds: Set<String>) -> Bool {
    eventIds.contains(eventId) || !causalEventIds.isDisjoint(with: eventIds)
  }
}

struct GlobalWorldItem: Codable, Equatable, Identifiable {
  var id: String
  var stableKey: String
  var kind: GlobalWorldItemKind
  var layer: GlobalWorldLayer
  var namespace: GlobalMemoryNamespace
  var namespaceId: String
  var topic: String
  var value: String
  var confidence: Double
  var contextVisibility: GlobalWorldContextVisibility
  var evidenceCount: Int
  var conversationIds: Set<String>
  var evidenceEventIds: [String]
  var evidenceProvenance: [GlobalEvidenceRef]
  var status: GlobalWorldItemStatus
  var temporalState: GlobalMemoryTemporalState
  var conflictGroupId: String
  var supersedesItemIds: [String]
  var supersededByItemId: String
  var firstSeenAtMillis: Int64
  var lastSeenAtMillis: Int64
  var expiresAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case id
    case stableKey = "stable_key"
    case kind
    case layer
    case namespace
    case namespaceId = "namespace_id"
    case topic
    case value
    case confidence
    case contextVisibility = "context_visibility"
    case evidenceCount = "evidence_count"
    case conversationIds = "conversation_ids"
    case evidenceEventIds = "evidence_event_ids"
    case evidenceProvenance = "evidence_provenance"
    case status
    case temporalState = "temporal_state"
    case conflictGroupId = "conflict_group_id"
    case supersedesItemIds = "supersedes_item_ids"
    case supersededByItemId = "superseded_by_item_id"
    case firstSeenAtMillis = "first_seen_at_millis"
    case lastSeenAtMillis = "last_seen_at_millis"
    case expiresAtMillis = "expires_at_millis"
  }

  init(
    id: String = UUID().uuidString,
    stableKey: String,
    kind: GlobalWorldItemKind,
    layer: GlobalWorldLayer,
    namespace: GlobalMemoryNamespace = .general,
    namespaceId: String = "",
    topic: String,
    value: String,
    confidence: Double,
    contextVisibility: GlobalWorldContextVisibility = .shareable,
    evidenceCount: Int = 1,
    conversationIds: Set<String> = [],
    evidenceEventIds: [String] = [],
    evidenceProvenance: [GlobalEvidenceRef] = [],
    status: GlobalWorldItemStatus = .active,
    temporalState: GlobalMemoryTemporalState = .current,
    conflictGroupId: String = "",
    supersedesItemIds: [String] = [],
    supersededByItemId: String = "",
    firstSeenAtMillis: Int64 = GlobalMemoryClock.nowMillis(),
    lastSeenAtMillis: Int64 = GlobalMemoryClock.nowMillis(),
    expiresAtMillis: Int64 = 0
  ) {
    self.id = id
    self.stableKey = stableKey
    self.kind = kind
    self.layer = layer
    self.namespace = namespace
    self.namespaceId = GlobalMemoryNamespacePolicy.normalizeScope(namespaceId)
    self.topic = topic
    self.value = value
    self.confidence = min(max(confidence, 0), 1)
    self.contextVisibility = contextVisibility
    self.evidenceCount = max(evidenceCount, 1)
    self.conversationIds = conversationIds
    self.evidenceEventIds = evidenceEventIds
    self.evidenceProvenance = evidenceProvenance
    self.status = status
    self.temporalState = temporalState
    self.conflictGroupId = conflictGroupId
    self.supersedesItemIds = supersedesItemIds
    self.supersededByItemId = supersededByItemId
    self.firstSeenAtMillis = max(firstSeenAtMillis, 0)
    self.lastSeenAtMillis = max(lastSeenAtMillis, 0)
    self.expiresAtMillis = max(expiresAtMillis, 0)
  }

  var memoryNamespaceKey: String {
    GlobalMemoryNamespaceRef(namespace: namespace, scopeId: namespaceId).key
  }
}

struct GlobalConversationLink: Codable, Equatable, Identifiable {
  var id: String
  var leftConversationId: String
  var rightConversationId: String
  var topic: String
  var strength: Double
  var evidenceCount: Int
  var evidenceProvenance: [GlobalEvidenceRef]
  var lastSeenAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case id
    case leftConversationId = "left_conversation_id"
    case rightConversationId = "right_conversation_id"
    case topic
    case strength
    case evidenceCount = "evidence_count"
    case evidenceProvenance = "evidence_provenance"
    case lastSeenAtMillis = "last_seen_at_millis"
  }

  init(
    id: String = UUID().uuidString,
    leftConversationId: String,
    rightConversationId: String,
    topic: String,
    strength: Double,
    evidenceCount: Int = 1,
    evidenceProvenance: [GlobalEvidenceRef] = [],
    lastSeenAtMillis: Int64 = GlobalMemoryClock.nowMillis()
  ) {
    self.id = id
    self.leftConversationId = leftConversationId
    self.rightConversationId = rightConversationId
    self.topic = topic
    self.strength = min(max(strength, 0), 1)
    self.evidenceCount = max(evidenceCount, 1)
    self.evidenceProvenance = evidenceProvenance
    self.lastSeenAtMillis = max(lastSeenAtMillis, 0)
  }
}

struct PersonalWorldModel: Codable, Equatable {
  var items: [GlobalWorldItem]
  var links: [GlobalConversationLink]
  var processedEventIds: [String]
  var retractedEventIds: [String]
  var updatedAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case items
    case links
    case processedEventIds = "processed_event_ids"
    case retractedEventIds = "retracted_event_ids"
    case updatedAtMillis = "updated_at_millis"
  }

  init(
    items: [GlobalWorldItem] = [],
    links: [GlobalConversationLink] = [],
    processedEventIds: [String] = [],
    retractedEventIds: [String] = [],
    updatedAtMillis: Int64 = 0
  ) {
    self.items = items
    self.links = links
    self.processedEventIds = processedEventIds
    self.retractedEventIds = retractedEventIds
    self.updatedAtMillis = max(updatedAtMillis, 0)
  }

  func hasRetractedEvidence(_ eventIds: Set<String>) -> Bool {
    !eventIds.isDisjoint(with: Set(retractedEventIds))
  }

  func relevant(query: String, currentConversationId: String, limit: Int = 16, nowMillis: Int64 = GlobalMemoryClock.nowMillis()) -> [GlobalWorldItem] {
    let queryTokens = GlobalAgentText.tokens(query)
    let plan = GlobalMemoryQueryPlanner.plan(query)
    var allowedNamespaces = plan.preferredNamespaces
    allowedNamespaces.insert(.general)
    return items
      .filter { item in
        [.active, .conflicted].contains(item.status) &&
          (item.expiresAtMillis <= 0 || item.expiresAtMillis > nowMillis) &&
          (item.layer != .conversation || item.conversationIds.contains(currentConversationId)) &&
          (plan.preferredNamespaces.isEmpty || allowedNamespaces.contains(item.namespace))
      }
      .map { item -> (GlobalWorldItem, Double) in
        let overlap = GlobalAgentText.overlap(queryTokens, GlobalAgentText.tokens("\(item.topic) \(item.value)"))
        let crossConversationBoost = overlap > 0 &&
          item.layer != .conversation &&
          item.conversationIds.contains { $0 != currentConversationId } ? 0.16 : 0
        let globalBoost: Double
        switch item.layer {
        case .user: globalBoost = 0.28
        case .topic: globalBoost = overlap > 0 ? 0.18 : 0
        case .realtime: globalBoost = overlap > 0 ? 0.12 : 0
        case .conversation: globalBoost = 0
        }
        let namespaceBoost = plan.preferredNamespaces.contains(item.namespace) ? 0.20 : 0
        return (item, overlap + crossConversationBoost + globalBoost + namespaceBoost + item.confidence * 0.18)
      }
      .filter { $0.1 >= 0.16 || $0.0.layer == .user }
      .sorted {
        if $0.1 != $1.1 { return $0.1 > $1.1 }
        return $0.0.lastSeenAtMillis > $1.0.lastSeenAtMillis
      }
      .map(\.0)
      .prefix(max(limit, 0))
      .map { $0 }
  }
}

enum GlobalMemoryCandidateKind: String, Codable, CaseIterable, Identifiable {
  case fact = "FACT"
  case preference = "PREFERENCE"
  case identity = "IDENTITY"
  case decision = "DECISION"
  case projectState = "PROJECT_STATE"
  case goal = "GOAL"
  case relation = "RELATION"
  case skillOpportunity = "SKILL_OPPORTUNITY"

  var id: String { rawValue }
}

enum GlobalMemoryCandidateRisk: String, Codable, CaseIterable, Identifiable {
  case low = "LOW"
  case reviewRequired = "REVIEW_REQUIRED"
  case privateBlocked = "PRIVATE_BLOCKED"

  var id: String { rawValue }
}

enum GlobalMemoryCandidateStatus: String, Codable, CaseIterable, Identifiable {
  case autoMerged = "AUTO_MERGED"
  case pendingReview = "PENDING_REVIEW"
  case conflicted = "CONFLICTED"
  case approved = "APPROVED"
  case rejected = "REJECTED"
  case superseded = "SUPERSEDED"

  var id: String { rawValue }
}

enum GlobalMemoryEvolutionAction: String, Codable, CaseIterable, Identifiable {
  case create = "CREATE"
  case strengthen = "STRENGTHEN"
  case supersede = "SUPERSEDE"
  case link = "LINK"
  case consolidate = "CONSOLIDATE"
  case reviewConflict = "REVIEW_CONFLICT"
  case blockPrivate = "BLOCK_PRIVATE"

  var id: String { rawValue }
}

struct GlobalMemoryCandidate: Codable, Equatable, Identifiable {
  var id: String
  var sourceEventId: String
  var conversationId: String
  var kind: GlobalMemoryCandidateKind
  var temporalState: GlobalMemoryTemporalState
  var risk: GlobalMemoryCandidateRisk
  var status: GlobalMemoryCandidateStatus
  var action: GlobalMemoryEvolutionAction
  var targetItemIds: [String]
  var item: GlobalWorldItem
  var reason: String
  var createdAtMillis: Int64
  var reviewedAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case id
    case sourceEventId = "source_event_id"
    case conversationId = "conversation_id"
    case kind
    case temporalState = "temporal_state"
    case risk
    case status
    case action
    case targetItemIds = "target_item_ids"
    case item
    case reason
    case createdAtMillis = "created_at_millis"
    case reviewedAtMillis = "reviewed_at_millis"
  }

  init(
    id: String,
    sourceEventId: String,
    conversationId: String,
    kind: GlobalMemoryCandidateKind,
    temporalState: GlobalMemoryTemporalState,
    risk: GlobalMemoryCandidateRisk,
    status: GlobalMemoryCandidateStatus,
    action: GlobalMemoryEvolutionAction = .create,
    targetItemIds: [String] = [],
    item: GlobalWorldItem,
    reason: String,
    createdAtMillis: Int64 = GlobalMemoryClock.nowMillis(),
    reviewedAtMillis: Int64 = 0
  ) {
    self.id = id
    self.sourceEventId = sourceEventId
    self.conversationId = conversationId
    self.kind = kind
    self.temporalState = temporalState
    self.risk = risk
    self.status = status
    self.action = action
    self.targetItemIds = targetItemIds
    self.item = item
    self.reason = reason
    self.createdAtMillis = max(createdAtMillis, 0)
    self.reviewedAtMillis = max(reviewedAtMillis, 0)
  }
}

struct GlobalMemoryInbox: Codable, Equatable {
  var candidates: [GlobalMemoryCandidate]
  var processedEventIds: [String]
  var updatedAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case candidates
    case processedEventIds = "processed_event_ids"
    case updatedAtMillis = "updated_at_millis"
  }

  init(
    candidates: [GlobalMemoryCandidate] = [],
    processedEventIds: [String] = [],
    updatedAtMillis: Int64 = 0
  ) {
    self.candidates = candidates
    self.processedEventIds = processedEventIds
    self.updatedAtMillis = max(updatedAtMillis, 0)
  }

  func pending() -> [GlobalMemoryCandidate] {
    candidates
      .filter { [.pendingReview, .conflicted].contains($0.status) }
      .sorted { $0.createdAtMillis > $1.createdAtMillis }
  }
}

struct GlobalMemoryTemporalSnapshot: Codable, Equatable {
  var current: [GlobalWorldItem]
  var historical: [GlobalWorldItem]
  var planned: [GlobalWorldItem]
  var deprecated: [GlobalWorldItem]
  var conflicted: [GlobalWorldItem]
  var pending: [GlobalWorldItem]
  var pendingCandidates: [GlobalMemoryCandidate]
  var conflictedCandidates: [GlobalMemoryCandidate]

  enum CodingKeys: String, CodingKey {
    case current
    case historical
    case planned
    case deprecated
    case conflicted
    case pending
    case pendingCandidates = "pending_candidates"
    case conflictedCandidates = "conflicted_candidates"
  }

  init(
    current: [GlobalWorldItem] = [],
    historical: [GlobalWorldItem] = [],
    planned: [GlobalWorldItem] = [],
    deprecated: [GlobalWorldItem] = [],
    conflicted: [GlobalWorldItem] = [],
    pending: [GlobalWorldItem] = [],
    pendingCandidates: [GlobalMemoryCandidate] = [],
    conflictedCandidates: [GlobalMemoryCandidate] = []
  ) {
    self.current = current
    self.historical = historical
    self.planned = planned
    self.deprecated = deprecated
    self.conflicted = conflicted
    self.pending = pending
    self.pendingCandidates = pendingCandidates
    self.conflictedCandidates = conflictedCandidates
  }

  func accepted(_ state: GlobalMemoryTemporalState) -> [GlobalWorldItem] {
    switch state {
    case .current: return current
    case .historical: return historical
    case .planned: return planned
    case .deprecated: return deprecated
    case .conflicted: return conflicted
    case .pending: return pending
    }
  }

  func count(_ state: GlobalMemoryTemporalState) -> Int {
    accepted(state).count + {
      switch state {
      case .pending: return pendingCandidates.count
      case .conflicted: return conflictedCandidates.count
      default: return 0
      }
    }()
  }
}

enum GlobalMemoryTemporalPolicy {
  static func classify(_ item: GlobalWorldItem) -> GlobalMemoryTemporalState {
    switch item.status {
    case .superseded: return .deprecated
    case .completed: return .historical
    case .conflicted: return .conflicted
    case .active: return item.temporalState
    }
  }

  static func snapshot(world: PersonalWorldModel, inbox: GlobalMemoryInbox) -> GlobalMemoryTemporalSnapshot {
    let grouped = Dictionary(grouping: world.items, by: classify)
    return GlobalMemoryTemporalSnapshot(
      current: sorted(grouped[.current] ?? []),
      historical: sorted(grouped[.historical] ?? []),
      planned: sorted(grouped[.planned] ?? []),
      deprecated: sorted(grouped[.deprecated] ?? []),
      conflicted: sorted(grouped[.conflicted] ?? []),
      pending: sorted(grouped[.pending] ?? []),
      pendingCandidates: inbox.candidates
        .filter { $0.status == .pendingReview }
        .sorted { $0.createdAtMillis > $1.createdAtMillis },
      conflictedCandidates: inbox.candidates
        .filter { $0.status == .conflicted }
        .sorted { $0.createdAtMillis > $1.createdAtMillis }
    )
  }

  private static func sorted(_ items: [GlobalWorldItem]) -> [GlobalWorldItem] {
    items.sorted { $0.lastSeenAtMillis > $1.lastSeenAtMillis }
  }
}

struct GlobalUnderstanding: Codable, Equatable {
  var eventId: String
  var topic: String
  var project: String
  var relatedTopics: Set<String>
  var intent: String
  var entities: Set<String>
  var goalCandidates: [String]
  var taskCandidates: [String]
  var decisionCandidates: [String]
  var preferenceCandidates: [String]
  var riskCandidates: [String]
  var opportunityCandidates: [String]
  var crossConversationIds: Set<String>
  var complexity: Double
  var urgency: Double
  var novelty: Double
  var uncertainty: Double
  var externalResearchUseful: Bool
  var durableFollowUpUseful: Bool

  init(
    eventId: String = "",
    topic: String = "",
    project: String = "",
    relatedTopics: Set<String> = [],
    intent: String = "",
    entities: Set<String> = [],
    goalCandidates: [String] = [],
    taskCandidates: [String] = [],
    decisionCandidates: [String] = [],
    preferenceCandidates: [String] = [],
    riskCandidates: [String] = [],
    opportunityCandidates: [String] = [],
    crossConversationIds: Set<String> = [],
    complexity: Double = 0,
    urgency: Double = 0,
    novelty: Double = 0.5,
    uncertainty: Double = 0,
    externalResearchUseful: Bool = false,
    durableFollowUpUseful: Bool = false
  ) {
    self.eventId = eventId
    self.topic = Self.clean(topic, limit: 160)
    self.project = Self.clean(project, limit: 160)
    self.relatedTopics = Set(Self.cleanArray(Array(relatedTopics), limit: 16, itemLimit: 160))
    self.intent = Self.clean(intent, limit: 120)
    self.entities = Set(Self.cleanArray(Array(entities), limit: 48, itemLimit: 160))
    self.goalCandidates = Self.cleanArray(goalCandidates, limit: 16, itemLimit: 1_000)
    self.taskCandidates = Self.cleanArray(taskCandidates, limit: 32, itemLimit: 1_000)
    self.decisionCandidates = Self.cleanArray(decisionCandidates, limit: 16, itemLimit: 1_000)
    self.preferenceCandidates = Self.cleanArray(preferenceCandidates, limit: 16, itemLimit: 1_000)
    self.riskCandidates = Self.cleanArray(riskCandidates, limit: 16, itemLimit: 1_000)
    self.opportunityCandidates = Self.cleanArray(opportunityCandidates, limit: 16, itemLimit: 1_000)
    self.crossConversationIds = Set(Self.cleanArray(Array(crossConversationIds), limit: 32, itemLimit: 160))
    self.complexity = min(max(complexity, 0), 1)
    self.urgency = min(max(urgency, 0), 1)
    self.novelty = min(max(novelty, 0), 1)
    self.uncertainty = min(max(uncertainty, 0), 1)
    self.externalResearchUseful = externalResearchUseful
    self.durableFollowUpUseful = durableFollowUpUseful
  }

  enum CodingKeys: String, CodingKey {
    case eventId
    case topic
    case project
    case relatedTopics
    case intent
    case entities
    case goalCandidates
    case taskCandidates
    case decisionCandidates
    case preferenceCandidates
    case riskCandidates
    case opportunityCandidates
    case crossConversationIds
    case complexity
    case urgency
    case novelty
    case uncertainty
    case externalResearchUseful
    case durableFollowUpUseful
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      eventId: try container.decodeIfPresent(String.self, forKey: .eventId) ?? "",
      topic: try container.decodeIfPresent(String.self, forKey: .topic) ?? "",
      project: try container.decodeIfPresent(String.self, forKey: .project) ?? "",
      relatedTopics: try container.decodeIfPresent(Set<String>.self, forKey: .relatedTopics) ?? [],
      intent: try container.decodeIfPresent(String.self, forKey: .intent) ?? "",
      entities: try container.decodeIfPresent(Set<String>.self, forKey: .entities) ?? [],
      goalCandidates: try container.decodeIfPresent([String].self, forKey: .goalCandidates) ?? [],
      taskCandidates: try container.decodeIfPresent([String].self, forKey: .taskCandidates) ?? [],
      decisionCandidates: try container.decodeIfPresent([String].self, forKey: .decisionCandidates) ?? [],
      preferenceCandidates: try container.decodeIfPresent([String].self, forKey: .preferenceCandidates) ?? [],
      riskCandidates: try container.decodeIfPresent([String].self, forKey: .riskCandidates) ?? [],
      opportunityCandidates: try container.decodeIfPresent([String].self, forKey: .opportunityCandidates) ?? [],
      crossConversationIds: try container.decodeIfPresent(Set<String>.self, forKey: .crossConversationIds) ?? [],
      complexity: try container.decodeIfPresent(Double.self, forKey: .complexity) ?? 0,
      urgency: try container.decodeIfPresent(Double.self, forKey: .urgency) ?? 0,
      novelty: try container.decodeIfPresent(Double.self, forKey: .novelty) ?? 0.5,
      uncertainty: try container.decodeIfPresent(Double.self, forKey: .uncertainty) ?? 0,
      externalResearchUseful: try container.decodeIfPresent(Bool.self, forKey: .externalResearchUseful) ?? false,
      durableFollowUpUseful: try container.decodeIfPresent(Bool.self, forKey: .durableFollowUpUseful) ?? false
    )
  }

  private static func cleanArray(
    _ values: [String],
    limit: Int,
    itemLimit: Int
  ) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values {
      let clean = clean(value, limit: itemLimit)
      let key = GlobalAgentText.normalize(clean)
      guard !clean.isEmpty, seen.insert(key).inserted else { continue }
      result.append(clean)
      if result.count >= limit { break }
    }
    return result
  }

  private static func clean(_ value: String, limit: Int) -> String {
    String(value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .prefix(limit))
  }
}

enum GlobalMemoryNamespacePolicy {
  static func resolve(
    event: GlobalConversationEvent,
    understanding: GlobalUnderstanding,
    kind: GlobalWorldItemKind,
    layer: GlobalWorldLayer
  ) -> GlobalMemoryNamespaceRef {
    if let explicit = parseExplicit(event.metadata["memory_namespace"]) {
      let explicitScope = event.metadata["memory_namespace_id"]?.nonEmpty ?? explicit.scopeId
      return GlobalMemoryNamespaceRef(namespace: explicit.namespace, scopeId: explicitScope)
    }

    let memoryKind = event.metadata["memory_kind"].map { AgentMemoryKind.fromWireValue($0) }
    let namespace: GlobalMemoryNamespace
    if authorizationEvents.contains(event.type) || memoryKind == .safety {
      namespace = .security
    } else if isDeviceEvidence(event) {
      namespace = .device
    } else if memoryKind.map({ [.identity, .contact, .preference].contains($0) }) == true || kind == .preference || layer == .user {
      namespace = .user
    } else if memoryKind.map({ [.task, .workflow].contains($0) }) == true ||
      event.type == .taskUpdated ||
      [.goal, .task].contains(kind) ||
      !understanding.project.isEmpty {
      namespace = .project
    } else {
      namespace = .general
    }
    return GlobalMemoryNamespaceRef(namespace: namespace, scopeId: scopeId(namespace: namespace, event: event, understanding: understanding))
  }

  static func same(_ left: GlobalWorldItem, _ right: GlobalWorldItem) -> Bool {
    left.memoryNamespaceKey == right.memoryNamespaceKey
  }

  static func itemKey(_ item: GlobalWorldItem) -> String {
    "\(item.memoryNamespaceKey)\u{0000}\(item.stableKey)"
  }

  static func normalizeScope(_ value: String) -> String {
    let filtered = value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: #"[^\p{L}\p{N}._-]+"#, with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return String(filtered.prefix(maxScopeLength))
  }

  private static func parseExplicit(_ value: String?) -> GlobalMemoryNamespaceRef? {
    let clean = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.isEmpty { return nil }
    let parts = clean.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard let first = parts.first,
          let namespace = GlobalMemoryNamespace(rawValue: String(first).uppercased()) else {
      return nil
    }
    return GlobalMemoryNamespaceRef(
      namespace: namespace,
      scopeId: parts.count > 1 ? String(parts[1]) : ""
    )
  }

  private static func scopeId(
    namespace: GlobalMemoryNamespace,
    event: GlobalConversationEvent,
    understanding: GlobalUnderstanding
  ) -> String {
    let keys: [String]
    switch namespace {
    case .user: keys = ["user_id", "profile_id"]
    case .project: keys = ["project_id", "workspace_id", "repository_id"]
    case .device: keys = ["device_id", "target_device_id", "resource_id_hash", "client_route_id"]
    case .security: keys = ["policy_id", "authorization_id"]
    case .general: keys = []
    }
    let explicit = keys.compactMap { event.metadata[$0]?.nonEmpty }.first ?? ""
    let inferred: String
    switch namespace {
    case .project:
      inferred = understanding.project.nonEmpty ??
        projectName("\(event.conversationTitle) \(understanding.topic) \(event.content)").nonEmpty ??
        "default"
    case .device: inferred = "local"
    case .user: inferred = "self"
    case .security: inferred = "policy"
    case .general: inferred = ""
    }
    return normalizeScope(explicit.nonEmpty ?? inferred)
  }

  private static func isDeviceEvidence(_ event: GlobalConversationEvent) -> Bool {
    let resourceKind = (event.metadata["resource_kind"] ?? "").lowercased()
    if deviceResourceKinds.contains(resourceKind) || resourceKind.hasSuffix("_device") {
      return true
    }
    let toolKey = (event.metadata["tool_key"] ?? "").lowercased()
    if deviceToolPrefixes.contains(where: { toolKey.hasPrefix($0) }) {
      return true
    }
    return deviceMetadataKeys.contains { event.metadata[$0]?.nonEmpty != nil }
  }

  private static func projectName(_ value: String) -> String {
    firstMatch(value, pattern: #"(?i)(?:\bproject\s+|\u9879\u76ee\s*)([\p{L}\p{N}_.-]{2,64})"#)
  }

  private static func firstMatch(_ value: String, pattern: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
          match.numberOfRanges > 1,
          let range = Range(match.range(at: 1), in: value) else {
      return ""
    }
    return String(value[range])
  }

  private static let authorizationEvents: Set<GlobalConversationEventType> = [
    .authorizationGranted,
    .authorizationRevoked,
    .authorizationPolicyChanged
  ]
  private static let deviceResourceKinds: Set<String> = [
    "android_device",
    "custom_device",
    "home_assistant",
    "phone",
    "smart_device"
  ]
  private static let deviceToolPrefixes = [
    "android.",
    "battery.",
    "bluetooth.",
    "camera.",
    "device.",
    "location.",
    "nfc.",
    "phone.",
    "sensor.",
    "telephony.",
    "wifi."
  ]
  private static let deviceMetadataKeys = [
    "device_id",
    "target_device_id",
    "client_route_id"
  ]
  private static let maxScopeLength = 96
}

enum GlobalMemoryQueryType: String, Codable, CaseIterable, Identifiable {
  case projectState = "PROJECT_STATE"
  case deviceCapability = "DEVICE_CAPABILITY"
  case historicalDecision = "HISTORICAL_DECISION"
  case personalIdentity = "PERSONAL_IDENTITY"
  case personalPreference = "PERSONAL_PREFERENCE"
  case securityState = "SECURITY_STATE"
  case longTermGoal = "LONG_TERM_GOAL"
  case toolEvidence = "TOOL_EVIDENCE"
  case relationship = "RELATIONSHIP"
  case general = "GENERAL"

  var id: String { rawValue }
}

enum GlobalMemoryTemporalQueryScope: String, Codable, CaseIterable, Identifiable {
  case current = "CURRENT"
  case history = "HISTORY"
  case currentAndHistory = "CURRENT_AND_HISTORY"

  var id: String { rawValue }
}

struct GlobalMemoryQueryPlan: Codable, Equatable {
  var type: GlobalMemoryQueryType
  var preferredKinds: Set<GlobalWorldItemKind>
  var preferredLayers: Set<GlobalWorldLayer>
  var includeHistorical: Bool
  var graphHops: Int
  var maximumWorldItems: Int
  var maximumGraphNodes: Int
  var types: [GlobalMemoryQueryType]
  var temporalScope: GlobalMemoryTemporalQueryScope
  var preferredRelationKinds: Set<GlobalEntityRelationKind>
  var preferredNamespaces: Set<GlobalMemoryNamespace>

  enum CodingKeys: String, CodingKey {
    case type
    case preferredKinds = "preferred_kinds"
    case preferredLayers = "preferred_layers"
    case includeHistorical = "include_historical"
    case graphHops = "graph_hops"
    case maximumWorldItems = "maximum_world_items"
    case maximumGraphNodes = "maximum_graph_nodes"
    case types
    case temporalScope = "temporal_scope"
    case preferredRelationKinds = "preferred_relation_kinds"
    case preferredNamespaces = "preferred_namespaces"
  }
}

enum GlobalMemoryQueryPlanner {
  static func plan(_ query: String) -> GlobalMemoryQueryPlan {
    let normalized = GlobalAgentText.normalize(query)
    var types: [GlobalMemoryQueryType] = []
    appendIfContains(.historicalDecision, normalized, historicalTerms, to: &types)
    appendIfContains(.relationship, normalized, relationshipTerms, to: &types)
    appendIfContains(.deviceCapability, normalized, deviceTerms, to: &types)
    appendIfContains(.personalIdentity, normalized, identityTerms, to: &types)
    appendIfContains(.personalPreference, normalized, preferenceTerms, to: &types)
    appendIfContains(.securityState, normalized, securityTerms, to: &types)
    appendIfContains(.longTermGoal, normalized, goalTerms, to: &types)
    appendIfContains(.toolEvidence, normalized, toolTerms, to: &types)
    appendIfContains(.projectState, normalized, projectTerms, to: &types)
    if types.isEmpty { types.append(.general) }

    let components = types.map(planFor)
    let temporalScope: GlobalMemoryTemporalQueryScope
    if !types.contains(.historicalDecision) {
      temporalScope = .current
    } else if containsAny(normalized, currentOrComparisonTerms) {
      temporalScope = .currentAndHistory
    } else {
      temporalScope = .history
    }

    return GlobalMemoryQueryPlan(
      type: types[0],
      preferredKinds: Set(components.flatMap { Array($0.preferredKinds) }),
      preferredLayers: Set(components.flatMap { Array($0.preferredLayers) }),
      includeHistorical: temporalScope != .current,
      graphHops: components.map(\.graphHops).max() ?? 2,
      maximumWorldItems: components.map(\.maximumWorldItems).max() ?? 16,
      maximumGraphNodes: components.map(\.maximumGraphNodes).max() ?? 18,
      types: types,
      temporalScope: temporalScope,
      preferredRelationKinds: relationKinds(normalized),
      preferredNamespaces: Set(types.flatMap { Array(namespaces(for: $0)) })
    )
  }

  private static func planFor(_ type: GlobalMemoryQueryType) -> GlobalMemoryQueryPlan {
    switch type {
    case .projectState:
      return plan(type, [.state, .task, .decision, .goal], [.topic, .conversation], historical: false, hops: 2, worldItems: 18, graphNodes: 20)
    case .deviceCapability:
      return plan(type, [.fact, .state, .decision], [.user, .topic, .realtime], historical: false, hops: 3, worldItems: 16, graphNodes: 28)
    case .historicalDecision:
      return plan(type, [.decision, .state, .fact], [.topic, .user, .conversation], historical: true, hops: 2, worldItems: 24, graphNodes: 24)
    case .personalIdentity:
      return plan(type, [.fact, .state, .preference], [.user], historical: false, hops: 2, worldItems: 12, graphNodes: 16)
    case .personalPreference:
      return plan(type, [.preference, .decision], [.user], historical: false, hops: 1, worldItems: 12, graphNodes: 12)
    case .securityState:
      return plan(type, [.risk, .decision, .state, .fact], [.user, .topic, .realtime], historical: false, hops: 2, worldItems: 14, graphNodes: 18)
    case .longTermGoal:
      return plan(type, [.goal, .task, .state], [.user, .topic], historical: false, hops: 2, worldItems: 18, graphNodes: 20)
    case .toolEvidence:
      return plan(type, [.fact, .state, .task], [.realtime, .conversation, .topic], historical: false, hops: 1, worldItems: 14, graphNodes: 14)
    case .relationship:
      return plan(type, [.fact, .state, .preference], [.user, .topic], historical: false, hops: 3, worldItems: 18, graphNodes: 32)
    case .general:
      return plan(type, Set(GlobalWorldItemKind.allCases), [.user, .topic, .conversation], historical: false, hops: 2, worldItems: 16, graphNodes: 18)
    }
  }

  private static func plan(
    _ type: GlobalMemoryQueryType,
    _ kinds: Set<GlobalWorldItemKind>,
    _ layers: Set<GlobalWorldLayer>,
    historical: Bool,
    hops: Int,
    worldItems: Int,
    graphNodes: Int
  ) -> GlobalMemoryQueryPlan {
    GlobalMemoryQueryPlan(
      type: type,
      preferredKinds: kinds,
      preferredLayers: layers,
      includeHistorical: historical,
      graphHops: hops,
      maximumWorldItems: worldItems,
      maximumGraphNodes: graphNodes,
      types: [type],
      temporalScope: historical ? .currentAndHistory : .current,
      preferredRelationKinds: [],
      preferredNamespaces: []
    )
  }

  private static func appendIfContains(
    _ type: GlobalMemoryQueryType,
    _ value: String,
    _ terms: [String],
    to types: inout [GlobalMemoryQueryType]
  ) {
    if containsAny(value, terms) && !types.contains(type) {
      types.append(type)
    }
  }

  private static func containsAny(_ value: String, _ terms: [String]) -> Bool {
    terms.contains { term in
      if term.unicodeScalars.contains(where: { $0.value > 0x7F }) {
        return value.contains(term)
      }
      let pattern = "(^|[^a-z0-9_])\(NSRegularExpression.escapedPattern(for: term))($|[^a-z0-9_])"
      return value.range(of: pattern, options: .regularExpression) != nil
    }
  }

  private static func namespaces(for type: GlobalMemoryQueryType) -> Set<GlobalMemoryNamespace> {
    switch type {
    case .projectState, .longTermGoal:
      return [.project]
    case .deviceCapability:
      return [.device]
    case .personalIdentity, .personalPreference:
      return [.user]
    case .securityState:
      return [.security]
    case .toolEvidence:
      return [.project, .device, .general]
    case .historicalDecision, .relationship, .general:
      return []
    }
  }

  private static func relationKinds(_ value: String) -> Set<GlobalEntityRelationKind> {
    var kinds = Set<GlobalEntityRelationKind>()
    if containsAny(value, ownsTerms) { kinds.insert(.owns) }
    if containsAny(value, usesTerms) { kinds.insert(.uses) }
    if containsAny(value, supportsTerms) { kinds.insert(.supports) }
    if containsAny(value, componentTerms) { kinds.insert(.hasComponent) }
    if containsAny(value, stateTerms) { kinds.insert(.hasState) }
    if containsAny(value, nameTerms) { kinds.insert(.namedAs) }
    if containsAny(value, dependencyTerms) { kinds.insert(.dependsOn) }
    if containsAny(value, connectionTerms) { kinds.insert(.connectedTo) }
    if containsAny(value, preferenceRelationTerms) { kinds.insert(.prefers) }
    if containsAny(value, removalTerms) { kinds.insert(.removed) }
    return kinds
  }

  private static let historicalTerms = [
    "previous", "previously", "earlier", "prior", "what happened before", "what was before",
    "historical", "history", "used to", "decision",
    "\u{4e4b}\u{524d}", "\u{4ee5}\u{524d}", "\u{66fe}\u{7ecf}", "\u{5386}\u{53f2}", "\u{51b3}\u{5b9a}", "\u{6539}\u{53e3}"
  ]
  private static let currentOrComparisonTerms = [
    "now", "current", "currently", "today", "changed", "compare", "then and now",
    "\u{73b0}\u{5728}", "\u{5f53}\u{524d}", "\u{4eca}\u{5929}", "\u{6539}\u{4e86}", "\u{53d8}\u{5316}", "\u{5bf9}\u{6bd4}", "\u{5f53}\u{65f6}\u{548c}\u{73b0}\u{5728}"
  ]
  private static let deviceTerms = [
    "device", "phone", "android", "battery", "chip", "ram", "gpu", "npu", "model", "runtime",
    "\u{8bbe}\u{5907}", "\u{624b}\u{673a}", "\u{7535}\u{6c60}", "\u{82af}\u{7247}", "\u{5185}\u{5b58}", "\u{578b}\u{53f7}", "\u{672c}\u{673a}"
  ]
  private static let preferenceTerms = [
    "prefer", "preference", "favorite", "default style", "my style",
    "\u{504f}\u{597d}", "\u{559c}\u{6b22}", "\u{9ed8}\u{8ba4}", "\u{6211}\u{7684}\u{98ce}\u{683c}"
  ]
  private static let identityTerms = [
    "who am i", "my identity", "my name", "my profile", "about me", "account owner",
    "\u{6211}\u{662f}\u{8c01}", "\u{6211}\u{7684}\u{8eab}\u{4efd}", "\u{6211}\u{7684}\u{540d}\u{5b57}", "\u{6211}\u{7684}\u{8d44}\u{6599}", "\u{5173}\u{4e8e}\u{6211}"
  ]
  private static let securityTerms = [
    "security", "privacy", "permission", "authorization", "trust", "trusted device", "safety policy",
    "\u{5b89}\u{5168}", "\u{9690}\u{79c1}", "\u{6743}\u{9650}", "\u{6388}\u{6743}", "\u{4fe1}\u{4efb}", "\u{53ef}\u{4fe1}\u{8bbe}\u{5907}", "\u{5b89}\u{5168}\u{7b56}\u{7565}"
  ]
  private static let goalTerms = [
    "goal", "objective", "roadmap", "long term", "long-term", "next milestone",
    "\u{76ee}\u{6807}", "\u{8def}\u{7ebf}\u{56fe}", "\u{957f}\u{671f}", "\u{91cc}\u{7a0b}\u{7891}", "\u{4e0b}\u{4e00}\u{6b65}"
  ]
  private static let toolTerms = [
    "tool", "command", "result", "output", "run", "terminal", "log",
    "\u{5de5}\u{5177}", "\u{547d}\u{4ee4}", "\u{7ed3}\u{679c}", "\u{8f93}\u{51fa}", "\u{65e5}\u{5fd7}", "\u{8fd0}\u{884c}"
  ]
  private static let projectTerms = [
    "project", "task", "feature", "bug", "build", "release",
    "\u{9879}\u{76ee}", "\u{4efb}\u{52a1}", "\u{529f}\u{80fd}", "\u{7f3a}\u{9677}", "\u{6784}\u{5efa}", "\u{53d1}\u{5e03}"
  ]
  private static let relationshipTerms = [
    "relationship", "related", "connected", "depend on", "depends on", "uses", "support", "supports", "belongs to", "paired",
    "owns", "contains", "component", "renamed", "state is", "status is",
    "\u{5173}\u{7cfb}", "\u{76f8}\u{5173}", "\u{8fde}\u{63a5}", "\u{4f9d}\u{8d56}", "\u{4f7f}\u{7528}", "\u{652f}\u{6301}", "\u{5c5e}\u{4e8e}", "\u{914d}\u{5bf9}",
    "\u{62e5}\u{6709}", "\u{5305}\u{542b}", "\u{7ec4}\u{6210}", "\u{66f4}\u{540d}", "\u{72b6}\u{6001}\u{4e3a}"
  ]
  private static let ownsTerms = ["owns", "owned by", "\u{62e5}\u{6709}", "\u{5c5e}\u{4e8e}"]
  private static let usesTerms = ["uses", "using", "used by", "use of", "\u{4f7f}\u{7528}"]
  private static let supportsTerms = ["supports", "support", "\u{652f}\u{6301}"]
  private static let componentTerms = ["contains", "component", "composed of", "\u{5305}\u{542b}", "\u{7ec4}\u{6210}"]
  private static let stateTerms = ["state is", "status is", "current state", "\u{72b6}\u{6001}\u{4e3a}", "\u{5f53}\u{524d}\u{72b6}\u{6001}"]
  private static let nameTerms = ["renamed", "named as", "called", "\u{66f4}\u{540d}", "\u{547d}\u{540d}", "\u{53eb}\u{4ec0}\u{4e48}"]
  private static let dependencyTerms = ["depend on", "depends on", "requires", "\u{4f9d}\u{8d56}", "\u{9700}\u{8981}"]
  private static let connectionTerms = ["connected", "paired", "\u{8fde}\u{63a5}", "\u{914d}\u{5bf9}"]
  private static let preferenceRelationTerms = ["prefers", "preference", "\u{504f}\u{597d}", "\u{559c}\u{6b22}"]
  private static let removalTerms = ["removed", "deleted", "deprecated", "\u{79fb}\u{9664}", "\u{5220}\u{9664}", "\u{5e9f}\u{5f03}"]
}

enum GlobalMemoryClock {
  static func nowMillis() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }
}

extension GlobalConversationEvent {
  var evidenceRoots: Set<String> {
    let roots = causalEventIds.filter { !$0.isEmpty }
    if roots.isEmpty { return [id] }
    return Set(roots)
  }

  var evidenceRef: GlobalEvidenceRef {
    GlobalEvidenceRef(
      eventId: id,
      causalEventIds: evidenceRoots,
      conversationId: conversationId,
      timestampMillis: timestampMillis
    )
  }

  var effectiveRetractions: Set<String> {
    var retractions = Set(retractedEventIds.filter { !$0.isEmpty })
    if let deleted = metadata["deleted_event_id"]?.nonEmpty {
      retractions.insert(deleted)
    }
    if let superseded = metadata["superseded_event_id"]?.nonEmpty {
      retractions.insert(superseded)
    }
    metadata["superseded_event_ids"]?
      .split(separator: ",")
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .forEach { retractions.insert($0) }
    return retractions
  }
}

extension GlobalAgentText {
  static func tokens(_ value: String) -> Set<String> {
    let normalized = normalize(value)
    var tokens = Set(
      normalized
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.count >= 2 }
    )
    let cjk = normalized
      .map(String.init)
      .filter { character in
        character.unicodeScalars.allSatisfy { (0x3400...0x9FFF).contains($0.value) }
      }
    if cjk.count >= 2 {
      for index in 0..<(cjk.count - 1) {
        tokens.insert(cjk[index] + cjk[index + 1])
      }
    }
    return tokens
  }

  static func overlap(_ left: Set<String>, _ right: Set<String>) -> Double {
    if left.isEmpty || right.isEmpty { return 0 }
    let intersection = left.intersection(right).count
    return Double(intersection) / Double(max(min(left.count, right.count), 1))
  }
}
