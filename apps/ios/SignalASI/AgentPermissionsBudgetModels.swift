import Foundation

struct AgentAction: Codable, Equatable, Identifiable {
  var id: String
  var kind: AgentActionKind
  var target: String
  var risk: AgentRisk
  var status: AgentActionStatus
  var description: String
  var parameters: [String: String]
  var requiresConfirmation: Bool
  var result: String
  var evidence: String

  init(
    id: String,
    kind: AgentActionKind,
    target: String,
    risk: AgentRisk,
    status: AgentActionStatus,
    description: String,
    parameters: [String: String] = [:],
    requiresConfirmation: Bool = true,
    result: String = "",
    evidence: String = ""
  ) {
    self.id = id
    self.kind = kind
    self.target = target
    self.risk = risk
    self.status = status
    self.description = description
    self.parameters = parameters
    self.requiresConfirmation = requiresConfirmation
    self.result = result
    self.evidence = evidence
  }

  enum CodingKeys: String, CodingKey {
    case id
    case kind
    case target
    case risk
    case status
    case description
    case parameters
    case requiresConfirmation = "requires_confirmation"
    case result
    case evidence
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      kind: try container.decodeIfPresent(AgentActionKind.self, forKey: .kind) ?? .draftPlan,
      target: try container.decodeIfPresent(String.self, forKey: .target) ?? "",
      risk: try container.decodeIfPresent(AgentRisk.self, forKey: .risk) ?? .medium,
      status: try container.decodeIfPresent(AgentActionStatus.self, forKey: .status) ?? .pendingConfirmation,
      description: try container.decodeIfPresent(String.self, forKey: .description) ?? "",
      parameters: try container.decodeIfPresent([String: String].self, forKey: .parameters) ?? [:],
      requiresConfirmation: try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) ?? true,
      result: try container.decodeIfPresent(String.self, forKey: .result) ?? "",
      evidence: try container.decodeIfPresent(String.self, forKey: .evidence) ?? ""
    )
  }
}

protocol AgentActionExecutor {
  func execute(action: AgentAction, screen: AgentScreenContext) -> AgentActionResult
}

struct PhoneExecutionAuthoritySnapshot: Codable, Equatable {
  var activeSideEffectTaskId: String
  var queuedSideEffectTasks: Int
  var cancelledTaskCount: Int

  init(
    activeSideEffectTaskId: String = "",
    queuedSideEffectTasks: Int = 0,
    cancelledTaskCount: Int = 0
  ) {
    self.activeSideEffectTaskId = activeSideEffectTaskId
    self.queuedSideEffectTasks = max(queuedSideEffectTasks, 0)
    self.cancelledTaskCount = max(cancelledTaskCount, 0)
  }

  enum CodingKeys: String, CodingKey {
    case activeSideEffectTaskId = "active_side_effect_task_id"
    case queuedSideEffectTasks = "queued_side_effect_tasks"
    case cancelledTaskCount = "cancelled_task_count"
  }
}

enum PhoneExecutionAuthority {
  static func guarded(_ delegate: AgentActionExecutor) -> AgentActionExecutor {
    GuardedExecutor(delegate: delegate)
  }

  static func requestCancellation(taskId: String) {
    let normalized = normalize(taskId)
    guard !normalized.isEmpty else { return }
    stateLock.lock()
    cancelledTasks.insert(normalized)
    stateLock.unlock()
  }

  static func clearCancellation(taskId: String) {
    let normalized = normalize(taskId)
    guard !normalized.isEmpty else { return }
    stateLock.lock()
    cancelledTasks.remove(normalized)
    stateLock.unlock()
  }

  static func isCancelled(taskId: String) -> Bool {
    let normalized = normalize(taskId)
    guard !normalized.isEmpty else { return false }
    stateLock.lock()
    let cancelled = cancelledTasks.contains(normalized)
    stateLock.unlock()
    return cancelled
  }

  static func snapshot() -> PhoneExecutionAuthoritySnapshot {
    stateLock.lock()
    let snapshot = PhoneExecutionAuthoritySnapshot(
      activeSideEffectTaskId: activeSideEffectTask,
      queuedSideEffectTasks: queuedSideEffectTasks,
      cancelledTaskCount: cancelledTasks.count
    )
    stateLock.unlock()
    return snapshot
  }

  fileprivate static func execute(
    delegate: AgentActionExecutor,
    action: AgentAction,
    screen: AgentScreenContext
  ) -> AgentActionResult {
    let taskId = taskId(for: action)
    if isCancelled(taskId: taskId) {
      return cancelledResult(action: action, taskId: taskId)
    }
    if action.kind.runsOutsidePhoneSideEffectLock {
      return delegate.execute(action: action, screen: screen)
        .withAuthorityMetadata(taskId: taskId, serialized: false)
    }

    stateLock.lock()
    queuedSideEffectTasks += 1
    stateLock.unlock()
    sideEffectLock.lock()
    stateLock.lock()
    queuedSideEffectTasks = max(queuedSideEffectTasks - 1, 0)
    activeSideEffectTask = taskId
    stateLock.unlock()
    defer {
      stateLock.lock()
      if activeSideEffectTask == taskId {
        activeSideEffectTask = ""
      }
      stateLock.unlock()
      sideEffectLock.unlock()
    }

    if isCancelled(taskId: taskId) {
      return cancelledResult(action: action, taskId: taskId)
    }
    return delegate.execute(action: action, screen: screen)
      .withAuthorityMetadata(taskId: taskId, serialized: true)
  }

  private static func taskId(for action: AgentAction) -> String {
    let candidate = normalize(action.parameters[taskIdParameter] ?? "")
    return candidate.isEmpty ? action.id : candidate
  }

  private static func cancelledResult(action: AgentAction, taskId: String) -> AgentActionResult {
    AgentActionResult(
      actionId: action.id,
      success: false,
      message: "Phone tool execution was cancelled",
      metadata: [
        "execution_location": "phone",
        "execution_authority": "signalasi-phone",
        "task_id": taskId,
        "cancelled": "true"
      ]
    )
  }

  private static func normalize(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static let taskIdParameter = "_signalasi_task_id"
  private static let sideEffectLock = NSLock()
  private static let stateLock = NSLock()
  private static var activeSideEffectTask = ""
  private static var queuedSideEffectTasks = 0
  private static var cancelledTasks: Set<String> = []

  private final class GuardedExecutor: AgentActionExecutor {
    private let delegate: AgentActionExecutor

    init(delegate: AgentActionExecutor) {
      self.delegate = delegate
    }

    func execute(action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
      PhoneExecutionAuthority.execute(delegate: delegate, action: action, screen: screen)
    }
  }
}

private extension AgentActionKind {
  var runsOutsidePhoneSideEffectLock: Bool {
    self == .readScreen || self == .draftPlan || self == .callConnector
  }
}

private extension AgentActionResult {
  func withAuthorityMetadata(taskId: String, serialized: Bool) -> AgentActionResult {
    var value = self
    value.metadata.merge([
      "execution_location": "phone",
      "execution_authority": "signalasi-phone",
      "task_id": taskId,
      "serialized_side_effect": serialized.description
    ]) { _, new in new }
    return value
  }
}

struct AgentActionRecoveryController {
  func recover(
    action: AgentAction,
    failedResult: AgentActionResult?,
    failedObservation: AgentObservationOutcome,
    retry: () -> AgentRecoveryAttempt
  ) -> AgentRecoveryOutcome {
    guard failedResult?.success == false else {
      return AgentRecoveryOutcome(
        result: failedResult,
        observation: failedObservation,
        decision: .notNeeded,
        attemptCount: 0
      )
    }
    guard supportsAutomaticRecovery(action),
      failedObservation.decision == .timedOut else {
      return AgentRecoveryOutcome(
        result: failedResult,
        observation: failedObservation,
        decision: .manualRequired,
        attemptCount: 0
      )
    }

    let attempt = retry()
    return AgentRecoveryOutcome(
      result: attempt.result,
      observation: attempt.observation,
      decision: attempt.result?.success == true ? .retrySucceeded : .retryFailed,
      attemptCount: 1
    )
  }

  private func supportsAutomaticRecovery(_ action: AgentAction) -> Bool {
    action.risk == .low && Self.safeRetryActions.contains(action.kind)
  }

  private static let safeRetryActions: Set<AgentActionKind> = [.openApp, .home, .recents]
}

enum AgentActionRiskHardener {
  static let minConfidentVisualAction = 0.70

  static func enforce(plan: AgentPlan) -> AgentPlan {
    enforce(plan: plan, customDeviceRisks: [:])
  }

  static func enforce(
    plan: AgentPlan,
    customDeviceConnectors: [CustomDeviceConnector],
    homeAssistantSettings: HomeAssistantSettings = .default
  ) -> AgentPlan {
    var customDeviceRisks: [String: CustomDeviceRisk] = [:]
    for connector in customDeviceConnectors {
      customDeviceRisks[connector.id] = connector.risk
    }
    return enforce(
      plan: plan,
      customDeviceRisks: customDeviceRisks,
      homeAssistantDefaultEntityId: homeAssistantSettings.defaultEntityId
    )
  }

  static func enforce(
    plan: AgentPlan,
    customDeviceRisks: [String: CustomDeviceRisk],
    homeAssistantDefaultEntityId: String = ""
  ) -> AgentPlan {
    let actions = plan.actions.map { action in
      var copy = action
      copy.risk = higherRisk(
        action.risk,
        hardenedRisk(
          for: action,
          customDeviceRisks: customDeviceRisks,
          homeAssistantDefaultEntityId: homeAssistantDefaultEntityId
        )
      )
      return copy
    }
    var hardened = plan
    hardened.actions = actions
    hardened.validation = AgentPlanValidator.validate(hardened)
    return hardened
  }

  private static func hardenedRisk(
    for action: AgentAction,
    customDeviceRisks: [String: CustomDeviceRisk],
    homeAssistantDefaultEntityId: String
  ) -> AgentRisk {
    switch action.kind {
    case .controlDevice:
      return deviceRisk(
        action,
        customDeviceRisks: customDeviceRisks,
        homeAssistantDefaultEntityId: homeAssistantDefaultEntityId
      )
    case .callConnector:
      return connectorRisk(action)
    case .tap, .longPress:
      return visualGroundingRisk(
        origin: action.parameters["element_origin"] ?? "",
        confidenceValue: action.parameters["element_confidence"] ?? ""
      )
    case .typeText, .deleteText, .pasteText:
      return visualGroundingRisk(
        origin: action.parameters["field_origin"] ?? "",
        confidenceValue: action.parameters["field_confidence"] ?? ""
      )
    default:
      return action.risk
    }
  }

  private static func deviceRisk(
    _ action: AgentAction,
    customDeviceRisks: [String: CustomDeviceRisk],
    homeAssistantDefaultEntityId: String
  ) -> AgentRisk {
    let connectorId = (action.parameters["connector_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if connectorId.hasPrefix(customDevicePrefix) {
      let customDeviceId = String(connectorId.dropFirst(customDevicePrefix.count))
      guard let risk = customDeviceRisks[customDeviceId] else { return .high }
      return agentRisk(for: risk)
    }
    if connectorId == homeAssistantConnectorId {
      return AgentHomeAssistantRiskPolicy.riskForPrompt(
        action.parameters["prompt"] ?? "",
        defaultEntityId: homeAssistantDefaultEntityId
      )
    }
    return .high
  }

  private static func connectorRisk(_ action: AgentAction) -> AgentRisk {
    let value = [
      action.description,
      action.target,
      action.parameters["prompt"] ?? ""
    ].joined(separator: " ").lowercased()
    return highRiskConnectorTerms.contains(where: { value.contains($0) }) ? .high : action.risk
  }

  private static func visualGroundingRisk(origin: String, confidenceValue: String) -> AgentRisk {
    guard AgentElementOrigin.fromWireValue(origin) == .visualOcr else {
      return .low
    }
    let confidence = Double(confidenceValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    return confidence < minConfidentVisualAction ? .high : .medium
  }

  private static func higherRisk(_ first: AgentRisk, _ second: AgentRisk) -> AgentRisk {
    first.weight >= second.weight ? first : second
  }

  private static func agentRisk(for risk: CustomDeviceRisk) -> AgentRisk {
    switch risk {
    case .low: return .low
    case .medium: return .medium
    case .high: return .high
    }
  }

  private static let customDevicePrefix = "custom-device:"
  private static let homeAssistantConnectorId = "home-assistant"
  private static let highRiskConnectorTerms = [
    "delete", "erase", "remove account", "install", "uninstall", "deploy", "publish",
    "send message", "send email", "payment", "purchase", "buy", "order", "transfer",
    "credential", "password", "private key", "api key", "unlock", "open door",
    "\u{5220}\u{9664}", "\u{6e05}\u{9664}", "\u{5b89}\u{88c5}", "\u{5378}\u{8f7d}",
    "\u{90e8}\u{7f72}", "\u{53d1}\u{5e03}", "\u{53d1}\u{9001}", "\u{652f}\u{4ed8}",
    "\u{8d2d}\u{4e70}", "\u{8f6c}\u{8d26}", "\u{5bc6}\u{7801}", "\u{79c1}\u{94a5}",
    "\u{89e3}\u{9501}", "\u{5f00}\u{95e8}"
  ]
}

enum AgentHomeAssistantRiskPolicy {
  static func riskForPrompt(_ prompt: String, defaultEntityId: String = "") -> AgentRisk {
    riskForEntity(
      prompt: prompt,
      entityId: entityId(for: prompt, defaultEntityId: defaultEntityId)
    )
  }

  static func entityId(for prompt: String, defaultEntityId: String = "") -> String {
    AgentHomeAssistantPromptRouter.entityId(for: prompt, defaultEntityId: defaultEntityId)
  }

  private static func riskForEntity(prompt: String, entityId: String) -> AgentRisk {
    let lower = prompt.lowercased()
    let domain = entityId.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
    if highRiskControlDomains.contains(domain) {
      return .high
    }
    if domain == "cover" && highRiskControlTerms.contains(where: { lower.contains($0) }) {
      return .high
    }
    if mediumRiskControlDomains.contains(domain) {
      return .medium
    }
    if highRiskControlTerms.contains(where: { lower.contains($0) }) {
      return .high
    }
    if mediumRiskControlTerms.contains(where: { lower.contains($0) }) {
      return .medium
    }
    return .low
  }

  private static let highRiskControlDomains: Set<String> = [
    "alarm_control_panel",
    "automation",
    "camera",
    "lock",
    "siren",
    "script",
    "valve"
  ]
  private static let mediumRiskControlDomains: Set<String> = [
    "climate",
    "cover",
    "fan",
    "scene",
    "switch",
    "vacuum"
  ]
  private static let highRiskControlTerms = [
    "alarm",
    "camera",
    "door",
    "gate",
    "garage",
    "lock",
    "security",
    "siren",
    "valve"
  ]
  private static let mediumRiskControlTerms = [
    "automation",
    "blind",
    "climate",
    "cover",
    "curtain",
    "scene",
    "script",
    "switch",
    "thermostat"
  ]
}

struct GlobalAgentSettings: Codable, Equatable {
  var backgroundCognitionArchitectureVersion: Int
  var enabled: Bool
  var proactiveInsightsEnabled: Bool
  var proactiveDiscoveryEnabled: Bool
  var modelUnderstandingEnabled: Bool
  var autonomousPreparationEnabled: Bool
  var autonomousToolExecutionEnabled: Bool
  var dynamicAutonomousReplanningEnabled: Bool
  var longHorizonPlanningEnabled: Bool
  var maxAutonomousReplans: Int
  var allowCloudCognition: Bool
  var allowPairedAgentCognition: Bool
  var autonomousResearchEnabled: Bool
  var autoCreateConversationsEnabled: Bool
  var notificationsEnabled: Bool
  var adaptiveLearningEnabled: Bool
  var allowMeteredBackgroundResearch: Bool
  var dailyBackgroundModelCallBudget: Int
  var maxConcurrentBackgroundModelCalls: Int
  var dailyBackgroundTokenBudget: Int64
  var dailyBackgroundReportedCostBudgetMicros: Int64
  var dailyMessageBudget: Int
  var dailyDiscoveryTaskBudget: Int
  var topicCooldownMillis: Int64
  var discoveryIntervalMillis: Int64
  var monitorIntervalMillis: Int64

  static let `default` = GlobalAgentSettings()

  init(
    backgroundCognitionArchitectureVersion: Int = 1,
    enabled: Bool = true,
    proactiveInsightsEnabled: Bool = true,
    proactiveDiscoveryEnabled: Bool = true,
    modelUnderstandingEnabled: Bool = true,
    autonomousPreparationEnabled: Bool = true,
    autonomousToolExecutionEnabled: Bool = true,
    dynamicAutonomousReplanningEnabled: Bool = true,
    longHorizonPlanningEnabled: Bool = true,
    maxAutonomousReplans: Int = 3,
    allowCloudCognition: Bool = false,
    allowPairedAgentCognition: Bool = false,
    autonomousResearchEnabled: Bool = true,
    autoCreateConversationsEnabled: Bool = true,
    notificationsEnabled: Bool = true,
    adaptiveLearningEnabled: Bool = true,
    allowMeteredBackgroundResearch: Bool = false,
    dailyBackgroundModelCallBudget: Int = 48,
    maxConcurrentBackgroundModelCalls: Int = 3,
    dailyBackgroundTokenBudget: Int64 = 250_000,
    dailyBackgroundReportedCostBudgetMicros: Int64 = 1_000_000,
    dailyMessageBudget: Int = 4,
    dailyDiscoveryTaskBudget: Int = 3,
    topicCooldownMillis: Int64 = 6 * 60 * 60 * 1_000,
    discoveryIntervalMillis: Int64 = 4 * 60 * 60 * 1_000,
    monitorIntervalMillis: Int64 = 24 * 60 * 60 * 1_000
  ) {
    self.backgroundCognitionArchitectureVersion = max(backgroundCognitionArchitectureVersion, 1)
    self.enabled = enabled
    self.proactiveInsightsEnabled = proactiveInsightsEnabled
    self.proactiveDiscoveryEnabled = proactiveDiscoveryEnabled
    self.modelUnderstandingEnabled = modelUnderstandingEnabled
    self.autonomousPreparationEnabled = autonomousPreparationEnabled
    self.autonomousToolExecutionEnabled = autonomousToolExecutionEnabled
    self.dynamicAutonomousReplanningEnabled = dynamicAutonomousReplanningEnabled
    self.longHorizonPlanningEnabled = longHorizonPlanningEnabled
    self.maxAutonomousReplans = max(0, min(maxAutonomousReplans, 24))
    self.allowCloudCognition = allowCloudCognition
    self.allowPairedAgentCognition = allowPairedAgentCognition
    self.autonomousResearchEnabled = autonomousResearchEnabled
    self.autoCreateConversationsEnabled = autoCreateConversationsEnabled
    self.notificationsEnabled = notificationsEnabled
    self.adaptiveLearningEnabled = adaptiveLearningEnabled
    self.allowMeteredBackgroundResearch = allowMeteredBackgroundResearch
    self.dailyBackgroundModelCallBudget = max(0, min(dailyBackgroundModelCallBudget, 1_000))
    self.maxConcurrentBackgroundModelCalls = max(1, min(maxConcurrentBackgroundModelCalls, 24))
    self.dailyBackgroundTokenBudget = max(0, min(dailyBackgroundTokenBudget, 100_000_000))
    self.dailyBackgroundReportedCostBudgetMicros = max(0, min(dailyBackgroundReportedCostBudgetMicros, 1_000_000_000))
    self.dailyMessageBudget = max(0, min(dailyMessageBudget, 200))
    self.dailyDiscoveryTaskBudget = max(0, min(dailyDiscoveryTaskBudget, 200))
    self.topicCooldownMillis = max(0, min(topicCooldownMillis, 30 * 24 * 60 * 60 * 1_000))
    self.discoveryIntervalMillis = max(60_000, min(discoveryIntervalMillis, 30 * 24 * 60 * 60 * 1_000))
    self.monitorIntervalMillis = max(60_000, min(monitorIntervalMillis, 30 * 24 * 60 * 60 * 1_000))
  }

  enum CodingKeys: String, CodingKey {
    case backgroundCognitionArchitectureVersion = "background_cognition_architecture_version"
    case enabled
    case proactiveInsightsEnabled = "proactive_insights_enabled"
    case proactiveDiscoveryEnabled = "proactive_discovery_enabled"
    case modelUnderstandingEnabled = "model_understanding_enabled"
    case autonomousPreparationEnabled = "autonomous_preparation_enabled"
    case autonomousToolExecutionEnabled = "autonomous_tool_execution_enabled"
    case dynamicAutonomousReplanningEnabled = "dynamic_autonomous_replanning_enabled"
    case longHorizonPlanningEnabled = "long_horizon_planning_enabled"
    case maxAutonomousReplans = "max_autonomous_replans"
    case allowCloudCognition = "allow_cloud_cognition"
    case allowPairedAgentCognition = "allow_paired_agent_cognition"
    case autonomousResearchEnabled = "autonomous_research_enabled"
    case autoCreateConversationsEnabled = "auto_create_conversations_enabled"
    case notificationsEnabled = "notifications_enabled"
    case adaptiveLearningEnabled = "adaptive_learning_enabled"
    case allowMeteredBackgroundResearch = "allow_metered_background_research"
    case dailyBackgroundModelCallBudget = "daily_background_model_call_budget"
    case maxConcurrentBackgroundModelCalls = "max_concurrent_background_model_calls"
    case dailyBackgroundTokenBudget = "daily_background_token_budget"
    case dailyBackgroundReportedCostBudgetMicros = "daily_background_reported_cost_budget_micros"
    case dailyMessageBudget = "daily_message_budget"
    case dailyDiscoveryTaskBudget = "daily_discovery_task_budget"
    case topicCooldownMillis = "topic_cooldown_millis"
    case discoveryIntervalMillis = "discovery_interval_millis"
    case monitorIntervalMillis = "monitor_interval_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let fallback = Self.default
    let architectureVersion = try container.decodeIfPresent(Int.self, forKey: .backgroundCognitionArchitectureVersion) ?? 0
    self.init(
      backgroundCognitionArchitectureVersion: 1,
      enabled: architectureVersion < 1
        ? true
        : (try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true),
      proactiveInsightsEnabled: try container.decodeIfPresent(Bool.self, forKey: .proactiveInsightsEnabled) ?? fallback.proactiveInsightsEnabled,
      proactiveDiscoveryEnabled: try container.decodeIfPresent(Bool.self, forKey: .proactiveDiscoveryEnabled) ?? fallback.proactiveDiscoveryEnabled,
      modelUnderstandingEnabled: try container.decodeIfPresent(Bool.self, forKey: .modelUnderstandingEnabled) ?? fallback.modelUnderstandingEnabled,
      autonomousPreparationEnabled: try container.decodeIfPresent(Bool.self, forKey: .autonomousPreparationEnabled) ?? fallback.autonomousPreparationEnabled,
      autonomousToolExecutionEnabled: try container.decodeIfPresent(Bool.self, forKey: .autonomousToolExecutionEnabled) ?? fallback.autonomousToolExecutionEnabled,
      dynamicAutonomousReplanningEnabled: try container.decodeIfPresent(Bool.self, forKey: .dynamicAutonomousReplanningEnabled) ?? fallback.dynamicAutonomousReplanningEnabled,
      longHorizonPlanningEnabled: try container.decodeIfPresent(Bool.self, forKey: .longHorizonPlanningEnabled) ?? fallback.longHorizonPlanningEnabled,
      maxAutonomousReplans: try container.decodeIfPresent(Int.self, forKey: .maxAutonomousReplans) ?? fallback.maxAutonomousReplans,
      allowCloudCognition: try container.decodeIfPresent(Bool.self, forKey: .allowCloudCognition) ?? fallback.allowCloudCognition,
      allowPairedAgentCognition: try container.decodeIfPresent(Bool.self, forKey: .allowPairedAgentCognition) ?? fallback.allowPairedAgentCognition,
      autonomousResearchEnabled: try container.decodeIfPresent(Bool.self, forKey: .autonomousResearchEnabled) ?? fallback.autonomousResearchEnabled,
      autoCreateConversationsEnabled: try container.decodeIfPresent(Bool.self, forKey: .autoCreateConversationsEnabled) ?? fallback.autoCreateConversationsEnabled,
      notificationsEnabled: try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? fallback.notificationsEnabled,
      adaptiveLearningEnabled: try container.decodeIfPresent(Bool.self, forKey: .adaptiveLearningEnabled) ?? fallback.adaptiveLearningEnabled,
      allowMeteredBackgroundResearch: try container.decodeIfPresent(Bool.self, forKey: .allowMeteredBackgroundResearch) ?? fallback.allowMeteredBackgroundResearch,
      dailyBackgroundModelCallBudget: try container.decodeIfPresent(Int.self, forKey: .dailyBackgroundModelCallBudget) ?? fallback.dailyBackgroundModelCallBudget,
      maxConcurrentBackgroundModelCalls: try container.decodeIfPresent(Int.self, forKey: .maxConcurrentBackgroundModelCalls) ?? fallback.maxConcurrentBackgroundModelCalls,
      dailyBackgroundTokenBudget: try container.decodeIfPresent(Int64.self, forKey: .dailyBackgroundTokenBudget) ?? fallback.dailyBackgroundTokenBudget,
      dailyBackgroundReportedCostBudgetMicros: try container.decodeIfPresent(Int64.self, forKey: .dailyBackgroundReportedCostBudgetMicros) ?? fallback.dailyBackgroundReportedCostBudgetMicros,
      dailyMessageBudget: try container.decodeIfPresent(Int.self, forKey: .dailyMessageBudget) ?? fallback.dailyMessageBudget,
      dailyDiscoveryTaskBudget: try container.decodeIfPresent(Int.self, forKey: .dailyDiscoveryTaskBudget) ?? fallback.dailyDiscoveryTaskBudget,
      topicCooldownMillis: try container.decodeIfPresent(Int64.self, forKey: .topicCooldownMillis) ?? fallback.topicCooldownMillis,
      discoveryIntervalMillis: try container.decodeIfPresent(Int64.self, forKey: .discoveryIntervalMillis) ?? fallback.discoveryIntervalMillis,
      monitorIntervalMillis: try container.decodeIfPresent(Int64.self, forKey: .monitorIntervalMillis) ?? fallback.monitorIntervalMillis
    )
  }
}
