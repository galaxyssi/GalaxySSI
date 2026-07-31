import Foundation

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
