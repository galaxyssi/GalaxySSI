import Foundation

enum GlobalMemoryEvolutionOutcome: String, Codable, CaseIterable, Identifiable {
  case applied = "APPLIED"
  case waitingReview = "WAITING_REVIEW"
  case conflicted = "CONFLICTED"
  case privateBlocked = "PRIVATE_BLOCKED"
  case approved = "APPROVED"
  case rejected = "REJECTED"

  var id: String { rawValue }
}

struct GlobalMemoryEvolutionRecord: Codable, Equatable, Identifiable {
  var id: String
  var sourceEventId: String
  var conversationId: String
  var candidateId: String
  var kind: GlobalMemoryCandidateKind
  var action: GlobalMemoryEvolutionAction
  var outcome: GlobalMemoryEvolutionOutcome
  var temporalState: GlobalMemoryTemporalState
  var subject: String
  var targetItemIds: [String]
  var resultingItemId: String
  var evidenceCount: Int
  var createdAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case id
    case sourceEventId = "source_event_id"
    case conversationId = "conversation_id"
    case candidateId = "candidate_id"
    case kind
    case action
    case outcome
    case temporalState = "temporal_state"
    case subject
    case targetItemIds = "target_item_ids"
    case resultingItemId = "resulting_item_id"
    case evidenceCount = "evidence_count"
    case createdAtMillis = "created_at_millis"
  }

  init(
    id: String,
    sourceEventId: String,
    conversationId: String,
    candidateId: String = "",
    kind: GlobalMemoryCandidateKind,
    action: GlobalMemoryEvolutionAction,
    outcome: GlobalMemoryEvolutionOutcome,
    temporalState: GlobalMemoryTemporalState,
    subject: String,
    targetItemIds: [String] = [],
    resultingItemId: String = "",
    evidenceCount: Int = 0,
    createdAtMillis: Int64 = GlobalMemoryClock.nowMillis()
  ) {
    self.id = String(id.prefix(160))
    self.sourceEventId = String(sourceEventId.prefix(240))
    self.conversationId = String(conversationId.prefix(240))
    self.candidateId = String(candidateId.prefix(160))
    self.kind = kind
    self.action = action
    self.outcome = outcome
    self.temporalState = temporalState
    self.subject = GlobalMemoryEvolutionPolicy.compact(subject, maximum: 160)
    self.targetItemIds = Array(targetItemIds.filter { !$0.isEmpty }.prefix(12))
    self.resultingItemId = String(resultingItemId.prefix(160))
    self.evidenceCount = max(evidenceCount, 0)
    self.createdAtMillis = max(createdAtMillis, 0)
  }
}

struct GlobalMemorySupersessionEdge: Codable, Equatable, Hashable {
  var previousItemId: String
  var replacementItemId: String

  enum CodingKeys: String, CodingKey {
    case previousItemId = "previous_item_id"
    case replacementItemId = "replacement_item_id"
  }
}

struct GlobalMemorySupersessionTrace: Codable, Equatable {
  var items: [GlobalWorldItem]
  var edges: [GlobalMemorySupersessionEdge]
  var evidenceEventIds: [String]
  var complete: Bool

  enum CodingKeys: String, CodingKey {
    case items
    case edges
    case evidenceEventIds = "evidence_event_ids"
    case complete
  }

  init(
    items: [GlobalWorldItem] = [],
    edges: [GlobalMemorySupersessionEdge] = [],
    evidenceEventIds: [String] = [],
    complete: Bool = true
  ) {
    self.items = items
    self.edges = edges
    self.evidenceEventIds = GlobalMemoryEvolutionPolicy.uniqueStrings(evidenceEventIds)
    self.complete = complete
  }
}

struct GlobalMemorySupersessionIntegrityReport: Codable, Equatable {
  var edges: [GlobalMemorySupersessionEdge]
  var violations: [String]

  var isSafe: Bool { violations.isEmpty }

  init(edges: [GlobalMemorySupersessionEdge] = [], violations: [String] = []) {
    self.edges = edges
    self.violations = GlobalMemoryEvolutionPolicy.uniqueStrings(violations)
  }

  func requireSafe() throws {
    if !isSafe {
      throw GlobalMemoryEvolutionPolicyError.unsafeSupersession(violations)
    }
  }
}

struct GlobalMemoryInboxIsolationReport: Codable, Equatable {
  var violations: [String]

  var isSafe: Bool { violations.isEmpty }

  init(violations: [String] = []) {
    self.violations = Array(GlobalMemoryEvolutionPolicy.uniqueStrings(violations).prefix(40))
  }

  func requireSafe() throws {
    if !isSafe {
      throw GlobalMemoryEvolutionPolicyError.unsafeInboxIsolation(violations)
    }
  }
}

enum GlobalMemoryEvolutionPolicyError: Error, Equatable {
  case unsafeSupersession([String])
  case unsafeInboxIsolation([String])
}

enum GlobalMemorySupersessionPolicy {
  static func inspect(world: PersonalWorldModel) -> GlobalMemorySupersessionIntegrityReport {
    let byId = world.items.reduce(into: [String: GlobalWorldItem]()) { result, item in
      result[item.id] = item
    }
    let graphEdges = edges(world: world)
    var violations: [String] = []

    for replacement in world.items {
      for previousId in GlobalMemoryEvolutionPolicy.uniqueStrings(replacement.supersedesItemIds).filter({ !$0.isEmpty }) {
        guard let previous = byId[previousId] else {
          violations.append("missing_previous:\(previousId)")
          continue
        }
        if previous.id == replacement.id {
          violations.append("self_reference:\(replacement.id)")
        }
        if previous.supersededByItemId != replacement.id {
          violations.append("missing_reverse:\(previous.id):\(replacement.id)")
        }
        if previous.status != .superseded {
          violations.append("previous_not_superseded:\(previous.id)")
        }
        if !GlobalMemoryNamespacePolicy.same(previous, replacement) {
          violations.append("cross_namespace:\(previous.id):\(replacement.id)")
        }
      }

      if !replacement.supersededByItemId.isEmpty {
        let replacementId = replacement.supersededByItemId
        guard let successor = byId[replacementId] else {
          violations.append("missing_replacement:\(replacementId)")
          continue
        }
        if !successor.supersedesItemIds.contains(replacement.id) {
          violations.append("missing_forward:\(replacement.id):\(replacementId)")
        }
        if !GlobalMemoryNamespacePolicy.same(replacement, successor) {
          violations.append("cross_namespace:\(replacement.id):\(replacementId)")
        }
      }
    }

    if containsCycle(graphEdges) {
      violations.append("cycle")
    }
    return GlobalMemorySupersessionIntegrityReport(edges: graphEdges, violations: violations)
  }

  static func trace(world: PersonalWorldModel, itemId: String) -> GlobalMemorySupersessionTrace {
    let byId = world.items.reduce(into: [String: GlobalWorldItem]()) { result, item in
      result[item.id] = item
    }
    guard byId[itemId] != nil else {
      return GlobalMemorySupersessionTrace(complete: false)
    }

    let graphEdges = edges(world: world)
    var adjacent: [String: Set<String>] = [:]
    for edge in graphEdges {
      adjacent[edge.previousItemId, default: []].insert(edge.replacementItemId)
      adjacent[edge.replacementItemId, default: []].insert(edge.previousItemId)
    }

    var connectedIds = Set<String>()
    var orderedIds: [String] = []
    var queue = [itemId]
    while !queue.isEmpty {
      let current = queue.removeFirst()
      if !connectedIds.insert(current).inserted { continue }
      orderedIds.append(current)
      for next in adjacent[current, default: []] {
        queue.append(next)
      }
    }

    let connectedEdges = graphEdges.filter {
      connectedIds.contains($0.previousItemId) || connectedIds.contains($0.replacementItemId)
    }
    let connectedItems = orderedIds
      .compactMap { byId[$0] }
      .sorted {
        if $0.firstSeenAtMillis != $1.firstSeenAtMillis {
          return $0.firstSeenAtMillis < $1.firstSeenAtMillis
        }
        return $0.lastSeenAtMillis < $1.lastSeenAtMillis
      }
    let complete = connectedEdges.allSatisfy {
      byId[$0.previousItemId] != nil && byId[$0.replacementItemId] != nil
    } && !containsCycle(connectedEdges)

    return GlobalMemorySupersessionTrace(
      items: connectedItems,
      edges: connectedEdges,
      evidenceEventIds: connectedItems.flatMap(\.evidenceEventIds).filter { !$0.isEmpty },
      complete: complete
    )
  }

  private static func edges(world: PersonalWorldModel) -> [GlobalMemorySupersessionEdge] {
    var seen = Set<GlobalMemorySupersessionEdge>()
    var result: [GlobalMemorySupersessionEdge] = []
    for item in world.items {
      for previousId in item.supersedesItemIds where !previousId.isEmpty {
        let edge = GlobalMemorySupersessionEdge(previousItemId: previousId, replacementItemId: item.id)
        if seen.insert(edge).inserted { result.append(edge) }
      }
      if !item.supersededByItemId.isEmpty {
        let edge = GlobalMemorySupersessionEdge(previousItemId: item.id, replacementItemId: item.supersededByItemId)
        if seen.insert(edge).inserted { result.append(edge) }
      }
    }
    return result
  }

  private static func containsCycle(_ edges: [GlobalMemorySupersessionEdge]) -> Bool {
    var outgoing: [String: [String]] = [:]
    for edge in edges {
      outgoing[edge.previousItemId, default: []].append(edge.replacementItemId)
    }
    var visiting = Set<String>()
    var visited = Set<String>()

    func visit(_ itemId: String) -> Bool {
      if visiting.contains(itemId) { return true }
      if !visited.insert(itemId).inserted { return false }
      visiting.insert(itemId)
      let cycle = outgoing[itemId, default: []].contains(where: visit)
      visiting.remove(itemId)
      return cycle
    }

    return edges.contains { visit($0.previousItemId) }
  }
}

enum GlobalMemoryInboxIsolationPolicy {
  static func inspect(
    world: PersonalWorldModel,
    topicGraph: GlobalTopicProjectGraph,
    entityGraph: GlobalEntityMemoryGraph,
    inbox: GlobalMemoryInbox
  ) -> GlobalMemoryInboxIsolationReport {
    let isolatedStatuses: Set<GlobalMemoryCandidateStatus> = [.pendingReview, .conflicted, .rejected]
    let isolated = inbox.candidates.filter { isolatedStatuses.contains($0.status) }
    if isolated.isEmpty {
      return GlobalMemoryInboxIsolationReport()
    }

    let sourceEventIds = Set(isolated.map(\.sourceEventId).filter { !$0.isEmpty })
    let candidateItemIds = Set(isolated.map(\.item.id).filter { !$0.isEmpty })
    var violations: [String] = []

    for candidate in isolated where candidate.risk == .privateBlocked {
      if !candidate.item.value.isEmpty ||
        candidate.item.topic != privateCandidateTopic ||
        candidate.item.contextVisibility != .localOnly {
        violations.append("private_candidate_not_redacted:\(candidate.id)")
      }
    }

    for item in world.items where item.idIn(candidateItemIds) || item.references(sourceEventIds) {
      violations.append("world_item:\(item.id)")
    }
    for link in world.links where link.evidenceProvenance.references(sourceEventIds) {
      violations.append("world_link:\(link.id)")
    }
    for node in topicGraph.nodes where
      !Set(node.worldItemIds).isDisjoint(with: candidateItemIds) || node.references(sourceEventIds) {
      violations.append("topic_node:\(node.id)")
    }
    for relation in topicGraph.relations where relation.references(sourceEventIds) {
      violations.append("topic_relation:\(relation.id)")
    }
    for node in entityGraph.nodes where node.evidence.references(sourceEventIds) {
      violations.append("entity_node:\(node.id)")
    }
    for relation in entityGraph.relations where relation.evidence.references(sourceEventIds) {
      violations.append("entity_relation:\(relation.id)")
    }

    return GlobalMemoryInboxIsolationReport(violations: violations)
  }

  private static let privateCandidateTopic = "Private memory candidate"
}

enum GlobalMemoryEvolutionPolicy {
  static func approve(
    world: PersonalWorldModel,
    inbox: GlobalMemoryInbox,
    candidateId: String,
    nowMillis: Int64 = GlobalMemoryClock.nowMillis()
  ) -> (world: PersonalWorldModel, inbox: GlobalMemoryInbox) {
    guard let candidate = inbox.candidates.first(where: {
      $0.id == candidateId && [.pendingReview, .conflicted].contains($0.status)
    }) else {
      return (world, inbox)
    }

    let approvedTemporalState = resolvedTemporalState(candidate)
    let approved = reviewedCandidate(
      candidate,
      status: .approved,
      temporalState: approvedTemporalState,
      reviewedAtMillis: nowMillis
    )
    var incomingBase = approved.item
    incomingBase.status = .active
    incomingBase.temporalState = approvedTemporalState
    incomingBase.conflictGroupId = ""
    incomingBase.supersededByItemId = ""
    incomingBase.lastSeenAtMillis = max(incomingBase.lastSeenAtMillis, nowMillis)

    let strengthenTarget: GlobalWorldItem? = candidate.action == .strengthen
      ? candidate.targetItemIds.first.flatMap { targetId in world.items.first { $0.id == targetId } }
      : nil
    let replaced: [GlobalWorldItem]
    if let strengthenTarget = strengthenTarget {
      let merged = strengthened(existing: strengthenTarget, incoming: incomingBase)
      replaced = world.items
        .map { $0.id == strengthenTarget.id ? merged : $0 }
        .filter { !($0.id == incomingBase.id && $0.id != strengthenTarget.id) }
    } else {
      let supersededItemIds = world.items
        .filter { existing in
          if existing.id == approved.item.id { return false }
          let sameSubject = existing.kind == approved.item.kind &&
            GlobalMemoryNamespacePolicy.same(existing, approved.item) &&
            GlobalAgentText.overlap(
              GlobalAgentText.tokens(existing.topic),
              GlobalAgentText.tokens(approved.item.topic)
            ) >= 0.45
          return sameSubject && [.active, .conflicted].contains(existing.status)
        }
        .map(\.id)
        .prefix(maxEvolutionTargets)

      var incoming = incomingBase
      incoming.supersedesItemIds = Array(uniqueStrings(incoming.supersedesItemIds + Array(supersededItemIds)).suffix(maxEvolutionTargets))
      replaced = world.items
        .map { existing -> GlobalWorldItem in
          if incoming.supersedesItemIds.contains(existing.id) {
            var superseded = existing
            superseded.status = .superseded
            superseded.temporalState = .deprecated
            superseded.conflictGroupId = ""
            superseded.supersededByItemId = incoming.id
            return superseded
          }
          return existing
        }
        .filter { $0.id != incoming.id } + [incoming]
    }

    var updatedWorld = world
    updatedWorld.items = Array(replaced.sorted { $0.lastSeenAtMillis > $1.lastSeenAtMillis }.prefix(maxWorldItems))
    updatedWorld.updatedAtMillis = max(world.updatedAtMillis, nowMillis)

    var updatedInbox = inbox
    updatedInbox.candidates = inbox.candidates.map { $0.id == candidateId ? approved : $0 }
    updatedInbox.updatedAtMillis = max(inbox.updatedAtMillis, nowMillis)
    return (updatedWorld, updatedInbox)
  }

  static func reject(
    inbox: GlobalMemoryInbox,
    candidateId: String,
    nowMillis: Int64 = GlobalMemoryClock.nowMillis()
  ) -> GlobalMemoryInbox {
    var changed = false
    let candidates = inbox.candidates.map { candidate -> GlobalMemoryCandidate in
      if candidate.id == candidateId && [.pendingReview, .conflicted].contains(candidate.status) {
        changed = true
        return reviewedCandidate(candidate, status: .rejected, temporalState: candidate.temporalState, reviewedAtMillis: nowMillis)
      }
      return candidate
    }
    if !changed { return inbox }
    var updated = inbox
    updated.candidates = candidates
    updated.updatedAtMillis = max(inbox.updatedAtMillis, nowMillis)
    return updated
  }

  static func record(
    for candidate: GlobalMemoryCandidate,
    explicitOutcome: GlobalMemoryEvolutionOutcome? = nil,
    createdAtMillis: Int64 = -1
  ) -> GlobalMemoryEvolutionRecord {
    let outcome = explicitOutcome ?? outcome(for: candidate)
    let resultingItemId: String
    if [.waitingReview, .conflicted, .privateBlocked, .rejected].contains(outcome) {
      resultingItemId = ""
    } else if candidate.action == .strengthen {
      resultingItemId = candidate.targetItemIds.first ?? ""
    } else {
      resultingItemId = candidate.item.id
    }
    let subject: String
    if candidate.risk == .privateBlocked {
      subject = "Private memory candidate"
    } else {
      subject = compact(candidate.item.topic, maximum: 160, fallback: candidate.kind.rawValue.lowercased())
    }

    return GlobalMemoryEvolutionRecord(
      id: GlobalAgentText.stableKey("memory-evolution-record", candidate.id, outcome.rawValue),
      sourceEventId: candidate.sourceEventId,
      conversationId: candidate.conversationId,
      candidateId: candidate.id,
      kind: candidate.kind,
      action: candidate.action,
      outcome: outcome,
      temporalState: outcome == .approved ? resolvedTemporalState(candidate) : candidate.temporalState,
      subject: subject,
      targetItemIds: candidate.targetItemIds,
      resultingItemId: resultingItemId,
      evidenceCount: candidate.item.evidenceCount,
      createdAtMillis: createdAtMillis >= 0 ? createdAtMillis : candidate.createdAtMillis
    )
  }

  static func reviewRecord(
    candidate: GlobalMemoryCandidate,
    outcome: GlobalMemoryEvolutionOutcome,
    nowMillis: Int64 = GlobalMemoryClock.nowMillis()
  ) -> GlobalMemoryEvolutionRecord {
    precondition([.approved, .rejected].contains(outcome), "Review records must be approved or rejected")
    return record(for: candidate, explicitOutcome: outcome, createdAtMillis: nowMillis)
  }

  static func auditRecords(
    worldBefore: PersonalWorldModel,
    worldAfter: PersonalWorldModel,
    nowMillis: Int64
  ) -> [GlobalMemoryEvolutionRecord] {
    let afterById = worldAfter.items.reduce(into: [String: GlobalWorldItem]()) { result, item in
      result[item.id] = item
    }

    return worldBefore.items.compactMap { previous -> GlobalMemoryEvolutionRecord? in
      guard let updated = afterById[previous.id] else { return nil }
      if previous.status == updated.status && previous.temporalState == updated.temporalState {
        return nil
      }
      if updated.status != .superseded && updated.temporalState != .deprecated {
        return nil
      }
      let consolidatedInto = worldAfter.items.first {
        $0.id != updated.id &&
          $0.status == .active &&
          $0.layer == updated.layer &&
          equivalentAssertion($0, updated)
      }
      let sourceEventId = updated.evidenceProvenance
        .max { $0.timestampMillis < $1.timestampMillis }?
        .eventId
        ?? updated.evidenceEventIds.last
        ?? "memory-audit:\(updated.id)"
      let action: GlobalMemoryEvolutionAction = consolidatedInto == nil ? .supersede : .consolidate

      return GlobalMemoryEvolutionRecord(
        id: GlobalAgentText.stableKey(
          "memory-audit-record",
          updated.id,
          action.rawValue,
          updated.temporalState.rawValue,
          consolidatedInto?.id ?? "",
          String(updated.lastSeenAtMillis)
        ),
        sourceEventId: sourceEventId,
        conversationId: updated.conversationIds.first ?? "",
        kind: candidateKind(updated),
        action: action,
        outcome: .applied,
        temporalState: updated.temporalState,
        subject: compact(updated.topic, maximum: 160, fallback: updated.kind.rawValue.lowercased()),
        targetItemIds: [updated.id],
        resultingItemId: consolidatedInto?.id ?? "",
        evidenceCount: updated.evidenceCount,
        createdAtMillis: nowMillis
      )
    }
  }

  static func strengthened(existing: GlobalWorldItem, incoming: GlobalWorldItem) -> GlobalWorldItem {
    let evidence = uniqueEvidence(existing.evidenceProvenance + incoming.evidenceProvenance)
    var updated = existing
    updated.confidence = min(max(existing.confidence, incoming.confidence) + strengthenConfidenceBoost, 0.99)
    updated.evidenceCount = max(evidence.count, max(existing.evidenceCount, incoming.evidenceCount))
    updated.conversationIds = Set(uniqueStrings(Array(existing.conversationIds) + Array(incoming.conversationIds)).prefix(maxConversationsPerItem))
    updated.evidenceEventIds = evidence.map(\.eventId)
    updated.evidenceProvenance = evidence
    updated.temporalState = incoming.lastSeenAtMillis >= existing.lastSeenAtMillis ? incoming.temporalState : existing.temporalState
    updated.lastSeenAtMillis = max(existing.lastSeenAtMillis, incoming.lastSeenAtMillis)
    updated.expiresAtMillis = (existing.expiresAtMillis <= 0 || incoming.expiresAtMillis <= 0)
      ? 0
      : max(existing.expiresAtMillis, incoming.expiresAtMillis)
    return updated
  }

  static func sameSubject(_ left: GlobalWorldItem, _ right: GlobalWorldItem) -> Bool {
    if !GlobalMemoryNamespacePolicy.same(left, right) { return false }
    let leftTopicTokens = GlobalAgentText.tokens(left.topic)
    let rightTopicTokens = GlobalAgentText.tokens(right.topic)
    let topicOverlap = GlobalAgentText.overlap(leftTopicTokens, rightTopicTokens)
    let valueOverlap = GlobalAgentText.overlap(GlobalAgentText.tokens(left.value), GlobalAgentText.tokens(right.value))
    let specificTopic = min(leftTopicTokens.count, rightTopicTokens.count) >= minSpecificTopicTokens
    return valueOverlap >= 0.42 || (specificTopic && topicOverlap >= 0.58 && valueOverlap >= 0.12)
  }

  static func equivalentAssertion(_ left: GlobalWorldItem, _ right: GlobalWorldItem) -> Bool {
    if left.kind != right.kind || !sameSubject(left, right) { return false }
    let valueOverlap = GlobalAgentText.overlap(GlobalAgentText.tokens(left.value), GlobalAgentText.tokens(right.value))
    let requiredOverlap = [.preference, .decision].contains(left.kind)
      ? equivalentProtectedAssertionOverlap
      : equivalentAssertionOverlap
    return valueOverlap >= requiredOverlap && assertionPolarity(left.value) == assertionPolarity(right.value)
  }

  static func candidateKind(_ item: GlobalWorldItem) -> GlobalMemoryCandidateKind {
    switch item.kind {
    case .preference:
      return .preference
    case .decision:
      return .decision
    case .goal:
      return .goal
    case .state, .task:
      return .projectState
    default:
      return .fact
    }
  }

  static func resolvedTemporalState(_ candidate: GlobalMemoryCandidate) -> GlobalMemoryTemporalState {
    if ![.pending, .conflicted].contains(candidate.temporalState) {
      return candidate.temporalState
    }
    switch candidate.item.status {
    case .completed:
      return .historical
    case .superseded:
      return .deprecated
    case .active, .conflicted:
      return candidate.kind == .goal ? .planned : .current
    }
  }

  static func compact(_ value: String, maximum: Int, fallback: String = "") -> String {
    let clean = value
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.isEmpty {
      return String(fallback.prefix(maximum))
    }
    return String(clean.prefix(maximum))
  }

  static func uniqueStrings(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values where !value.isEmpty {
      if seen.insert(value).inserted {
        result.append(value)
      }
    }
    return result
  }

  private static func outcome(for candidate: GlobalMemoryCandidate) -> GlobalMemoryEvolutionOutcome {
    switch candidate.status {
    case .autoMerged, .superseded:
      return .applied
    case .pendingReview:
      return .waitingReview
    case .conflicted:
      return .conflicted
    case .approved:
      return .approved
    case .rejected:
      return candidate.risk == .privateBlocked ? .privateBlocked : .rejected
    }
  }

  private static func reviewedCandidate(
    _ candidate: GlobalMemoryCandidate,
    status: GlobalMemoryCandidateStatus,
    temporalState: GlobalMemoryTemporalState,
    reviewedAtMillis: Int64
  ) -> GlobalMemoryCandidate {
    GlobalMemoryCandidate(
      id: candidate.id,
      sourceEventId: candidate.sourceEventId,
      conversationId: candidate.conversationId,
      kind: candidate.kind,
      temporalState: temporalState,
      risk: candidate.risk,
      status: status,
      action: candidate.action,
      targetItemIds: candidate.targetItemIds,
      item: candidate.item,
      reason: candidate.reason,
      createdAtMillis: candidate.createdAtMillis,
      reviewedAtMillis: reviewedAtMillis
    )
  }

  private static func assertionPolarity(_ value: String) -> Int {
    let lower = value.lowercased()
    return negativeSignals.contains { lower.contains($0) } ? -1 : 1
  }

  private static func uniqueEvidence(_ values: [GlobalEvidenceRef]) -> [GlobalEvidenceRef] {
    var seen = Set<String>()
    var result: [GlobalEvidenceRef] = []
    for value in values {
      if seen.insert(value.eventId).inserted {
        result.append(value)
      }
    }
    return Array(result.suffix(maxEvidencePerItem))
  }

  private static let negativeSignals = [
    " not ", "no longer", "without", "disabled", "removed", "deleted", "failed",
    "\u{4e0d}", "\u{672a}", "\u{65e0}", "\u{5173}\u{95ed}", "\u{79fb}\u{9664}", "\u{5220}\u{9664}", "\u{5931}\u{8d25}"
  ]
  private static let equivalentAssertionOverlap = 0.64
  private static let equivalentProtectedAssertionOverlap = 0.82
  private static let minSpecificTopicTokens = 2
  private static let strengthenConfidenceBoost = 0.035
  private static let maxEvidencePerItem = 20
  private static let maxConversationsPerItem = 20
  private static let maxEvolutionTargets = 12
  private static let maxWorldItems = 1_500
}

private extension GlobalWorldItem {
  func idIn(_ ids: Set<String>) -> Bool {
    ids.contains(id)
  }

  func references(_ sourceEventIds: Set<String>) -> Bool {
    !Set(evidenceEventIds).isDisjoint(with: sourceEventIds) ||
      evidenceProvenance.references(sourceEventIds)
  }
}

private extension GlobalTopicNode {
  func references(_ sourceEventIds: Set<String>) -> Bool {
    !Set(evidenceEventIds).isDisjoint(with: sourceEventIds) ||
      evidenceProvenance.references(sourceEventIds)
  }
}

private extension GlobalTopicRelation {
  func references(_ sourceEventIds: Set<String>) -> Bool {
    !Set(evidenceEventIds).isDisjoint(with: sourceEventIds) ||
      evidenceProvenance.references(sourceEventIds)
  }
}

private extension Array where Element == GlobalEvidenceRef {
  func references(_ sourceEventIds: Set<String>) -> Bool {
    contains { evidence in
      sourceEventIds.contains(evidence.eventId) ||
        !evidence.causalEventIds.isDisjoint(with: sourceEventIds)
    }
  }
}
