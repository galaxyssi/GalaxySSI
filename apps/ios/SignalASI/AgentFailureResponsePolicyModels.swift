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
