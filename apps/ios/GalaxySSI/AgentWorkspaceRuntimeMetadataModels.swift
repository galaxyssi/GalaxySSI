import Foundation

struct AgentWorkspaceToolCallRecord: Codable, Equatable, Identifiable {
  var id: String
  var toolName: String
  var status: AgentToolCallStatus
  var argumentsJson: String
  var resultJson: String
  var errorMessage: String
  var startedAtMillis: Int64
  var completedAtMillis: Int64

  init(
    id: String,
    toolName: String,
    status: AgentToolCallStatus = .pending,
    argumentsJson: String = "",
    resultJson: String = "",
    errorMessage: String = "",
    startedAtMillis: Int64 = 0,
    completedAtMillis: Int64 = 0
  ) {
    self.id = Self.clean(id)
    self.toolName = Self.clean(toolName)
    self.status = status
    self.argumentsJson = argumentsJson
    self.resultJson = resultJson
    self.errorMessage = errorMessage
    self.startedAtMillis = max(startedAtMillis, 0)
    self.completedAtMillis = max(completedAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case toolName = "tool_name"
    case status
    case argumentsJson = "arguments_json"
    case resultJson = "result_json"
    case errorMessage = "error_message"
    case startedAtMillis = "started_at"
    case completedAtMillis = "completed_at"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      toolName: try container.decodeIfPresent(String.self, forKey: .toolName) ?? "",
      status: try container.decodeIfPresent(AgentToolCallStatus.self, forKey: .status) ?? .failed,
      argumentsJson: try container.decodeIfPresent(String.self, forKey: .argumentsJson) ?? "",
      resultJson: try container.decodeIfPresent(String.self, forKey: .resultJson) ?? "",
      errorMessage: try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? "",
      startedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .startedAtMillis) ?? 0,
      completedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .completedAtMillis) ?? 0
    )
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct AgentWorkspaceCheckpoint: Codable, Equatable, Identifiable {
  var id: String
  var eventSequence: Int64
  var planSnapshot: String
  var stateJson: String
  var createdAtMillis: Int64

  init(
    id: String,
    eventSequence: Int64 = 0,
    planSnapshot: String = "",
    stateJson: String = "",
    createdAtMillis: Int64 = 0
  ) {
    self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
    self.eventSequence = max(eventSequence, 0)
    self.planSnapshot = planSnapshot
    self.stateJson = stateJson
    self.createdAtMillis = max(createdAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case eventSequence = "event_sequence"
    case planSnapshot = "plan_snapshot"
    case stateJson = "state_json"
    case createdAtMillis = "created_at"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      eventSequence: try container.decodeIfPresent(Int64.self, forKey: .eventSequence) ?? 0,
      planSnapshot: try container.decodeIfPresent(String.self, forKey: .planSnapshot) ?? "",
      stateJson: try container.decodeIfPresent(String.self, forKey: .stateJson) ?? "",
      createdAtMillis: try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? 0
    )
  }
}

struct AgentWorkspaceArtifactReference: Codable, Equatable, Identifiable {
  var id: String
  var uri: String
  var name: String
  var mimeType: String
  var metadataJson: String
  var createdAtMillis: Int64

  init(
    id: String,
    uri: String,
    name: String = "",
    mimeType: String = "",
    metadataJson: String = "",
    createdAtMillis: Int64 = 0
  ) {
    self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
    self.uri = uri.trimmingCharacters(in: .whitespacesAndNewlines)
    self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    self.mimeType = mimeType.trimmingCharacters(in: .whitespacesAndNewlines)
    self.metadataJson = metadataJson
    self.createdAtMillis = max(createdAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case uri
    case name
    case mimeType = "mime_type"
    case metadataJson = "metadata_json"
    case createdAtMillis = "created_at"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      uri: try container.decodeIfPresent(String.self, forKey: .uri) ?? "",
      name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
      mimeType: try container.decodeIfPresent(String.self, forKey: .mimeType) ?? "",
      metadataJson: try container.decodeIfPresent(String.self, forKey: .metadataJson) ?? "",
      createdAtMillis: try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? 0
    )
  }
}

struct AgentWorkspaceExecutionSnapshot: Codable, Equatable {
  var status: AgentWorkspaceStatus?
  var planSnapshot: String
  var resultJson: String
  var errorMessage: String
  var toolCalls: [AgentWorkspaceToolCallRecord]
  var artifacts: [AgentWorkspaceArtifactReference]
  var permissionGrantIds: [String]
  var permissionScopes: [String]
  var handoffIds: [String]
  var agentId: String
  var deviceId: String
  var remoteRunId: String
  var lastRemoteEventSequence: Int64

  init(
    status: AgentWorkspaceStatus? = nil,
    planSnapshot: String = "",
    resultJson: String = "{}",
    errorMessage: String = "",
    toolCalls: [AgentWorkspaceToolCallRecord] = [],
    artifacts: [AgentWorkspaceArtifactReference] = [],
    permissionGrantIds: [String] = [],
    permissionScopes: [String] = [],
    handoffIds: [String] = [],
    agentId: String = "",
    deviceId: String = "",
    remoteRunId: String = "",
    lastRemoteEventSequence: Int64 = 0
  ) {
    self.status = status
    self.planSnapshot = planSnapshot
    self.resultJson = resultJson.isEmpty ? "{}" : resultJson
    self.errorMessage = errorMessage
    self.toolCalls = toolCalls
    self.artifacts = artifacts
    self.permissionGrantIds = permissionGrantIds.map { Self.clean($0) }.filter { !$0.isEmpty }
    self.permissionScopes = permissionScopes.map { Self.clean($0) }.filter { !$0.isEmpty }
    self.handoffIds = handoffIds.map { Self.clean($0) }.filter { !$0.isEmpty }
    self.agentId = Self.clean(agentId)
    self.deviceId = Self.clean(deviceId)
    self.remoteRunId = Self.clean(remoteRunId)
    self.lastRemoteEventSequence = max(lastRemoteEventSequence, 0)
  }

  enum CodingKeys: String, CodingKey {
    case status
    case planSnapshot = "plan_snapshot"
    case resultJson = "result_json"
    case errorMessage = "error_message"
    case toolCalls = "tool_calls"
    case artifacts
    case permissionGrantIds = "permission_grant_ids"
    case permissionScopes = "permission_scopes"
    case handoffIds = "handoff_ids"
    case agentId = "agent_id"
    case deviceId = "device_id"
    case remoteRunId = "remote_run_id"
    case lastRemoteEventSequence = "last_remote_event_sequence"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      status: try container.decodeIfPresent(AgentWorkspaceStatus.self, forKey: .status),
      planSnapshot: try container.decodeIfPresent(String.self, forKey: .planSnapshot) ?? "",
      resultJson: try container.decodeIfPresent(String.self, forKey: .resultJson) ?? "{}",
      errorMessage: try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? "",
      toolCalls: try container.decodeIfPresent([AgentWorkspaceToolCallRecord].self, forKey: .toolCalls) ?? [],
      artifacts: try container.decodeIfPresent([AgentWorkspaceArtifactReference].self, forKey: .artifacts) ?? [],
      permissionGrantIds: try container.decodeIfPresent([String].self, forKey: .permissionGrantIds) ?? [],
      permissionScopes: try container.decodeIfPresent([String].self, forKey: .permissionScopes) ?? [],
      handoffIds: try container.decodeIfPresent([String].self, forKey: .handoffIds) ?? [],
      agentId: try container.decodeIfPresent(String.self, forKey: .agentId) ?? "",
      deviceId: try container.decodeIfPresent(String.self, forKey: .deviceId) ?? "",
      remoteRunId: try container.decodeIfPresent(String.self, forKey: .remoteRunId) ?? "",
      lastRemoteEventSequence: try container.decodeIfPresent(Int64.self, forKey: .lastRemoteEventSequence) ?? 0
    )
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
