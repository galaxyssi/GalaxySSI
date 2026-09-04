import Foundation

struct GlobalResearchExecutionResult: Codable, Equatable {
  var taskId: String
  var status: GlobalResearchTaskStatus
  var resourceId: String
  var detail: String

  init(
    taskId: String,
    status: GlobalResearchTaskStatus,
    resourceId: String = "",
    detail: String = ""
  ) {
    self.taskId = taskId
    self.status = status
    self.resourceId = resourceId
    self.detail = String(detail.prefix(GlobalResearchExecutorLimits.maxResultDetailCharacters))
  }

  enum CodingKeys: String, CodingKey {
    case taskId = "task_id"
    case status
    case resourceId = "resource_id"
    case detail
  }
}

enum GlobalResearchResourceTransport: String, Codable, CaseIterable, Identifiable {
  case onDeviceModel = "ON_DEVICE_MODEL"
  case cloudModel = "CLOUD_MODEL"
  case pairedAgent = "PAIRED_AGENT"

  var id: String { rawValue }
}

enum GlobalBackgroundReasoningResourcePolicy {
  private static let reasoningTypes: Set<AgentResourceType> = [
    .onDeviceModel,
    .remoteLocalModel,
    .cloudModel,
    .localAgent,
    .remoteAgent
  ]

  static func allowed(
    _ resource: AgentResourceDescriptor,
    allowPaired: Bool,
    allowCloud: Bool,
    localModelReady: Bool
  ) -> Bool {
    guard resource.status == .available, reasoningTypes.contains(resource.type) else { return false }
    switch resource.location {
    case .phone:
      return resource.trust == .phoneSystem && localModelReady
    case .trustedDesktop:
      return allowPaired && resource.trust == .verifiedPaired && resource.supportsBackground
    case .privateNetwork:
      return allowCloud && resource.trust == .privateConfigured
    case .cloud:
      return allowCloud && resource.trust == .cloudConfigured
    }
  }
}

struct GlobalResearchExecutorResource: Codable, Equatable, Identifiable {
  var id: String
  var transport: GlobalResearchResourceTransport
  var contactId: String
  var available: Bool
  var capabilities: Set<AgentCapability>
  var displayName: String

  init(
    id: String,
    transport: GlobalResearchResourceTransport,
    contactId: String = "",
    available: Bool = true,
    capabilities: Set<AgentCapability> = [.research, .reasoning],
    displayName: String = ""
  ) {
    self.id = id
    self.transport = transport
    self.contactId = contactId
    self.available = available
    self.capabilities = capabilities
    self.displayName = displayName
  }

  var targetContactId: String {
    contactId.isBlank ? id : contactId
  }

  var researchCapable: Bool {
    available && (
      capabilities.isEmpty ||
        capabilities.contains(.research) ||
        capabilities.contains(.reasoning) ||
        capabilities.contains(.liveData) ||
        capabilities.contains(.chat)
    )
  }

  enum CodingKeys: String, CodingKey {
    case id
    case transport
    case contactId = "contact_id"
    case available
    case capabilities
    case displayName = "display_name"
  }
}

enum GlobalResearchDispatchStage: String, Codable, CaseIterable, Identifiable {
  case evidence = "EVIDENCE"
  case synthesis = "SYNTHESIS"

  var id: String { rawValue }
}

struct GlobalResearchDispatchRequest: Codable, Equatable, Identifiable {
  var id: String
  var taskId: String
  var unitId: String
  var stage: GlobalResearchDispatchStage
  var transport: GlobalResearchResourceTransport
  var resourceId: String
  var contactId: String
  var sourceMessageId: Int64
  var conversationId: String
  var turnId: String
  var ownerKey: String
  var leaseId: String
  var systemPrompt: String
  var prompt: String
  var estimatedInputTokens: Int64
  var createdAtMillis: Int64

  init(
    id: String = UUID().uuidString,
    taskId: String,
    unitId: String = "",
    stage: GlobalResearchDispatchStage,
    transport: GlobalResearchResourceTransport,
    resourceId: String,
    contactId: String,
    sourceMessageId: Int64,
    conversationId: String,
    turnId: String,
    ownerKey: String,
    leaseId: String,
    systemPrompt: String,
    prompt: String,
    estimatedInputTokens: Int64,
    createdAtMillis: Int64
  ) {
    self.id = id
    self.taskId = taskId
    self.unitId = unitId
    self.stage = stage
    self.transport = transport
    self.resourceId = resourceId
    self.contactId = contactId
    self.sourceMessageId = max(sourceMessageId, 0)
    self.conversationId = conversationId
    self.turnId = turnId
    self.ownerKey = String(ownerKey.prefix(500))
    self.leaseId = leaseId
    self.systemPrompt = String(systemPrompt.prefix(GlobalResearchExecutorLimits.maxSystemPromptCharacters))
    self.prompt = String(prompt.prefix(GlobalResearchExecutorLimits.maxSynthesisPromptCharacters))
    self.estimatedInputTokens = max(estimatedInputTokens, 0)
    self.createdAtMillis = max(createdAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case taskId = "task_id"
    case unitId = "unit_id"
    case stage
    case transport
    case resourceId = "resource_id"
    case contactId = "contact_id"
    case sourceMessageId = "source_message_id"
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case ownerKey = "owner_key"
    case leaseId = "lease_id"
    case systemPrompt = "system_prompt"
    case prompt
    case estimatedInputTokens = "estimated_input_tokens"
    case createdAtMillis = "created_at_millis"
  }
}

struct GlobalResearchExecutorBudgetLimits: Codable, Equatable {
  var dailyLimit: Int
  var concurrencyLimit: Int
  var dailyTokenLimit: Int64
  var dailyReportedCostLimitMicros: Int64

  init(
    dailyLimit: Int = 24,
    concurrencyLimit: Int = 3,
    dailyTokenLimit: Int64 = GlobalModelCallBudgetPolicy.maxDailyTokenLimit,
    dailyReportedCostLimitMicros: Int64 = 0
  ) {
    self.dailyLimit = max(dailyLimit, 1)
    self.concurrencyLimit = max(concurrencyLimit, 1)
    self.dailyTokenLimit = max(dailyTokenLimit, 0)
    self.dailyReportedCostLimitMicros = max(dailyReportedCostLimitMicros, 0)
  }

  enum CodingKeys: String, CodingKey {
    case dailyLimit = "daily_limit"
    case concurrencyLimit = "concurrency_limit"
    case dailyTokenLimit = "daily_token_limit"
    case dailyReportedCostLimitMicros = "daily_reported_cost_limit_micros"
  }
}

struct GlobalResearchExecutionContext: Codable, Equatable {
  var conversationContext: String
  var realtimeContext: String
  var worldContext: String
  var causalEventIdsWithRetractedEvidence: Set<String>

  init(
    conversationContext: String = "",
    realtimeContext: String = "",
    worldContext: String = "",
    causalEventIdsWithRetractedEvidence: Set<String> = []
  ) {
    self.conversationContext = String(conversationContext.prefix(GlobalResearchExecutorLimits.maxContextCharacters))
    self.realtimeContext = String(realtimeContext.prefix(GlobalResearchExecutorLimits.maxContextCharacters))
    self.worldContext = String(worldContext.prefix(GlobalResearchExecutorLimits.maxContextCharacters))
    self.causalEventIdsWithRetractedEvidence = Set(causalEventIdsWithRetractedEvidence.filter { !$0.isBlank })
  }

  enum CodingKeys: String, CodingKey {
    case conversationContext = "conversation_context"
    case realtimeContext = "realtime_context"
    case worldContext = "world_context"
    case causalEventIdsWithRetractedEvidence = "causal_event_ids_with_retracted_evidence"
  }

  func hasRetractedEvidence(_ ids: Set<String>) -> Bool {
    !ids.isDisjoint(with: causalEventIdsWithRetractedEvidence)
  }
}

struct GlobalResearchResourceHealthUpdate: Codable, Equatable, Identifiable {
  var id: String
  var resourceId: String
  var success: Bool
  var latencyMillis: Int64
  var createdAtMillis: Int64

  init(
    resourceId: String,
    success: Bool,
    latencyMillis: Int64 = 0,
    createdAtMillis: Int64
  ) {
    self.id = "research-health:\(GlobalAgentText.stableKey(resourceId, success.description, String(createdAtMillis)))"
    self.resourceId = resourceId
    self.success = success
    self.latencyMillis = max(latencyMillis, 0)
    self.createdAtMillis = max(createdAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case resourceId = "resource_id"
    case success
    case latencyMillis = "latency_millis"
    case createdAtMillis = "created_at_millis"
  }
}

struct GlobalResearchExecutorState: Codable, Equatable {
  var tasks: [GlobalResearchTask]
  var modelBudget: GlobalModelCallBudgetState
  var dispatchRequests: [GlobalResearchDispatchRequest]
  var proactiveMessages: [GlobalProactiveMessage]
  var events: [GlobalConversationEvent]
  var healthUpdates: [GlobalResearchResourceHealthUpdate]

  init(
    tasks: [GlobalResearchTask] = [],
    modelBudget: GlobalModelCallBudgetState = GlobalModelCallBudgetState(),
    dispatchRequests: [GlobalResearchDispatchRequest] = [],
    proactiveMessages: [GlobalProactiveMessage] = [],
    events: [GlobalConversationEvent] = [],
    healthUpdates: [GlobalResearchResourceHealthUpdate] = []
  ) {
    self.tasks = tasks
    self.modelBudget = modelBudget
    self.dispatchRequests = dispatchRequests
    self.proactiveMessages = proactiveMessages
    self.events = events
    self.healthUpdates = healthUpdates
  }

  mutating func upsert(_ task: GlobalResearchTask) {
    if let index = tasks.firstIndex(where: { $0.id == task.id }) {
      tasks[index] = task
    } else {
      tasks.append(task)
    }
  }

  func task(id: String) -> GlobalResearchTask? {
    tasks.first { $0.id == id }
  }
}

struct GlobalResearchExecutorStep: Codable, Equatable {
  var state: GlobalResearchExecutorState
  var result: GlobalResearchExecutionResult

  init(state: GlobalResearchExecutorState, result: GlobalResearchExecutionResult) {
    self.state = state
    self.result = result
  }
}

enum GlobalResearchExecutorLimits {
  static let maximumAttempts = 3
  static let maximumUnitAttempts = 3
  static let maximumSynthesisAttempts = 3
  static let resourceRetryMillis: Int64 = 30 * 60 * 1_000
  static let collectionContinueDelayMillis: Int64 = 3_000
  static let monitorFailureRetryMillis: Int64 = 6 * 60 * 60 * 1_000
  static let maxUnitResultCharacters = 18_000
  static let maxResultCharacters = 24_000
  static let maxPromptCharacters = 12_000
  static let maxSynthesisPromptCharacters = 28_000
  static let maxSynthesisUnitCharacters = 5_000
  static let maxArchivedUnitResultCharacters = 3_000
  static let maxEvidenceUris = 30
  static let maxResultDetailCharacters = 240
  static let maxSystemPromptCharacters = 2_000
  static let maxContextCharacters = 4_000
}

enum GlobalResearchTaskPolicy {
  static func selectionScore(_ task: GlobalResearchTask, nowMillis: Int64) -> Int64 {
    let ageMillis = max(nowMillis - task.createdAtMillis, 0)
    let freshBonus = min(max(sixHoursMillis - ageMillis, 0) / 60_000, 360)
    let agingBonus = min(ageMillis / dayMillis, 30) * 12
    let depthScore: Int64
    switch task.depth {
    case .proactiveInference: depthScore = 260
    case .deepResearch: depthScore = 180
    case .quickFact: depthScore = 120
    case .continuousMonitor: depthScore = 60
    }
    let statusScore: Int64
    switch task.status {
    case .queued: statusScore = 120
    case .scheduled: statusScore = 60
    default: statusScore = 0
    }
    return depthScore + statusScore + freshBonus + agingBonus - Int64(min(task.attemptCount, 8) * 45)
  }

  static func leaseMillis(_ depth: GlobalResearchDepth) -> Int64 {
    switch depth {
    case .quickFact:
      return 2 * 60 * 1_000
    case .proactiveInference:
      return 3 * 60 * 1_000
    case .deepResearch:
      return 8 * 60 * 1_000
    case .continuousMonitor:
      return 10 * 60 * 1_000
    }
  }

  static func retryDelayMillis(_ attemptCount: Int) -> Int64 {
    switch max(attemptCount, 1) {
    case 1:
      return 30_000
    case 2:
      return 2 * 60 * 1_000
    case 3:
      return 10 * 60 * 1_000
    default:
      return 30 * 60 * 1_000
    }
  }

  static func monitorIntervalMillis(_ configured: Int64) -> Int64 {
    if configured > 0 {
      return min(max(configured, minimumMonitorIntervalMillis), maximumMonitorIntervalMillis)
    }
    return defaultMonitorIntervalMillis
  }

  static func recoverIfStale(_ task: GlobalResearchTask, nowMillis: Int64) -> GlobalResearchTask {
    let recoveredPlan = GlobalResearchPlanBuilder.recoverStale(plan: task.researchPlan, nowMillis: nowMillis)
    let parentExpired = task.status == .running &&
      task.leaseExpiresAtMillis > 0 &&
      task.leaseExpiresAtMillis <= nowMillis
    if !parentExpired && recoveredPlan == task.researchPlan { return task }
    return GlobalResearchTask(
      id: task.id,
      sourceEventId: task.sourceEventId,
      sourceConversationId: task.sourceConversationId,
      topic: task.topic,
      question: task.question,
      depth: task.depth,
      preferredSources: task.preferredSources,
      causalEventIds: task.causalEventIds,
      status: .waitingForResource,
      resourceId: task.resourceId,
      fallbackResourceIds: task.fallbackResourceIds,
      attemptedResourceIds: researchTaskPolicyUniqueStrings((task.attemptedResourceIds + [task.resourceId]).filter { !$0.isBlank }),
      sourceMessageId: 0,
      attemptCount: task.attemptCount,
      nextAttemptAtMillis: nowMillis,
      leaseExpiresAtMillis: 0,
      monitorIntervalMillis: task.monitorIntervalMillis,
      lastCompletedAtMillis: task.lastCompletedAtMillis,
      lastResultFingerprint: task.lastResultFingerprint,
      lastError: "The previous research lease expired before a result arrived",
      result: task.result,
      evidenceUris: task.evidenceUris,
      researchPlan: recoveredPlan,
      evidenceLedger: task.evidenceLedger,
      createdAtMillis: task.createdAtMillis,
      updatedAtMillis: nowMillis
    )
  }

  static func fingerprint(_ result: String, evidenceUris: [String]) -> String {
    GlobalAgentText.stableKey(
      String(result
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .prefix(20_000)),
      evidenceUris.sorted().joined(separator: "|")
    )
  }

  private static let sixHoursMillis: Int64 = 6 * 60 * 60 * 1_000
  private static let dayMillis: Int64 = 24 * 60 * 60 * 1_000

  static func isMaterialChange(
    previousResult: String,
    previousEvidenceUris: [String],
    nextResult: String,
    nextEvidenceUris: [String]
  ) -> Bool {
    if previousResult.isBlank { return true }
    let previousComparable = comparableResult(previousResult)
    let nextComparable = comparableResult(nextResult)
    if previousComparable == nextComparable { return false }
    let previousTokens = GlobalAgentText.tokens(previousComparable)
    let nextTokens = GlobalAgentText.tokens(nextComparable)
    let semanticOverlap = GlobalAgentText.overlap(previousTokens, nextTokens)
    let tokenUnion = previousTokens.union(nextTokens)
    let tokenDeltaRatio = tokenUnion.isEmpty ? 0 : Double(
      previousTokens.subtracting(nextTokens).count + nextTokens.subtracting(previousTokens).count
    ) / Double(tokenUnion.count)
    let previousSignalText = signalResult(previousResult)
    let nextSignalText = signalResult(nextResult)
    let structuredChange = structuredSignals(previousSignalText) != structuredSignals(nextSignalText)
    let polarityChange = polarity(previousSignalText) != polarity(nextSignalText)
    return structuredChange ||
      polarityChange ||
      semanticOverlap < materialChangeOverlap ||
      tokenDeltaRatio >= materialTokenDeltaRatio
  }

  private static func comparableResult(_ value: String) -> String {
    value
      .replacingOccurrences(of: urlPattern, with: " ", options: .regularExpression)
      .replacingOccurrences(of: monitorMarkerPattern, with: " ", options: .regularExpression)
      .replacingOccurrences(of: resultPunctuationPattern, with: " ", options: .regularExpression)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  private static func signalResult(_ value: String) -> String {
    value
      .replacingOccurrences(of: urlPattern, with: " ", options: .regularExpression)
      .replacingOccurrences(of: monitorMarkerPattern, with: " ", options: .regularExpression)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  private static func structuredSignals(_ value: String) -> Set<String> {
    var signals = Set<String>()
    regexValues(versionPattern, in: value).forEach { signals.insert($0) }
    regexValues(datePattern, in: value).forEach { signals.insert($0) }
    regexValues(percentPattern, in: value).forEach { signals.insert($0) }
    for (group, pattern) in statusGroups {
      if value.range(of: pattern, options: .regularExpression) != nil {
        signals.insert(group)
      }
    }
    if positiveStatusCjk.contains(where: { value.contains($0) }) { signals.insert("status:positive") }
    if negativeStatusCjk.contains(where: { value.contains($0) }) { signals.insert("status:negative") }
    if requiredStatusCjk.contains(where: { value.contains($0) }) { signals.insert("requirement:required") }
    if optionalStatusCjk.contains(where: { value.contains($0) }) { signals.insert("requirement:optional") }
    return signals
  }

  private static func polarity(_ value: String) -> Int {
    if value.range(of: negationPattern, options: .regularExpression) != nil ||
      negationSignals.contains(where: { value.contains($0) }) {
      return -1
    }
    return 1
  }

  private static func regexValues(_ pattern: String, in value: String) -> [String] {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return expression.matches(in: value, options: [], range: range).compactMap { match in
      guard let range = Range(match.range, in: value) else { return nil }
      return String(value[range])
    }
  }

  private static let materialChangeOverlap = 0.82
  private static let materialTokenDeltaRatio = 0.28
  private static let resultPunctuationPattern = #"[.,;:!?()\[\]{}]"#
  private static let urlPattern = #"https?://\S+"#
  private static let monitorMarkerPattern = #"(?im)^\s*material[_ ]change\s*[:=]\s*(yes|no)\s*$"#
  private static let versionPattern = #"(?i)\b(?:v(?:ersion)?\s*)?\d+(?:\.\d+){1,4}(?:[-+._][a-z0-9]+)?\b"#
  private static let datePattern = #"\b20\d{2}[-/.](?:0?[1-9]|1[0-2])[-/.](?:0?[1-9]|[12]\d|3[01])\b"#
  private static let percentPattern = #"\b\d+(?:\.\d+)?%"#
  private static let statusGroups = [
    "status:positive": #"\b(supported|released|available|fixed)\b"#,
    "status:negative": #"\b(unsupported|deprecated|removed|blocked|vulnerable|breaking)\b"#,
    "requirement:required": #"\b(required|mandatory)\b"#,
    "requirement:optional": #"\b(optional|recommended)\b"#
  ]
  private static let positiveStatusCjk = ["\u{652f}\u{6301}", "\u{53d1}\u{5e03}", "\u{53ef}\u{7528}", "\u{5df2}\u{4fee}\u{590d}"]
  private static let negativeStatusCjk = [
    "\u{4e0d}\u{652f}\u{6301}", "\u{5df2}\u{5e9f}\u{5f03}", "\u{5df2}\u{79fb}\u{9664}",
    "\u{53d7}\u{963b}", "\u{6f0f}\u{6d1e}", "\u{7834}\u{574f}\u{6027}"
  ]
  private static let requiredStatusCjk = ["\u{5fc5}\u{987b}", "\u{5f3a}\u{5236}", "\u{8981}\u{6c42}"]
  private static let optionalStatusCjk = ["\u{53ef}\u{9009}", "\u{5efa}\u{8bae}"]
  private static let negationPattern = #"\b(no|not|never|without|cannot|unsupported)\b"#
  private static let negationSignals = [
    "\u{4e0d}\u{652f}\u{6301}", "\u{4e0d}\u{80fd}", "\u{65e0}\u{6cd5}",
    "\u{672a}\u{901a}\u{8fc7}", "\u{6ca1}\u{6709}"
  ]
  private static let minimumMonitorIntervalMillis: Int64 = 60 * 60 * 1_000
  private static let defaultMonitorIntervalMillis: Int64 = 24 * 60 * 60 * 1_000
  private static let maximumMonitorIntervalMillis: Int64 = 30 * 24 * 60 * 60 * 1_000
}

private func researchTaskPolicyUniqueStrings(_ values: [String]) -> [String] {
  var seen = Set<String>()
  var result: [String] = []
  for value in values where seen.insert(value).inserted {
    result.append(value)
  }
  return result
}
