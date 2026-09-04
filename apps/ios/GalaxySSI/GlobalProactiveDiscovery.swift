import Foundation

enum GlobalDiscoveryKind: String, Codable, CaseIterable, Identifiable {
  case crossTopicConflict = "CROSS_TOPIC_CONFLICT"
  case crossTopicSynthesis = "CROSS_TOPIC_SYNTHESIS"
  case materialRisk = "MATERIAL_RISK"
  case highValueOpportunity = "HIGH_VALUE_OPPORTUNITY"
  case stalledGoal = "STALLED_GOAL"

  var id: String { rawValue }
}

struct GlobalDiscoveryCandidate: Codable, Equatable {
  var stableKey: String
  var fingerprint: String
  var kind: GlobalDiscoveryKind
  var topic: String
  var summary: String
  var sourceConversationIds: Set<String>
  var causalEventIds: Set<String>
  var score: Double
  var urgency: Double
  var externalResearchUseful: Bool
  var longHorizonGoalId: String

  init(
    stableKey: String,
    fingerprint: String,
    kind: GlobalDiscoveryKind,
    topic: String,
    summary: String,
    sourceConversationIds: Set<String>,
    causalEventIds: Set<String>,
    score: Double,
    urgency: Double,
    externalResearchUseful: Bool,
    longHorizonGoalId: String = ""
  ) {
    self.stableKey = stableKey
    self.fingerprint = fingerprint
    self.kind = kind
    self.topic = topic
    self.summary = summary
    self.sourceConversationIds = sourceConversationIds
    self.causalEventIds = causalEventIds
    self.score = clamp01(score)
    self.urgency = clamp01(urgency)
    self.externalResearchUseful = externalResearchUseful
    self.longHorizonGoalId = longHorizonGoalId
  }

  enum CodingKeys: String, CodingKey {
    case stableKey = "stable_key"
    case fingerprint
    case kind
    case topic
    case summary
    case sourceConversationIds = "source_conversation_ids"
    case causalEventIds = "causal_event_ids"
    case score
    case urgency
    case externalResearchUseful = "external_research_useful"
    case longHorizonGoalId = "long_horizon_goal_id"
  }
}

struct GlobalDiscoveryRecord: Codable, Equatable {
  var stableKey: String
  var fingerprint: String
  var cognitionTaskId: String
  var emittedAtMillis: Int64

  init(
    stableKey: String,
    fingerprint: String,
    cognitionTaskId: String,
    emittedAtMillis: Int64
  ) {
    self.stableKey = String(stableKey.prefix(240))
    self.fingerprint = String(fingerprint.prefix(160))
    self.cognitionTaskId = String(cognitionTaskId.prefix(240))
    self.emittedAtMillis = max(emittedAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case stableKey = "stable_key"
    case fingerprint
    case cognitionTaskId = "cognition_task_id"
    case emittedAtMillis = "emitted_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      stableKey: try container.decodeIfPresent(String.self, forKey: .stableKey) ?? "",
      fingerprint: try container.decodeIfPresent(String.self, forKey: .fingerprint) ?? "",
      cognitionTaskId: try container.decodeIfPresent(String.self, forKey: .cognitionTaskId) ?? "",
      emittedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .emittedAtMillis) ?? 0
    )
  }
}

struct GlobalProactiveDiscoveryState: Codable, Equatable {
  var nextScanAtMillis: Int64
  var scanLeaseExpiresAtMillis: Int64
  var lastStartedAtMillis: Int64
  var lastCompletedAtMillis: Int64
  var scanSequence: Int64
  var recentEmissionTimestamps: [Int64]
  var records: [GlobalDiscoveryRecord]
  var lastError: String

  init(
    nextScanAtMillis: Int64 = 0,
    scanLeaseExpiresAtMillis: Int64 = 0,
    lastStartedAtMillis: Int64 = 0,
    lastCompletedAtMillis: Int64 = 0,
    scanSequence: Int64 = 0,
    recentEmissionTimestamps: [Int64] = [],
    records: [GlobalDiscoveryRecord] = [],
    lastError: String = ""
  ) {
    self.nextScanAtMillis = max(nextScanAtMillis, 0)
    self.scanLeaseExpiresAtMillis = max(scanLeaseExpiresAtMillis, 0)
    self.lastStartedAtMillis = max(lastStartedAtMillis, 0)
    self.lastCompletedAtMillis = max(lastCompletedAtMillis, 0)
    self.scanSequence = max(scanSequence, 0)
    self.recentEmissionTimestamps = recentEmissionTimestamps.filter { $0 > 0 }.suffix(Self.maxEmissions).map { $0 }
    self.records = records.filter {
      !$0.stableKey.isBlank && !$0.fingerprint.isBlank && !$0.cognitionTaskId.isBlank
    }.suffix(Self.maxRecords).map { $0 }
    self.lastError = String(lastError.prefix(600))
  }

  enum CodingKeys: String, CodingKey {
    case nextScanAtMillis = "next_scan_at_millis"
    case scanLeaseExpiresAtMillis = "scan_lease_expires_at_millis"
    case lastStartedAtMillis = "last_started_at_millis"
    case lastCompletedAtMillis = "last_completed_at_millis"
    case scanSequence = "scan_sequence"
    case recentEmissionTimestamps = "recent_emission_timestamps"
    case records
    case lastError = "last_error"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      nextScanAtMillis: try container.decodeIfPresent(Int64.self, forKey: .nextScanAtMillis) ?? 0,
      scanLeaseExpiresAtMillis: try container.decodeIfPresent(Int64.self, forKey: .scanLeaseExpiresAtMillis) ?? 0,
      lastStartedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .lastStartedAtMillis) ?? 0,
      lastCompletedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .lastCompletedAtMillis) ?? 0,
      scanSequence: try container.decodeIfPresent(Int64.self, forKey: .scanSequence) ?? 0,
      recentEmissionTimestamps: try container.decodeIfPresent([Int64].self, forKey: .recentEmissionTimestamps) ?? [],
      records: try container.decodeIfPresent([GlobalDiscoveryRecord].self, forKey: .records) ?? [],
      lastError: try container.decodeIfPresent(String.self, forKey: .lastError) ?? ""
    )
  }

  private static let maxRecords = 400
  private static let maxEmissions = 200
}

struct GlobalDiscoveryScanClaim: Codable, Equatable {
  var sequence: Int64
  var leaseExpiresAtMillis: Int64

  init(sequence: Int64, leaseExpiresAtMillis: Int64) {
    self.sequence = max(sequence, 0)
    self.leaseExpiresAtMillis = max(leaseExpiresAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case sequence
    case leaseExpiresAtMillis = "lease_expires_at_millis"
  }
}

struct GlobalProactiveDiscoveryCycleResult: Codable, Equatable {
  var scanned: Bool
  var candidateCount: Int
  var queuedTaskCount: Int
  var nextWakeAtMillis: Int64
  var error: String

  init(
    scanned: Bool,
    candidateCount: Int,
    queuedTaskCount: Int,
    nextWakeAtMillis: Int64,
    error: String = ""
  ) {
    self.scanned = scanned
    self.candidateCount = max(candidateCount, 0)
    self.queuedTaskCount = max(queuedTaskCount, 0)
    self.nextWakeAtMillis = max(nextWakeAtMillis, 0)
    self.error = String(error.prefix(600))
  }

  enum CodingKeys: String, CodingKey {
    case scanned
    case candidateCount = "candidate_count"
    case queuedTaskCount = "queued_task_count"
    case nextWakeAtMillis = "next_wake_at_millis"
    case error
  }
}

enum GlobalProactiveDiscoveryPolicy {
  static func scan(
    world: PersonalWorldModel,
    goals: [GlobalLongHorizonGoal],
    excludedConversationIds: Set<String>,
    nowMillis: Int64,
    topicGraph: GlobalTopicProjectGraph = GlobalTopicProjectGraph()
  ) -> [GlobalDiscoveryCandidate] {
    let eligibleItems = world.items.filter { item in
      item.contextVisibility == .shareable &&
        [.active, .conflicted].contains(item.status) &&
        (item.expiresAtMillis <= 0 || item.expiresAtMillis > nowMillis) &&
        !item.evidenceEventIds.isEmpty &&
        !item.conversationIds.isEmpty &&
        item.conversationIds.isDisjoint(with: excludedConversationIds)
    }
    var candidates: [GlobalDiscoveryCandidate] = []
    candidates.append(contentsOf: conflictCandidates(eligibleItems))
    for item in eligibleItems where item.kind == .risk && item.status == .active {
      if item.confidence >= 0.62 &&
        (item.confidence >= 0.82 || item.evidenceCount >= 2 || item.conversationIds.count >= 2) {
        candidates.append(worldItemCandidate(item, kind: .materialRisk))
      }
    }
    for item in eligibleItems where item.kind == .opportunity && item.status == .active {
      if item.confidence >= 0.72 && (item.evidenceCount >= 2 || item.conversationIds.count >= 2) {
        candidates.append(worldItemCandidate(item, kind: .highValueOpportunity))
      }
    }
    candidates.append(contentsOf: synthesisCandidates(
      graph: topicGraph,
      eligibleItems: eligibleItems,
      excludedConversationIds: excludedConversationIds
    ))
    candidates.append(contentsOf: stalledGoalCandidates(
      goals: goals,
      eligibleItems: eligibleItems,
      excludedConversationIds: excludedConversationIds,
      nowMillis: nowMillis
    ))
    return distinctByStableKey(candidates)
      .sorted {
        if $0.score != $1.score { return $0.score > $1.score }
        if $0.urgency != $1.urgency { return $0.urgency > $1.urgency }
        return $0.stableKey < $1.stableKey
      }
      .prefix(maxScanCandidates)
      .map { $0 }
  }

  static func selectForDeliberation(
    candidates: [GlobalDiscoveryCandidate],
    state: GlobalProactiveDiscoveryState,
    existingTasks: [GlobalCognitionTask],
    settings: GlobalAgentSettings,
    nowMillis: Int64,
    maxTasks: Int = 2
  ) -> [GlobalDiscoveryCandidate] {
    let emittedToday = state.recentEmissionTimestamps.filter { timestamp in
      (0...dayMillis).contains(nowMillis - timestamp)
    }.count
    let remainingBudget = max(settings.dailyDiscoveryTaskBudget - emittedToday, 0)
    if remainingBudget == 0 { return [] }
    let records = recordsByStableKey(state.records)
    let tasksById = existingTasks.reduce(into: [String: GlobalCognitionTask]()) { result, task in
      result[task.id] = task
    }
    let changedCooldown = min(intervalMillis(settings.discoveryIntervalMillis), changedFindingCooldownMillis)
    return candidates
      .filter { $0.score >= minimumDiscoveryScore }
      .filter { candidate in
        guard let record = records[candidate.stableKey] else { return true }
        if record.fingerprint != candidate.fingerprint {
          return nowMillis - record.emittedAtMillis >= changedCooldown
        }
        guard let task = tasksById[record.cognitionTaskId] else { return false }
        return task.status == .failed && nowMillis - task.updatedAtMillis >= failedTaskRetryMillis
      }
      .prefix(min(maxTasks.clamped(to: 1...maxTasksPerScan), remainingBudget))
      .map { $0 }
  }

  static func task(_ candidate: GlobalDiscoveryCandidate, nowMillis: Int64) -> GlobalCognitionTask {
    let primaryConversationId = candidate.sourceConversationIds.sorted().first ?? ""
    let kindLabel = candidate.kind.rawValue.lowercased().replacingOccurrences(of: "_", with: " ")
    let stableEventKey = GlobalAgentText.stableKey(candidate.stableKey, candidate.fingerprint)
    let event = GlobalConversationEvent(
      id: "global-discovery-event:\(stableEventKey)",
      type: .taskUpdated,
      conversationId: primaryConversationId,
      actor: .tool,
      timestampMillis: nowMillis,
      content: String((
        "Periodic Personal ASI world review found a \(kindLabel) candidate.\n" +
          candidate.summary +
          "\nEvaluate whether this is still material, identify cross-topic implications, and propose only safe, evidence-backed next actions."
      ).prefix(12_000)),
      contentRef: "encrypted://global-agent/discovery/\(candidate.stableKey)",
      conversationTitle: candidate.topic,
      topicHints: Set([candidate.topic].filter { !$0.isBlank }),
      metadata: taskMetadata(candidate),
      causalEventIds: candidate.causalEventIds
    )
    return GlobalCognitionTask(
      id: cognitionTaskId(candidate),
      sourceEvent: event,
      baselineUnderstanding: GlobalUnderstanding(topic: candidate.topic),
      baselineIntent: "proactive_world_review",
      createdAtMillis: nowMillis,
      updatedAtMillis: nowMillis
    )
  }

  static func cognitionTaskId(_ candidate: GlobalDiscoveryCandidate) -> String {
    "global-discovery:\(GlobalAgentText.stableKey(candidate.stableKey, candidate.fingerprint))"
  }

  static func shouldSurfaceResult(
    task: GlobalCognitionTask,
    userInsight: String = "",
    risks: [String] = [],
    opportunities: [String] = []
  ) -> Bool {
    task.sourceEvent.metadata["origin"] != origin ||
      !userInsight.isBlank ||
      risks.contains { !$0.isBlank } ||
      opportunities.contains { !$0.isBlank }
  }

  static func intervalMillis(_ configured: Int64) -> Int64 {
    min(max(configured, minimumScanIntervalMillis), maximumScanIntervalMillis)
  }

  static func canClaim(
    _ state: GlobalProactiveDiscoveryState,
    nowMillis: Int64,
    force: Bool = false
  ) -> Bool {
    if state.scanLeaseExpiresAtMillis > nowMillis { return false }
    return force || state.nextScanAtMillis <= nowMillis
  }

  static func claim(
    state: GlobalProactiveDiscoveryState,
    nowMillis: Int64,
    force: Bool = false
  ) -> (GlobalProactiveDiscoveryState, GlobalDiscoveryScanClaim)? {
    guard canClaim(state, nowMillis: nowMillis, force: force) else { return nil }
    let claim = GlobalDiscoveryScanClaim(
      sequence: state.scanSequence + 1,
      leaseExpiresAtMillis: nowMillis + scanLeaseMillis
    )
    return (
      GlobalProactiveDiscoveryState(
        nextScanAtMillis: state.nextScanAtMillis,
        scanLeaseExpiresAtMillis: claim.leaseExpiresAtMillis,
        lastStartedAtMillis: nowMillis,
        lastCompletedAtMillis: state.lastCompletedAtMillis,
        scanSequence: claim.sequence,
        recentEmissionTimestamps: state.recentEmissionTimestamps,
        records: state.records,
        lastError: ""
      ),
      claim
    )
  }

  static func complete(
    state: GlobalProactiveDiscoveryState,
    claim: GlobalDiscoveryScanClaim,
    emitted: [GlobalDiscoveryCandidate],
    nowMillis: Int64,
    intervalMillis configuredIntervalMillis: Int64
  ) -> GlobalProactiveDiscoveryState {
    if state.scanSequence != claim.sequence { return state }
    var records = recordsByStableKey(state.records)
    for candidate in emitted {
      records[candidate.stableKey] = GlobalDiscoveryRecord(
        stableKey: candidate.stableKey,
        fingerprint: candidate.fingerprint,
        cognitionTaskId: cognitionTaskId(candidate),
        emittedAtMillis: nowMillis
      )
    }
    return GlobalProactiveDiscoveryState(
      nextScanAtMillis: nowMillis + intervalMillis(configuredIntervalMillis),
      scanLeaseExpiresAtMillis: 0,
      lastStartedAtMillis: state.lastStartedAtMillis,
      lastCompletedAtMillis: nowMillis,
      scanSequence: state.scanSequence,
      recentEmissionTimestamps: (state.recentEmissionTimestamps + emitted.map { _ in nowMillis })
        .filter { nowMillis - $0 <= retainEmissionsMillis },
      records: records.values.sorted { $0.emittedAtMillis < $1.emittedAtMillis },
      lastError: ""
    )
  }

  static func fail(
    state: GlobalProactiveDiscoveryState,
    claim: GlobalDiscoveryScanClaim,
    nowMillis: Int64,
    error: String
  ) -> GlobalProactiveDiscoveryState {
    if state.scanSequence != claim.sequence { return state }
    return GlobalProactiveDiscoveryState(
      nextScanAtMillis: nowMillis + retryDelayMillis,
      scanLeaseExpiresAtMillis: 0,
      lastStartedAtMillis: state.lastStartedAtMillis,
      lastCompletedAtMillis: state.lastCompletedAtMillis,
      scanSequence: state.scanSequence,
      recentEmissionTimestamps: state.recentEmissionTimestamps,
      records: state.records,
      lastError: error
    )
  }

  static func makeDue(_ state: GlobalProactiveDiscoveryState, nowMillis: Int64) -> GlobalProactiveDiscoveryState {
    GlobalProactiveDiscoveryState(
      nextScanAtMillis: min(state.nextScanAtMillis > 0 ? state.nextScanAtMillis : Int64.max, nowMillis),
      scanLeaseExpiresAtMillis: state.scanLeaseExpiresAtMillis,
      lastStartedAtMillis: state.lastStartedAtMillis,
      lastCompletedAtMillis: state.lastCompletedAtMillis,
      scanSequence: state.scanSequence,
      recentEmissionTimestamps: state.recentEmissionTimestamps,
      records: state.records,
      lastError: state.lastError
    )
  }

  static func nextWakeAt(_ state: GlobalProactiveDiscoveryState, nowMillis: Int64) -> Int64 {
    if state.scanLeaseExpiresAtMillis > nowMillis { return state.scanLeaseExpiresAtMillis }
    if state.nextScanAtMillis > 0 {
      return max(state.nextScanAtMillis, nowMillis + minimumWakeDelayMillis)
    }
    return nowMillis + minimumWakeDelayMillis
  }

  private static func conflictCandidates(_ items: [GlobalWorldItem]) -> [GlobalDiscoveryCandidate] {
    let groups = Dictionary(grouping: items.filter {
      $0.status == .conflicted && !$0.conflictGroupId.isBlank
    }, by: \.conflictGroupId)
    return groups.values
      .filter { $0.count >= 2 }
      .map { group in
        let sorted = group.sorted { $0.stableKey < $1.stableKey }
        let topic = group.max { $0.confidence < $1.confidence }?.topic ?? ""
        let values = distinctByNormalized(sorted.map(\.value), limit: 4)
        let causalIds = Set(sorted.flatMap(\.evidenceEventIds).filter { !$0.isBlank })
        let conversations = Set(sorted.flatMap { $0.conversationIds }.filter { !$0.isBlank })
        return GlobalDiscoveryCandidate(
          stableKey: "conflict:\(sorted.first?.conflictGroupId ?? "")",
          fingerprint: fingerprint(
            kind: .crossTopicConflict,
            topic: topic,
            values: values,
            causalEventIds: causalIds
          ),
          kind: .crossTopicConflict,
          topic: topic,
          summary: "Reconcile this unresolved cross-conversation contradiction:" +
            values.map { "\n- \(String($0.prefix(800)))" }.joined(),
          sourceConversationIds: conversations,
          causalEventIds: causalIds,
          score: 0.90,
          urgency: min(max(group.map(\.confidence).max() ?? 0, 0.6), 1.0),
          externalResearchUseful: false
        )
      }
  }

  private static func worldItemCandidate(
    _ item: GlobalWorldItem,
    kind: GlobalDiscoveryKind
  ) -> GlobalDiscoveryCandidate {
    let evidence = Set(item.evidenceEventIds.filter { !$0.isBlank })
    let score: Double
    switch kind {
    case .materialRisk:
      score = min(max(0.50 + item.confidence * 0.32 + Double(min(item.evidenceCount, 4)) * 0.035, 0), 0.94)
    case .highValueOpportunity:
      score = min(max(
        0.42 + item.confidence * 0.30 + Double(min(item.evidenceCount, 4)) * 0.04 +
          (item.conversationIds.count >= 2 ? 0.08 : 0.0),
        0
      ), 0.90)
    default:
      score = item.confidence
    }
    let label = kind == .materialRisk ? "Material risk" : "High-value opportunity"
    return GlobalDiscoveryCandidate(
      stableKey: "\(kind.rawValue.lowercased()):\(item.stableKey)",
      fingerprint: fingerprint(kind: kind, topic: item.topic, values: [item.value], causalEventIds: evidence),
      kind: kind,
      topic: item.topic,
      summary: "\(label) supported by \(item.evidenceCount) authorized observation(s): \(String(item.value.prefix(1_500)))",
      sourceConversationIds: item.conversationIds,
      causalEventIds: evidence,
      score: score,
      urgency: kind == .materialRisk ? item.confidence : score * 0.72,
      externalResearchUseful: true
    )
  }

  private static func synthesisCandidates(
    graph: GlobalTopicProjectGraph,
    eligibleItems: [GlobalWorldItem],
    excludedConversationIds: Set<String>
  ) -> [GlobalDiscoveryCandidate] {
    graph.activeNodes().compactMap { node -> GlobalDiscoveryCandidate? in
      guard node.confidence >= 0.65,
            node.conversationIds.count >= 2,
            node.conversationIds.isDisjoint(with: excludedConversationIds) else {
        return nil
      }
      let nodeTokens = GlobalAgentText.tokens(node.name)
      let itemKinds: Set<GlobalWorldItemKind> = [.goal, .task, .decision, .fact, .state]
      let items = distinctWorldItems(eligibleItems.filter { item in
        let linkedById = node.worldItemIds.contains(item.id)
        let linkedByConversation = !item.conversationIds.isDisjoint(with: node.conversationIds) &&
          GlobalAgentText.overlap(nodeTokens, GlobalAgentText.tokens(item.topic)) >= 0.45
        return (linkedById || linkedByConversation) && itemKinds.contains(item.kind)
      })
      let conversations = Set(items.flatMap { $0.conversationIds })
      guard items.count >= minimumSynthesisItems, conversations.count >= 2 else { return nil }
      let evidence = Set(items.flatMap(\.evidenceEventIds).filter { !$0.isBlank })
      guard let authorizedTopic = items.max(by: { $0.confidence < $1.confidence })?.topic,
            !authorizedTopic.isBlank else {
        return nil
      }
      let values = distinctByNormalized(
        items.sorted {
          if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
          return $0.lastSeenAtMillis > $1.lastSeenAtMillis
        }.map(\.value),
        limit: 6
      )
      return GlobalDiscoveryCandidate(
        stableKey: "synthesis:\(node.stableKey)",
        fingerprint: fingerprint(
          kind: .crossTopicSynthesis,
          topic: authorizedTopic,
          values: values,
          causalEventIds: evidence
        ),
        kind: .crossTopicSynthesis,
        topic: authorizedTopic,
        summary: "Synthesize these related observations to find an unexpressed need, contradiction, risk, or opportunity:" +
          values.map { "\n- \(String($0.prefix(800)))" }.joined(),
        sourceConversationIds: conversations,
        causalEventIds: evidence,
        score: min(max(
          0.50 + node.confidence * 0.20 + Double(min(items.count, 6)) * 0.025 +
            Double(min(conversations.count, 4)) * 0.025,
          0
        ), 0.84),
        urgency: 0.52,
        externalResearchUseful: false
      )
    }
  }

  private static func stalledGoalCandidates(
    goals: [GlobalLongHorizonGoal],
    eligibleItems: [GlobalWorldItem],
    excludedConversationIds: Set<String>,
    nowMillis: Int64
  ) -> [GlobalDiscoveryCandidate] {
    let activeStatuses: Set<GlobalLongHorizonGoalStatus> = [.active, .inProgress, .waitingDependency, .blocked]
    return goals.compactMap { goal -> GlobalDiscoveryCandidate? in
      guard goal.activeCognitionTaskId.isBlank,
            goal.activeRunId.isBlank,
            activeStatuses.contains(goal.status) else {
        return nil
      }
      let goalSourceEvents = Set(goal.sourceEventIds)
      let support = eligibleItems.filter { item in
        !Set(item.evidenceEventIds).isDisjoint(with: goalSourceEvents) ||
          (
            GlobalAgentText.normalize(item.topic) == GlobalAgentText.normalize(goal.topic) &&
              GlobalAgentText.overlap(GlobalAgentText.tokens(item.value), GlobalAgentText.tokens(goal.title)) >= 0.58
          )
      }
      if support.isEmpty { return nil }
      let conversations = Set((Array(goal.sourceConversationIds) + support.flatMap { Array($0.conversationIds) })
        .filter { !$0.isBlank })
      if conversations.isEmpty || !conversations.isDisjoint(with: excludedConversationIds) { return nil }
      let referenceAt = max(goal.lastProgressAtMillis, max(goal.lastCheckAtMillis, goal.createdAtMillis))
      let stallThreshold = max(minimumStalledGoalAgeMillis, goal.checkpointIntervalMillis * 2)
      let stalled = goal.status == .blocked || nowMillis - referenceAt >= stallThreshold
      if !stalled { return nil }
      let causalIds = Set(support.flatMap(\.evidenceEventIds).filter { !$0.isBlank })
      let detail = firstNonBlank([
        goal.blocker,
        goal.progressSummary,
        "No verified progress has been recorded within the expected checkpoint window."
      ])
      return GlobalDiscoveryCandidate(
        stableKey: "stalled-goal:\(goal.stableKey)",
        fingerprint: fingerprint(
          kind: .stalledGoal,
          topic: goal.topic,
          values: [goal.title, goal.status.rawValue, detail],
          causalEventIds: causalIds
        ),
        kind: .stalledGoal,
        topic: goal.topic,
        summary: "Long-horizon goal needs a revised path: \(String(goal.title.prefix(1_000)))\n" +
          "Current evidence: \(String(detail.prefix(1_000)))",
        sourceConversationIds: conversations,
        causalEventIds: causalIds,
        score: goal.status == .blocked ? 0.84 : 0.74,
        urgency: max(goal.priority, goal.status == .blocked ? 0.72 : 0.52),
        externalResearchUseful: true,
        longHorizonGoalId: goal.id
      )
    }
  }

  private static func taskMetadata(_ candidate: GlobalDiscoveryCandidate) -> [String: String] {
    var metadata = [
      "origin": origin,
      "discovery_key": candidate.stableKey,
      "discovery_fingerprint": candidate.fingerprint,
      "discovery_kind": candidate.kind.rawValue,
      "source_conversation_ids": candidate.sourceConversationIds.sorted().joined(separator: ","),
      "external_research_useful": candidate.externalResearchUseful ? "true" : "false"
    ]
    if !candidate.longHorizonGoalId.isBlank {
      metadata["long_horizon_goal_id"] = candidate.longHorizonGoalId
    }
    switch candidate.kind {
    case .crossTopicConflict, .materialRisk, .stalledGoal:
      metadata["risk_candidate"] = String(candidate.summary.prefix(1_500))
    case .highValueOpportunity:
      metadata["opportunity_candidate"] = String(candidate.summary.prefix(1_500))
    case .crossTopicSynthesis:
      break
    }
    return metadata
  }

  private static func fingerprint(
    kind: GlobalDiscoveryKind,
    topic: String,
    values: [String],
    causalEventIds: Set<String>
  ) -> String {
    GlobalAgentText.stableKey(
      kind.rawValue,
      GlobalAgentText.normalize(topic),
      values.map(compact).joined(separator: "|"),
      causalEventIds.sorted().joined(separator: "|")
    )
  }

  private static func distinctByStableKey(_ candidates: [GlobalDiscoveryCandidate]) -> [GlobalDiscoveryCandidate] {
    var seen = Set<String>()
    var result: [GlobalDiscoveryCandidate] = []
    for candidate in candidates where seen.insert(candidate.stableKey).inserted {
      result.append(candidate)
    }
    return result
  }

  private static func distinctWorldItems(_ items: [GlobalWorldItem]) -> [GlobalWorldItem] {
    var seen = Set<String>()
    var result: [GlobalWorldItem] = []
    for item in items where seen.insert(item.stableKey).inserted {
      result.append(item)
    }
    return result
  }

  private static func distinctByNormalized(_ values: [String], limit: Int) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values {
      let normalized = GlobalAgentText.normalize(value)
      if normalized.isBlank || !seen.insert(normalized).inserted { continue }
      result.append(value)
      if result.count >= limit { break }
    }
    return result
  }

  private static func recordsByStableKey(_ records: [GlobalDiscoveryRecord]) -> [String: GlobalDiscoveryRecord] {
    records.reduce(into: [String: GlobalDiscoveryRecord]()) { result, record in
      result[record.stableKey] = record
    }
  }

  private static func firstNonBlank(_ values: [String]) -> String {
    values.first { !$0.isBlank } ?? ""
  }

  private static func compact(_ value: String) -> String {
    value
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static let origin = "global_world_discovery"
  static let scanLeaseMillis: Int64 = 10 * 60 * 1_000
  static let retryDelayMillis: Int64 = 15 * 60 * 1_000
  private static let minimumDiscoveryScore = 0.68
  private static let maxScanCandidates = 40
  private static let minimumSynthesisItems = 3
  private static let maxTasksPerScan = 2
  private static let dayMillis: Int64 = 24 * 60 * 60 * 1_000
  private static let changedFindingCooldownMillis: Int64 = 6 * 60 * 60 * 1_000
  private static let failedTaskRetryMillis: Int64 = 24 * 60 * 60 * 1_000
  private static let minimumStalledGoalAgeMillis: Int64 = 24 * 60 * 60 * 1_000
  private static let minimumScanIntervalMillis: Int64 = 60 * 60 * 1_000
  private static let maximumScanIntervalMillis: Int64 = 7 * 24 * 60 * 60 * 1_000
  private static let minimumWakeDelayMillis: Int64 = 60_000
  private static let retainEmissionsMillis: Int64 = 7 * 24 * 60 * 60 * 1_000
}

enum GlobalProactiveDiscoveryCodec {
  static func encode(_ state: GlobalProactiveDiscoveryState) -> String {
    guard let data = try? encoder.encode(state),
          let encoded = String(data: data, encoding: .utf8) else {
      return "{}"
    }
    return encoded
  }

  static func decode(_ raw: String) -> GlobalProactiveDiscoveryState {
    guard !raw.isBlank, let data = raw.data(using: .utf8) else {
      return GlobalProactiveDiscoveryState()
    }
    return (try? decoder.decode(GlobalProactiveDiscoveryState.self, from: data)) ?? GlobalProactiveDiscoveryState()
  }

  private static var encoder: JSONEncoder {
    JSONEncoder()
  }

  private static var decoder: JSONDecoder {
    JSONDecoder()
  }
}

private func clamp01(_ value: Double) -> Double {
  min(max(value, 0), 1)
}
