import Foundation

enum AgentPermissionMode: String, CaseIterable, Identifiable, Codable {
  case observeOnly = "OBSERVE_ONLY"
  case suggestOnly = "SUGGEST_ONLY"
  case askBeforeAction = "ASK_BEFORE_ACTION"
  case autoLowRisk = "AUTO_LOW_RISK"

  var id: String { rawValue }

  var displayTitle: String {
    switch self {
    case .observeOnly: return "Observe Only"
    case .suggestOnly: return "Suggest Only"
    case .askBeforeAction: return "Ask Before Action"
    case .autoLowRisk: return "Auto Low-risk"
    }
  }

  var detail: String {
    switch self {
    case .observeOnly:
      return "Read current screen and device state; never create or execute actions."
    case .suggestOnly:
      return "Build plans and suggestions, but block every executable action."
    case .askBeforeAction:
      return "Require confirmation before every executable action."
    case .autoLowRisk:
      return "Run direct actions, remember first-time consent, and always confirm high-risk actions."
    }
  }

  static func fromStoredValue(_ value: String?) -> AgentPermissionMode {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let normalized = trimmed.uppercased().replacingOccurrences(of: "-", with: "_")
    return allCases.first { $0.rawValue == normalized } ?? .askBeforeAction
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromStoredValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentSafetySettings: Codable, Equatable {
  var taskExecutionMode: AgentTaskExecutionMode
  var permissionMode: AgentPermissionMode
  var highRiskGuard: Bool
  var memoryCapture: Bool
  var screenObservationAllowed: Bool
  var localActionsAllowed: Bool
  var connectorCallsAllowed: Bool
  var deviceControlAllowed: Bool
  var executionPaused: Bool

  init(
    taskExecutionMode: AgentTaskExecutionMode = .autoComplete,
    permissionMode: AgentPermissionMode = .askBeforeAction,
    highRiskGuard: Bool = true,
    memoryCapture: Bool = true,
    screenObservationAllowed: Bool = true,
    localActionsAllowed: Bool = true,
    connectorCallsAllowed: Bool = true,
    deviceControlAllowed: Bool = true,
    executionPaused: Bool = false
  ) {
    self.taskExecutionMode = taskExecutionMode
    self.permissionMode = permissionMode
    self.highRiskGuard = highRiskGuard
    self.memoryCapture = memoryCapture
    self.screenObservationAllowed = screenObservationAllowed
    self.localActionsAllowed = localActionsAllowed
    self.connectorCallsAllowed = connectorCallsAllowed
    self.deviceControlAllowed = deviceControlAllowed
    self.executionPaused = executionPaused
  }

  static let `default` = AgentSafetySettings()

  enum CodingKeys: String, CodingKey {
    case taskExecutionMode = "task_execution_mode"
    case permissionMode = "permission_mode"
    case highRiskGuard = "high_risk_guard"
    case memoryCapture = "memory_capture"
    case screenObservationAllowed = "screen_observation_allowed"
    case localActionsAllowed = "local_actions_allowed"
    case connectorCallsAllowed = "connector_calls_allowed"
    case deviceControlAllowed = "device_control_allowed"
    case executionPaused = "execution_paused"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      taskExecutionMode: try container.decodeIfPresent(AgentTaskExecutionMode.self, forKey: .taskExecutionMode) ?? .autoComplete,
      permissionMode: try container.decodeIfPresent(AgentPermissionMode.self, forKey: .permissionMode) ?? .askBeforeAction,
      highRiskGuard: try container.decodeIfPresent(Bool.self, forKey: .highRiskGuard) ?? true,
      memoryCapture: try container.decodeIfPresent(Bool.self, forKey: .memoryCapture) ?? true,
      screenObservationAllowed: try container.decodeIfPresent(Bool.self, forKey: .screenObservationAllowed) ?? true,
      localActionsAllowed: try container.decodeIfPresent(Bool.self, forKey: .localActionsAllowed) ?? true,
      connectorCallsAllowed: try container.decodeIfPresent(Bool.self, forKey: .connectorCallsAllowed) ?? true,
      deviceControlAllowed: try container.decodeIfPresent(Bool.self, forKey: .deviceControlAllowed) ?? true,
      executionPaused: try container.decodeIfPresent(Bool.self, forKey: .executionPaused) ?? false
    )
  }
}
