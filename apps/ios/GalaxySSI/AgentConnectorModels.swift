import Foundation

enum AgentModelReasoningEffort: String, Codable, CaseIterable, Identifiable {
  case automatic = "auto"
  case low
  case medium
  case high
  case xhigh

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentModelReasoningEffort {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .automatic
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try? container.decode(String.self))
  }
}

struct AgentModelOption: Codable, Equatable, Identifiable {
  var id: String
  var displayName: String
  var description: String

  init(id: String, displayName: String = "", description: String = "") {
    self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
    self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(self.id)
    self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case displayName = "display_name"
    case description
  }

  init(from decoder: Decoder) throws {
    if let value = try? decoder.singleValueContainer().decode(String.self) {
      self.init(id: value)
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      displayName: try container.decodeIfPresent(String.self, forKey: .displayName) ?? "",
      description: try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    )
  }
}

struct AgentInvocationProfile: Codable, Equatable {
  var defaultModelId: String
  var models: [AgentModelOption]
  var reasoningEfforts: [AgentModelReasoningEffort]

  init(
    defaultModelId: String = "",
    models: [AgentModelOption] = [],
    reasoningEfforts: [AgentModelReasoningEffort] = []
  ) {
    self.defaultModelId = defaultModelId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.models = models.reduce(into: []) { result, option in
      guard !option.id.isEmpty, !result.contains(where: { $0.id == option.id }) else { return }
      result.append(option)
    }
    self.reasoningEfforts = reasoningEfforts.reduce(into: []) { result, effort in
      guard effort != .automatic, !result.contains(effort) else { return }
      result.append(effort)
    }
  }

  var configurable: Bool {
    !models.isEmpty || !reasoningEfforts.isEmpty
  }

  func normalizedModelId(_ requested: String) -> String {
    let clean = requested.trimmingCharacters(in: .whitespacesAndNewlines)
    return models.first(where: { $0.id == clean })?.id
      ?? models.first(where: { $0.id == defaultModelId })?.id
      ?? models.first?.id
      ?? ""
  }

  enum CodingKeys: String, CodingKey {
    case defaultModelId = "default_model"
    case models
    case reasoningEfforts = "reasoning_efforts"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      defaultModelId: try container.decodeIfPresent(String.self, forKey: .defaultModelId) ?? "",
      models: try container.decodeIfPresent([AgentModelOption].self, forKey: .models) ?? [],
      reasoningEfforts: try container.decodeIfPresent(
        [AgentModelReasoningEffort].self,
        forKey: .reasoningEfforts
      ) ?? []
    )
  }
}

struct AgentTargetConfiguration: Codable, Equatable {
  var modelId: String = ""
  var reasoningEffort: AgentModelReasoningEffort = .automatic
}

enum AgentInvocationRequestJsonCodec {
  static func encode(
    modelId: String,
    reasoningEffort: AgentModelReasoningEffort
  ) -> [String: String]? {
    let cleanModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanModelId.isEmpty || reasoningEffort != .automatic else { return nil }
    return [
      "model_id": cleanModelId,
      "reasoning_effort": reasoningEffort.rawValue
    ]
  }
}

enum AgentConnectorKind: String, Codable, CaseIterable, Identifiable {
  case model = "MODEL"
  case agent = "AGENT"
  case device = "DEVICE"
  case knowledge = "KNOWLEDGE"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentConnectorKind {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .agent
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentConnectorStatus: String, Codable, CaseIterable, Identifiable {
  case available = "AVAILABLE"
  case needsSetup = "NEEDS_SETUP"
  case disconnected = "DISCONNECTED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentConnectorStatus {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .disconnected
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentCapability: String, Codable, CaseIterable, Identifiable {
  case chat = "CHAT"
  case reasoning = "REASONING"
  case liveData = "LIVE_DATA"
  case toolUse = "TOOL_USE"
  case mcp = "MCP"
  case skill = "SKILL"
  case localInference = "LOCAL_INFERENCE"
  case research = "RESEARCH"
  case code = "CODE"
  case taskExecution = "TASK_EXECUTION"
  case smartHome = "SMART_HOME"
  case deviceControl = "DEVICE_CONTROL"
  case knowledgeSearch = "KNOWLEDGE_SEARCH"
  case screenReading = "SCREEN_READING"
  case clipboard = "CLIPBOARD"
  case systemSettings = "SYSTEM_SETTINGS"
  case appNavigation = "APP_NAVIGATION"
  case alarm = "ALARM"

  var id: String { rawValue }
  var wireValue: String { rawValue.lowercased() }

  static func fromWireValue(_ value: String?) -> AgentCapability? {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self)) ?? .chat
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
