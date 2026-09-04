import Foundation

enum AgentAttentionDisposition: String, Codable, CaseIterable, Identifiable {
  case notifyNow = "notify_now"
  case dailyDigest = "daily_digest"
  case silentRecord = "silent_record"
  case discard

  var id: String { rawValue }
}

struct AgentAttentionCandidate: Codable, Equatable {
  var relevance: Double
  var novelty: Double
  var credibility: Double
  var actionability: Double
  var interruptionCost: Double
  var tokenCost: Double
  var batteryCost: Double
  var urgent = false
}

struct AgentAttentionDecision: Codable, Equatable {
  var value: Double
  var threshold: Double
  var disposition: AgentAttentionDisposition
  var reasons: [String]
}

enum AgentAttentionBudgetPolicy {
  static func evaluate(candidate: AgentAttentionCandidate, threshold: Double) -> AgentAttentionDecision {
    let relevance = unit(candidate.relevance)
    let novelty = unit(candidate.novelty)
    let credibility = unit(candidate.credibility)
    let actionability = unit(candidate.actionability)
    let positive = relevance * novelty * credibility * actionability
    let cost = unit(candidate.interruptionCost) * 0.55 + unit(candidate.tokenCost) * 0.25 +
      unit(candidate.batteryCost) * 0.20
    let value = min(max(positive - cost, -1), 1)
    let threshold = unit(threshold)
    let disposition: AgentAttentionDisposition
    if candidate.urgent, value >= threshold * 0.75 {
      disposition = .notifyNow
    } else if value >= threshold {
      disposition = .notifyNow
    } else if value >= threshold * 0.55 {
      disposition = .dailyDigest
    } else if value > 0 {
      disposition = .silentRecord
    } else {
      disposition = .discard
    }
    return AgentAttentionDecision(
      value: value,
      threshold: threshold,
      disposition: disposition,
      reasons: [
        "relevance:\(format(relevance))",
        "novelty:\(format(novelty))",
        "credibility:\(format(credibility))",
        "actionability:\(format(actionability))",
        "interruption_cost:\(format(unit(candidate.interruptionCost)))",
        "token_cost:\(format(unit(candidate.tokenCost)))",
        "battery_cost:\(format(unit(candidate.batteryCost)))"
      ]
    )
  }

  private static func unit(_ value: Double) -> Double { min(max(value, 0), 1) }
  private static func format(_ value: Double) -> String { String(format: "%.4f", value) }
}

enum AgentKnowledgeGapStatus: String, Codable, CaseIterable, Identifiable {
  case open
  case researching
  case resolved
  case dismissed

  var id: String { rawValue }
}

struct AgentKnowledgeGap: Codable, Equatable, Identifiable {
  var id: String
  var topic: String
  var knownSummary: String
  var unknownQuestions: [String]
  var missingEvidence: [String]
  var relatedGoal: String
  var sourceRunIds: [String]
  var priority: Double
  var status: AgentKnowledgeGapStatus
  var createdAtMillis: Int64
  var updatedAtMillis: Int64
  var recheckAfterMillis: Int64

  init(
    id: String = UUID().uuidString,
    topic: String,
    knownSummary: String,
    unknownQuestions: [String],
    missingEvidence: [String],
    relatedGoal: String = "",
    sourceRunIds: [String] = [],
    priority: Double = 0.5,
    status: AgentKnowledgeGapStatus = .open,
    createdAtMillis: Int64 = AgentEvalClock.nowMillis(),
    updatedAtMillis: Int64? = nil,
    recheckAfterMillis: Int64 = 0
  ) {
    self.id = id
    self.topic = String(topic.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
    self.knownSummary = String(knownSummary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_000))
    self.unknownQuestions = Self.unique(unknownQuestions, limit: 20)
    self.missingEvidence = Self.unique(missingEvidence, limit: 20)
    self.relatedGoal = String(relatedGoal.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000))
    self.sourceRunIds = Array(Self.unique(sourceRunIds, limit: 40).suffix(40))
    self.priority = min(max(priority, 0), 1)
    self.status = status
    self.createdAtMillis = max(0, createdAtMillis)
    self.updatedAtMillis = max(0, updatedAtMillis ?? createdAtMillis)
    self.recheckAfterMillis = max(0, recheckAfterMillis)
  }

  private static func unique(_ values: [String], limit: Int) -> [String] {
    var seen = Set<String>()
    return values.compactMap { value in
      let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return clean.isEmpty || !seen.insert(clean).inserted ? nil : clean
    }.prefixArray(limit)
  }
}

struct AgentDecisionLogEntry: Codable, Equatable, Identifiable {
  var id: String
  var question: String
  var decision: String
  var alternatives: [String]
  var evidenceRefs: [String]
  var rationale: String
  var relatedGoal: String
  var outcome: String
  var outcomeEvidenceRefs: [String]
  var createdAtMillis: Int64
  var reviewedAtMillis: Int64

  init(
    id: String = UUID().uuidString,
    question: String,
    decision: String,
    alternatives: [String],
    evidenceRefs: [String],
    rationale: String,
    relatedGoal: String = "",
    outcome: String = "pending",
    outcomeEvidenceRefs: [String] = [],
    createdAtMillis: Int64 = AgentEvalClock.nowMillis(),
    reviewedAtMillis: Int64 = 0
  ) {
    self.id = id
    self.question = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
    self.decision = String(decision.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
    self.alternatives = Array(alternatives.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(20))
    self.evidenceRefs = Array(evidenceRefs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(40))
    self.rationale = String(rationale.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_000))
    self.relatedGoal = String(relatedGoal.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000))
    self.outcome = String(outcome.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(80))
    self.outcomeEvidenceRefs = Array(outcomeEvidenceRefs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(40))
    self.createdAtMillis = max(0, createdAtMillis)
    self.reviewedAtMillis = max(0, reviewedAtMillis)
  }
}

final class AgentCognitiveGovernanceStore {
  private struct State: Codable {
    var gaps: [String: AgentKnowledgeGap] = [:]
    var decisions: [String: AgentDecisionLogEntry] = [:]
  }

  static let defaultKey = "galaxyssi-ios-cognitive-governance-v1"
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let key: String
  private let nowMillis: () -> Int64
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    key: String = AgentCognitiveGovernanceStore.defaultKey,
    nowMillis: @escaping () -> Int64 = AgentEvalClock.nowMillis
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.key = key
    self.nowMillis = nowMillis
  }

  @discardableResult
  func upsertGap(_ gap: AgentKnowledgeGap) -> AgentKnowledgeGap? {
    var normalized = AgentKnowledgeGap(
      id: gap.id,
      topic: gap.topic,
      knownSummary: gap.knownSummary,
      unknownQuestions: gap.unknownQuestions,
      missingEvidence: gap.missingEvidence,
      relatedGoal: gap.relatedGoal,
      sourceRunIds: gap.sourceRunIds,
      priority: gap.priority,
      status: gap.status,
      createdAtMillis: gap.createdAtMillis,
      updatedAtMillis: nowMillis(),
      recheckAfterMillis: gap.recheckAfterMillis
    )
    guard !normalized.topic.isEmpty, !normalized.unknownQuestions.isEmpty else { return nil }
    return locked {
      var state = load()
      normalized.updatedAtMillis = nowMillis()
      state.gaps[normalized.id] = normalized
      state.gaps = Dictionary(uniqueKeysWithValues: state.gaps.values
        .sorted { $0.updatedAtMillis > $1.updatedAtMillis }
        .prefix(Self.maximumGaps)
        .map { ($0.id, $0) })
      save(state)
      return normalized
    }
  }

  func gaps(status: AgentKnowledgeGapStatus? = nil, limit: Int = AgentCognitiveGovernanceStore.maximumGaps) -> [AgentKnowledgeGap] {
    locked {
      Array(load().gaps.values)
        .filter { status == nil || $0.status == status }
        .sorted { $0.priority == $1.priority ? $0.updatedAtMillis > $1.updatedAtMillis : $0.priority > $1.priority }
        .prefixArray(min(max(limit, 1), Self.maximumGaps))
    }
  }

  @discardableResult
  func updateGapStatus(id: String, status: AgentKnowledgeGapStatus) -> AgentKnowledgeGap? {
    guard var gap = locked({ load().gaps[id.trimmingCharacters(in: .whitespacesAndNewlines)] }) else { return nil }
    gap.status = status
    return upsertGap(gap)
  }

  @discardableResult
  func appendDecision(_ entry: AgentDecisionLogEntry) -> AgentDecisionLogEntry? {
    let normalized = AgentDecisionLogEntry(
      id: entry.id,
      question: entry.question,
      decision: entry.decision,
      alternatives: entry.alternatives,
      evidenceRefs: entry.evidenceRefs,
      rationale: entry.rationale,
      relatedGoal: entry.relatedGoal,
      outcome: entry.outcome,
      outcomeEvidenceRefs: entry.outcomeEvidenceRefs,
      createdAtMillis: entry.createdAtMillis,
      reviewedAtMillis: entry.reviewedAtMillis
    )
    guard !normalized.question.isEmpty, !normalized.decision.isEmpty else { return nil }
    return locked {
      var state = load()
      state.decisions[normalized.id] = normalized
      state.decisions = Dictionary(uniqueKeysWithValues: state.decisions.values
        .sorted { $0.createdAtMillis > $1.createdAtMillis }
        .prefix(Self.maximumDecisions)
        .map { ($0.id, $0) })
      save(state)
      return normalized
    }
  }

  func decisions(limit: Int = AgentCognitiveGovernanceStore.maximumDecisions) -> [AgentDecisionLogEntry] {
    locked {
      Array(load().decisions.values.sorted { $0.createdAtMillis > $1.createdAtMillis }
        .prefix(min(max(limit, 1), Self.maximumDecisions)))
    }
  }

  @discardableResult
  func recordDecisionOutcome(
    id: String,
    outcome: String,
    evidenceRefs: [String],
    reviewedAtMillis: Int64? = nil
  ) -> AgentDecisionLogEntry? {
    locked {
      var state = load()
      guard var current = state.decisions[id.trimmingCharacters(in: .whitespacesAndNewlines)] else { return nil }
      current.outcome = String(outcome.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(80))
      current.outcomeEvidenceRefs = Array(evidenceRefs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(40))
      current.reviewedAtMillis = max(0, reviewedAtMillis ?? nowMillis())
      state.decisions[current.id] = current
      save(state)
      return current
    }
  }

  private func load() -> State {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets),
          let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
    return state
  }

  private func save(_ state: State) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: key, secrets: secrets)
  }

  private func locked<T>(_ work: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return work()
  }

  static let maximumGaps = 1_000
  static let maximumDecisions = 2_000
}

enum AgentKnowledgeGapDetector {
  @discardableResult
  static func observe(
    store: AgentCognitiveGovernanceStore,
    run: AgentRecordedRun,
    sample: AgentEvalSample,
    nowMillis: Int64 = AgentEvalClock.nowMillis()
  ) -> AgentKnowledgeGap? {
    let missing = sample.failureReasons.filter { $0.hasPrefix("missing_evidence:") }
    guard !missing.isEmpty else { return nil }
    let topic = AgentLearningAnalyzer.safeTitle(run.originalRequest)
    let existing = store.gaps(status: .open).first { AgentLearningAnalyzer.sameTaskFamily($0.topic, topic) }
    let gap = AgentKnowledgeGap(
      id: existing?.id ?? UUID().uuidString,
      topic: topic,
      knownSummary: existing?.knownSummary ?? "A real Agent run was observed but its completion evidence was incomplete.",
      unknownQuestions: existing?.unknownQuestions ?? ["What evidence would prove this task completed correctly?"],
      missingEvidence: (existing?.missingEvidence ?? []) + missing.map { String($0.dropFirst("missing_evidence:".count)) },
      relatedGoal: existing?.relatedGoal ?? run.originalRequest,
      sourceRunIds: (existing?.sourceRunIds ?? []) + [run.runId],
      priority: max(existing?.priority ?? 0, sample.verdict == .failed ? 0.80 : 0.65),
      status: existing?.status ?? .open,
      createdAtMillis: existing?.createdAtMillis ?? nowMillis,
      recheckAfterMillis: nowMillis + 7 * 24 * 60 * 60_000
    )
    return store.upsertGap(gap)
  }
}

enum AgentStandardProtocol: String, Codable, CaseIterable, Identifiable {
  case mcp
  case agentSkills = "agent_skills"
  case acp
  case a2a

  var id: String { rawValue }
}

enum AgentProtocolAdapterState: String, Codable, CaseIterable, Identifiable {
  case ready
  case connected
  case needsSetup = "needs_setup"
  case disabled

  var id: String { rawValue }
}

struct AgentProtocolAdapterDescriptor: Codable, Equatable, Identifiable {
  var protocolKind: AgentStandardProtocol
  var state: AgentProtocolAdapterState
  var version: String
  var connectedEndpoints: Int
  var operations: Set<String>
  var localPermissionBoundary: Bool = true

  var id: String { protocolKind.rawValue }
}

protocol AgentStandardProtocolAdapter {
  var protocolKind: AgentStandardProtocol { get }
  func encodeRequest(_ request: AgentRunRequest) -> AgentMcpJSONObject
  func decodeRequest(_ payload: AgentMcpJSONObject) -> AgentRunRequest?
  func encodeEvent(_ event: AgentRunControlEvent) -> AgentMcpJSONObject
}

struct AgentA2ABoundaryAdapter: AgentStandardProtocolAdapter {
  let protocolKind = AgentStandardProtocol.a2a

  func encodeRequest(_ request: AgentRunRequest) -> AgentMcpJSONObject {
    [
      "jsonrpc": .string("2.0"),
      "id": .string(request.runId),
      "method": .string("message/send"),
      "params": .object([
        "contextId": .string(request.conversationId),
        "message": .object([
          "messageId": .string(request.messageId),
          "role": .string("user"),
          "parts": .array([.object(["kind": .string("text"), "text": .string(request.goal)])])
        ])
      ])
    ]
  }

  func decodeRequest(_ payload: AgentMcpJSONObject) -> AgentRunRequest? {
    guard let parameters = payload["params"]?.objectValue,
          let message = parameters["message"]?.objectValue,
          case .array(let parts) = message["parts"] else { return nil }
    let goal = parts.compactMap { $0.objectValue?["text"]?.stringValue }.joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !goal.isEmpty else { return nil }
    return request(
      conversationId: parameters["contextId"]?.stringValue,
      messageId: message["messageId"]?.stringValue,
      taskId: parameters["taskId"]?.stringValue,
      runId: payload["id"]?.stringValue,
      goal: goal
    )
  }

  func encodeEvent(_ event: AgentRunControlEvent) -> AgentMcpJSONObject {
    [
      "taskId": .string(event.taskId),
      "contextId": .string(event.conversationId),
      "kind": .string("status-update"),
      "final": .bool([.runCompleted, .runFailed, .runCancelled].contains(event.type)),
      "status": .object([
        "state": .string(a2aState(event.type)),
        "timestamp": .int(event.timestampMillis)
      ])
    ]
  }

  private func a2aState(_ type: AgentRunControlEventType) -> String {
    switch type {
    case .runCompleted: return "completed"
    case .runFailed: return "failed"
    case .runCancelled: return "canceled"
    case .waitingForUser, .toolPermissionRequired: return "input-required"
    case .waitingForDevice: return "auth-required"
    default: return "working"
    }
  }
}

struct AgentACPBoundaryAdapter: AgentStandardProtocolAdapter {
  let protocolKind = AgentStandardProtocol.acp

  func encodeRequest(_ request: AgentRunRequest) -> AgentMcpJSONObject {
    [
      "jsonrpc": .string("2.0"),
      "id": .string(request.runId),
      "method": .string("session/prompt"),
      "params": .object([
        "sessionId": .string(request.conversationId),
        "prompt": .array([.object(["type": .string("text"), "text": .string(request.goal)])])
      ])
    ]
  }

  func decodeRequest(_ payload: AgentMcpJSONObject) -> AgentRunRequest? {
    guard let parameters = payload["params"]?.objectValue,
          case .array(let prompt) = parameters["prompt"] else { return nil }
    let goal = prompt.compactMap { $0.objectValue?["text"]?.stringValue }.joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !goal.isEmpty else { return nil }
    return request(
      conversationId: parameters["sessionId"]?.stringValue,
      messageId: payload["id"]?.stringValue,
      taskId: parameters["taskId"]?.stringValue,
      runId: payload["id"]?.stringValue,
      goal: goal
    )
  }

  func encodeEvent(_ event: AgentRunControlEvent) -> AgentMcpJSONObject {
    [
      "jsonrpc": .string("2.0"),
      "method": .string("session/update"),
      "params": .object([
        "sessionId": .string(event.conversationId),
        "update": .object([
          "sessionUpdate": .string("agent_message_chunk"),
          "content": .object(["type": .string("text"), "text": .string(String(describing: event.payload))])
        ])
      ])
    ]
  }
}

private func request(
  conversationId: String?,
  messageId: String?,
  taskId: String?,
  runId: String?,
  goal: String
) -> AgentRunRequest {
  let runId = runId?.ifBlank(UUID().uuidString) ?? UUID().uuidString
  return AgentRunRequest(
    conversationId: conversationId?.ifBlank(UUID().uuidString) ?? UUID().uuidString,
    messageId: messageId?.ifBlank(UUID().uuidString) ?? UUID().uuidString,
    taskId: taskId?.ifBlank(UUID().uuidString) ?? UUID().uuidString,
    runId: runId,
    parentRunId: "",
    goal: goal,
    deliveryMode: .respond,
    requiredCapabilities: [],
    context: [:],
    idempotencyKey: runId,
    createdAtMillis: AgentEvalClock.nowMillis()
  )
}

enum AgentProtocolAdapterRegistry {
  static func descriptors(
    settings: AgentEvalOpsSettings,
    callableMCPConnections: Int,
    enabledSkills: Int,
    acpRegistrations: Int,
    a2aRegistrations: Int
  ) -> [AgentProtocolAdapterDescriptor] {
    let enabled = settings.protocolAdaptersEnabled
    return [
      AgentProtocolAdapterDescriptor(
        protocolKind: .mcp,
        state: enabled ? (callableMCPConnections > 0 ? .connected : .ready) : .disabled,
        version: "negotiated",
        connectedEndpoints: max(0, callableMCPConnections),
        operations: ["tools/list", "tools/call", "resources/list", "resources/read"]
      ),
      AgentProtocolAdapterDescriptor(
        protocolKind: .agentSkills,
        state: enabled ? .ready : .disabled,
        version: "SKILL.md",
        connectedEndpoints: max(0, enabledSkills),
        operations: ["import", "export", "review", "sign", "install"]
      ),
      AgentProtocolAdapterDescriptor(
        protocolKind: .acp,
        state: enabled ? .ready : .disabled,
        version: "negotiated",
        connectedEndpoints: max(0, acpRegistrations),
        operations: ["initialize", "session/new", "session/prompt", "session/cancel", "session/update"]
      ),
      AgentProtocolAdapterDescriptor(
        protocolKind: .a2a,
        state: enabled ? .ready : .disabled,
        version: "1.0.0",
        connectedEndpoints: max(0, a2aRegistrations),
        operations: ["agent-card", "message/send", "message/stream", "tasks/get", "tasks/cancel"]
      )
    ]
  }
}

private extension Array {
  func prefixArray(_ count: Int) -> [Element] { Array(prefix(count)) }
}
