import Foundation

enum AgentFailureRecoveryAction: String, Codable, CaseIterable, Identifiable {
  case retry = "retry"
  case switchAgent = "switch_agent"
  case degrade = "degrade"
  case diagnostics = "diagnostics"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentFailureRecoveryAction? {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return allCases.first { $0.rawValue == normalized }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    guard let action = Self.fromWireValue(try container.decode(String.self)) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown recovery action")
    }
    self = action
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentFailureRecoveryPayload: Codable, Equatable {
  var action: AgentFailureRecoveryAction
  var taskId: String
  var conversationId: String
  var turnId: String
  var agentId: String
  var originalGoal: String
  var failure: String

  enum CodingKeys: String, CodingKey {
    case version
    case action
    case taskId = "task_id"
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case agentId = "agent_id"
    case originalGoal = "original_goal"
    case failure
  }

  init(
    action: AgentFailureRecoveryAction,
    taskId: String,
    conversationId: String,
    turnId: String,
    agentId: String,
    originalGoal: String,
    failure: String
  ) {
    self.action = action
    self.taskId = taskId
    self.conversationId = conversationId
    self.turnId = turnId
    self.agentId = agentId
    self.originalGoal = originalGoal
    self.failure = failure
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      action: try container.decode(AgentFailureRecoveryAction.self, forKey: .action),
      taskId: Self.bounded(try container.decodeIfPresent(String.self, forKey: .taskId) ?? "", limit: Self.maximumIdLength),
      conversationId: Self.bounded(try container.decodeIfPresent(String.self, forKey: .conversationId) ?? "", limit: Self.maximumIdLength),
      turnId: Self.bounded(try container.decodeIfPresent(String.self, forKey: .turnId) ?? "", limit: Self.maximumIdLength),
      agentId: Self.bounded(try container.decodeIfPresent(String.self, forKey: .agentId) ?? "", limit: Self.maximumIdLength),
      originalGoal: Self.bounded(try container.decodeIfPresent(String.self, forKey: .originalGoal) ?? "", limit: Self.maximumGoalLength),
      failure: Self.bounded(try container.decodeIfPresent(String.self, forKey: .failure) ?? "", limit: Self.maximumFailureLength)
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(1, forKey: .version)
    try container.encode(action, forKey: .action)
    try container.encode(Self.bounded(taskId, limit: Self.maximumIdLength), forKey: .taskId)
    try container.encode(Self.bounded(conversationId, limit: Self.maximumIdLength), forKey: .conversationId)
    try container.encode(Self.bounded(turnId, limit: Self.maximumIdLength), forKey: .turnId)
    try container.encode(Self.bounded(agentId, limit: Self.maximumIdLength), forKey: .agentId)
    try container.encode(Self.bounded(originalGoal, limit: Self.maximumGoalLength), forKey: .originalGoal)
    try container.encode(Self.bounded(failure, limit: Self.maximumFailureLength), forKey: .failure)
  }

  func encode() -> String {
    guard let data = try? JSONEncoder().encode(self) else {
      return "{}"
    }
    return String(decoding: data, as: UTF8.self)
  }

  static func decode(_ raw: String) -> AgentFailureRecoveryPayload? {
    guard let data = raw.data(using: .utf8) else {
      return nil
    }
    return try? JSONDecoder().decode(AgentFailureRecoveryPayload.self, from: data)
  }

  private static func bounded(_ value: String, limit: Int) -> String {
    String(value.prefix(limit))
  }

  private static let maximumIdLength = 160
  private static let maximumGoalLength = 16_000
  private static let maximumFailureLength = 2_000
}

enum AgentFailureRecoveryPolicy {
  static func recommended(status: String, failure: String) -> AgentFailureRecoveryAction {
    let normalized = "\(status.lowercased()) \(failure.lowercased())"
    if normalized.contains("timeout") ||
      normalized.contains("timed out") ||
      normalized.contains("temporar") ||
      normalized.contains("network") {
      return .retry
    }
    if normalized.contains("unavailable") ||
      normalized.contains("not installed") ||
      normalized.contains("not found") {
      return .switchAgent
    }
    if normalized.contains("permission") ||
      normalized.contains("approval") ||
      normalized.contains("verif") {
      return .degrade
    }
    return .diagnostics
  }

  static func executionMode(for action: AgentFailureRecoveryAction) -> AgentTaskExecutionMode? {
    switch action {
    case .degrade, .diagnostics:
      return .planOnly
    case .retry, .switchAgent:
      return nil
    }
  }

  static func instruction(payload: AgentFailureRecoveryPayload, chinese: Bool) -> String {
    let goal = payload.originalGoal.trimmingCharacters(in: .whitespacesAndNewlines)
    let failure = payload.failure.trimmingCharacters(in: .whitespacesAndNewlines)
    let request: String
    switch payload.action {
    case .retry:
      request = "Retry the previous task from its latest safe checkpoint. Preserve verified results and do not repeat successful side effects."
    case .switchAgent:
      request = "Continue the previous goal with another currently available Agent, using the existing context and verified evidence."
    case .degrade:
      request = "Use a read-only safe fallback for the previous goal. Do not perform side effects; return a viable plan and unmet prerequisites."
    case .diagnostics:
      request = "Only diagnose why the previous task failed. Do not retry or perform side effects. Return the failure type, available resources, and the smallest next step."
    }
    var result = request
    if chinese {
      result += "\nRespond in Simplified Chinese."
    }
    if !goal.isEmpty {
      result += "\n\nOriginal goal:\n\(goal)"
    }
    if !failure.isEmpty {
      result += "\n\nObserved failure:\n\(failure)"
    }
    return result
  }
}

enum AgentFailureDetailPolicy {
  static func visibleMessage(error: String, fallback: String) -> String {
    let normalized = error
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "[\\r\\n]{3,}", with: "\n\n", options: .regularExpression)
    return String(normalized.prefix(maximumVisibleCharacters))
      .ifBlank(fallback.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private static let maximumVisibleCharacters = 6_000
}

struct AgentFailureRecoveryAdvertisedAction: Codable, Equatable, Identifiable {
  var id: String { action.rawValue }
  var action: AgentFailureRecoveryAction
  var enabled: Bool
  var recommended: Bool
  var label: String

  init(
    action: AgentFailureRecoveryAction,
    enabled: Bool = true,
    recommended: Bool = false,
    label: String = ""
  ) {
    self.action = action
    self.enabled = enabled
    self.recommended = recommended
    self.label = label
  }
}

enum AgentFailureRecoveryRichContent {
  static let actionVerb = "recover_agent_task"

  static func recoveryBlock(
    signal: AgentNoReplySignal,
    taskId: String,
    conversationId: String,
    turnId: String,
    agentId: String,
    originalGoal: String,
    advertisedActions: [AgentFailureRecoveryAdvertisedAction] = [],
    chinese: Bool = false
  ) -> AgentRichBlock? {
    let display = AgentNoReplyReasonPolicy.display(for: signal, chinese: chinese)
    return recoveryBlock(
      taskId: taskId,
      conversationId: conversationId,
      turnId: turnId,
      agentId: agentId,
      originalGoal: originalGoal,
      failure: signal.error.ifBlank(display.message),
      status: signal.taskStatus,
      title: display.title,
      message: display.message,
      noReplyReason: display.reason.rawValue,
      advertisedActions: advertisedActions,
      chinese: chinese
    )
  }

  static func recoveryBlock(
    taskId: String,
    conversationId: String,
    turnId: String,
    agentId: String,
    originalGoal: String,
    failure: String,
    status: String,
    title: String,
    message: String,
    noReplyReason: String = "",
    advertisedActions: [AgentFailureRecoveryAdvertisedAction] = [],
    chinese: Bool = false
  ) -> AgentRichBlock? {
    let cleanTaskId = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanConversationId = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTaskId.isEmpty, !cleanConversationId.isEmpty else { return nil }

    let actions = recoveryActions(
      taskId: cleanTaskId,
      conversationId: cleanConversationId,
      turnId: turnId,
      agentId: agentId,
      originalGoal: originalGoal,
      failure: failure,
      status: status,
      advertisedActions: advertisedActions,
      chinese: chinese
    )
    guard !actions.isEmpty else { return nil }
    let recommended = recommendedAction(status: status, failure: failure, advertisedActions: advertisedActions)
    let body = AgentFailureDetailPolicy.visibleMessage(error: failure, fallback: message)
    return AgentRichBlock(
      id: "recovery-\(String(cleanTaskId.prefix(96)))",
      type: .actions,
      title: title.ifBlank("Agent task needs recovery"),
      text: body,
      fallbackText: body,
      actions: actions,
      metadata: [
        "task_id": cleanTaskId,
        "no_reply_reason": normalizedToken(noReplyReason),
        "recommended_action": recommended.rawValue
      ]
    )
  }

  static func recoveryActions(
    taskId: String,
    conversationId: String,
    turnId: String,
    agentId: String,
    originalGoal: String,
    failure: String,
    status: String,
    advertisedActions: [AgentFailureRecoveryAdvertisedAction] = [],
    chinese: Bool = false
  ) -> [AgentRichAction] {
    let advertisedByAction = advertisedActions.reduce(into: [AgentFailureRecoveryAction: AgentFailureRecoveryAdvertisedAction]()) {
      values, item in
      values[item.action] = item
    }
    let recommended = recommendedAction(status: status, failure: failure, advertisedActions: advertisedActions)
    return AgentFailureRecoveryAction.allCases.compactMap { action in
      if advertisedByAction[action]?.enabled == false {
        return nil
      }
      let payload = AgentFailureRecoveryPayload(
        action: action,
        taskId: taskId,
        conversationId: conversationId,
        turnId: turnId,
        agentId: agentId,
        originalGoal: originalGoal,
        failure: failure
      )
      return AgentRichAction(
        id: "recovery-\(action.rawValue)",
        label: advertisedByAction[action]?.label.ifBlank(label(for: action, chinese: chinese))
          ?? label(for: action, chinese: chinese),
        verb: actionVerb,
        value: payload.encode(),
        style: action == recommended ? "primary" : "default"
      )
    }
  }

  static func connectorAction(
    payload: AgentFailureRecoveryPayload,
    turnId: String,
    targets: [AgentCallableTarget],
    prompt: String? = nil,
    chinese: Bool = false
  ) -> AgentAction? {
    let availableTargets = targets.filter(AgentConnectorRouteSelector.isDeliverable)
    let current = canonical(payload.agentId)
    let target: AgentCallableTarget?
    switch payload.action {
    case .switchAgent:
      target = availableTargets.first { !matches($0, identifier: current) }
    case .retry, .degrade, .diagnostics:
      target = availableTargets.first { matches($0, identifier: current) }
    }
    guard let target else { return nil }
    let resolvedPrompt = prompt ?? AgentFailureRecoveryPolicy.instruction(payload: payload, chinese: chinese)
    return AgentAction(
      id: "recovery-\(payload.action.rawValue)-\(String(turnId.prefix(96)))",
      kind: .callConnector,
      target: target.title,
      risk: .low,
      status: .pendingConfirmation,
      description: "Continue a failed task with \(target.title)",
      parameters: [
        "connector_id": target.id,
        "prompt": resolvedPrompt,
        "recovery_of_task_id": payload.taskId,
        "recovery_action": payload.action.rawValue
      ],
      requiresConfirmation: false
    )
  }

  static func label(for action: AgentFailureRecoveryAction, chinese: Bool = false) -> String {
    let presentation: (key: String, fallback: String)
    switch action {
    case .retry: presentation = ("agent_failure_recovery_retry", "Retry")
    case .switchAgent: presentation = ("agent_failure_recovery_switch_agent", "Switch Agent")
    case .degrade: presentation = ("agent_failure_recovery_safe_fallback", "Safe fallback")
    case .diagnostics: presentation = ("agent_failure_recovery_diagnostics", "Diagnostics")
    }
    return SignalASILocalization.string(
      presentation.key,
      fallback: presentation.fallback,
      language: chinese ? LanguagePolicySettings.zhCN : LanguagePolicySettings.enUS
    )
  }

  private static func recommendedAction(
    status: String,
    failure: String,
    advertisedActions: [AgentFailureRecoveryAdvertisedAction]
  ) -> AgentFailureRecoveryAction {
    advertisedActions.first { $0.enabled && $0.recommended }?.action ??
      AgentFailureRecoveryPolicy.recommended(status: status, failure: failure)
  }

  private static func canonical(_ value: String) -> String {
    let suffix = value
      .split(separator: ":")
      .last
      .map(String.init) ?? value
    return suffix.lowercased().unicodeScalars
      .filter { CharacterSet.alphanumerics.contains($0) }
      .map(String.init)
      .joined()
  }

  private static func matches(_ target: AgentCallableTarget, identifier: String) -> Bool {
    guard !identifier.isEmpty else { return false }
    return canonical(target.id) == identifier || canonical(target.title) == identifier
  }

  private static func normalizedToken(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9_]+"#, with: "_", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
  }
}
