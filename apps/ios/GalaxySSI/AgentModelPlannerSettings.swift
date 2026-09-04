import Foundation

struct AgentModelPlannerSettings: Codable, Equatable {
  static let maximumCloudContactIdLength = 120
  static let maximumActions = 12
  static let maximumReplans = 5
  static let maximumAgentHops = 8
  static let minimumToolCalls = 4
  static let maximumToolCalls = 32
  static let minimumLoopIterations = 1
  static let maximumLoopIterations = 24
  static let minimumPhaseRetries = 0
  static let maximumPhaseRetries = 5
  static let minimumNoProgressTimeoutSeconds = 60
  static let maximumNoProgressTimeoutSeconds = 3_600

  var enabled: Bool
  var shareScreenText: Bool
  var maxActions: Int
  var cloudContactId: String
  var dynamicReplanning: Bool
  var maxReplans: Int
  var multiAgentCoordination: Bool
  var shareAgentOutputsWithPlanner: Bool
  var maxAgentHops: Int
  var maxToolCalls: Int
  var maxLoopIterations: Int
  var maxPhaseRetries: Int
  var noProgressTimeoutSeconds: Int

  init(
    enabled: Bool = false,
    shareScreenText: Bool = false,
    maxActions: Int = 8,
    cloudContactId: String = "",
    dynamicReplanning: Bool = true,
    maxReplans: Int = 3,
    multiAgentCoordination: Bool = true,
    shareAgentOutputsWithPlanner: Bool = false,
    maxAgentHops: Int = 4,
    maxToolCalls: Int = 16,
    maxLoopIterations: Int = 8,
    maxPhaseRetries: Int = 2,
    noProgressTimeoutSeconds: Int = 180
  ) {
    self.enabled = enabled
    self.shareScreenText = shareScreenText
    self.maxActions = max(1, min(maxActions, Self.maximumActions))
    self.cloudContactId = String(
      cloudContactId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumCloudContactIdLength)
    )
    self.dynamicReplanning = dynamicReplanning
    self.maxReplans = max(1, min(maxReplans, Self.maximumReplans))
    self.multiAgentCoordination = multiAgentCoordination
    self.shareAgentOutputsWithPlanner = shareAgentOutputsWithPlanner
    self.maxAgentHops = max(1, min(maxAgentHops, Self.maximumAgentHops))
    self.maxToolCalls = max(Self.minimumToolCalls, min(maxToolCalls, Self.maximumToolCalls))
    self.maxLoopIterations = max(Self.minimumLoopIterations, min(maxLoopIterations, Self.maximumLoopIterations))
    self.maxPhaseRetries = max(Self.minimumPhaseRetries, min(maxPhaseRetries, Self.maximumPhaseRetries))
    self.noProgressTimeoutSeconds = max(
      Self.minimumNoProgressTimeoutSeconds,
      min(noProgressTimeoutSeconds, Self.maximumNoProgressTimeoutSeconds)
    )
  }

  static let `default` = AgentModelPlannerSettings()

  var normalized: AgentModelPlannerSettings {
    AgentModelPlannerSettings(
      enabled: enabled,
      shareScreenText: shareScreenText,
      maxActions: maxActions,
      cloudContactId: cloudContactId,
      dynamicReplanning: dynamicReplanning,
      maxReplans: maxReplans,
      multiAgentCoordination: multiAgentCoordination,
      shareAgentOutputsWithPlanner: shareAgentOutputsWithPlanner,
      maxAgentHops: maxAgentHops,
      maxToolCalls: maxToolCalls,
      maxLoopIterations: maxLoopIterations,
      maxPhaseRetries: maxPhaseRetries,
      noProgressTimeoutSeconds: noProgressTimeoutSeconds
    )
  }

  enum CodingKeys: String, CodingKey {
    case version
    case enabled
    case shareScreenText = "share_screen_text"
    case maxActions = "max_actions"
    case cloudContactId = "cloud_contact_id"
    case dynamicReplanning = "dynamic_replanning"
    case maxReplans = "max_replans"
    case multiAgentCoordination = "multi_agent_coordination"
    case shareAgentOutputsWithPlanner = "share_agent_outputs_with_planner"
    case maxAgentHops = "max_agent_hops"
    case maxToolCalls = "max_tool_calls"
    case maxLoopIterations = "max_loop_iterations"
    case maxPhaseRetries = "max_phase_retries"
    case noProgressTimeoutSeconds = "no_progress_timeout_seconds"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
      shareScreenText: try container.decodeIfPresent(Bool.self, forKey: .shareScreenText) ?? false,
      maxActions: try container.decodeIfPresent(Int.self, forKey: .maxActions) ?? 8,
      cloudContactId: try container.decodeIfPresent(String.self, forKey: .cloudContactId) ?? "",
      dynamicReplanning: try container.decodeIfPresent(Bool.self, forKey: .dynamicReplanning) ?? true,
      maxReplans: try container.decodeIfPresent(Int.self, forKey: .maxReplans) ?? 3,
      multiAgentCoordination: try container.decodeIfPresent(Bool.self, forKey: .multiAgentCoordination) ?? true,
      shareAgentOutputsWithPlanner: try container.decodeIfPresent(Bool.self, forKey: .shareAgentOutputsWithPlanner) ?? false,
      maxAgentHops: try container.decodeIfPresent(Int.self, forKey: .maxAgentHops) ?? 4,
      maxToolCalls: try container.decodeIfPresent(Int.self, forKey: .maxToolCalls) ?? 16,
      maxLoopIterations: try container.decodeIfPresent(Int.self, forKey: .maxLoopIterations) ?? 8,
      maxPhaseRetries: try container.decodeIfPresent(Int.self, forKey: .maxPhaseRetries) ?? 2,
      noProgressTimeoutSeconds: try container.decodeIfPresent(Int.self, forKey: .noProgressTimeoutSeconds) ?? 180
    )
  }

  func encode(to encoder: Encoder) throws {
    let value = normalized
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(5, forKey: .version)
    try container.encode(value.enabled, forKey: .enabled)
    try container.encode(value.shareScreenText, forKey: .shareScreenText)
    try container.encode(value.maxActions, forKey: .maxActions)
    try container.encode(value.cloudContactId, forKey: .cloudContactId)
    try container.encode(value.dynamicReplanning, forKey: .dynamicReplanning)
    try container.encode(value.maxReplans, forKey: .maxReplans)
    try container.encode(value.multiAgentCoordination, forKey: .multiAgentCoordination)
    try container.encode(value.shareAgentOutputsWithPlanner, forKey: .shareAgentOutputsWithPlanner)
    try container.encode(value.maxAgentHops, forKey: .maxAgentHops)
    try container.encode(value.maxToolCalls, forKey: .maxToolCalls)
    try container.encode(value.maxLoopIterations, forKey: .maxLoopIterations)
    try container.encode(value.maxPhaseRetries, forKey: .maxPhaseRetries)
    try container.encode(value.noProgressTimeoutSeconds, forKey: .noProgressTimeoutSeconds)
  }
}
