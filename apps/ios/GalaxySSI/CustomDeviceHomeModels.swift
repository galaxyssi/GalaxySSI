import CryptoKit
import Foundation

enum CustomDeviceTransport: String, Codable, CaseIterable, Identifiable {
  case httpRest = "HTTP_REST"
  case mqtt = "MQTT"
  case websocket = "WEBSOCKET"
  case tcp = "TCP"
  case udp = "UDP"
  case mcp = "MCP"
  case galaxySSIAgent = "GALAXYSSI_AGENT"
  case ble = "BLE"
  case matterThread = "MATTER_THREAD"

  var id: String { rawValue }

  var displayName: String {
    rawValue.replacingOccurrences(of: "_", with: " ")
  }

  static func fromWireValue(_ value: String?) -> CustomDeviceTransport {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()
      .replacingOccurrences(of: " ", with: "_") ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .httpRest
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

enum CustomDeviceRisk: String, Codable, CaseIterable, Identifiable {
  case low = "LOW"
  case medium = "MEDIUM"
  case high = "HIGH"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .low: return "LOW"
    case .medium: return "MEDIUM"
    case .high: return "HIGH"
    }
  }

  static func fromWireValue(_ value: String?) -> CustomDeviceRisk {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .medium
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

struct CustomDeviceConnector: Codable, Equatable, Identifiable {
  static let maximumConnectors = 50
  static let maximumIdLength = 80
  static let maximumNameLength = 100
  static let maximumEndpointLength = 1_000
  static let maximumCommandTargetLength = 300
  static let maximumUsernameLength = 200
  static let maximumAuthTokenLength = 2_000

  var id: String
  var name: String
  var transport: CustomDeviceTransport
  var endpoint: String
  var commandTarget: String
  var username: String
  var authToken: String
  var risk: CustomDeviceRisk
  var enabled: Bool

  init(
    id: String = UUID().uuidString,
    name: String = "Custom Device",
    transport: CustomDeviceTransport = .httpRest,
    endpoint: String = "",
    commandTarget: String = "",
    username: String = "",
    authToken: String = "",
    risk: CustomDeviceRisk = .medium,
    enabled: Bool = true
  ) {
    let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    self.id = String(cleanId.prefix(Self.maximumIdLength)).ifBlank(UUID().uuidString)
    self.name = String(cleanName.prefix(Self.maximumNameLength)).ifBlank("Custom Device")
    self.transport = transport
    self.endpoint = String(endpoint.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumEndpointLength))
    self.commandTarget = String(commandTarget.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumCommandTargetLength))
    self.username = String(username.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumUsernameLength))
    self.authToken = String(authToken.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumAuthTokenLength))
    self.risk = risk
    self.enabled = enabled
  }

  var configured: Bool {
    enabled && !name.isEmpty && !endpoint.isEmpty
  }

  var normalized: CustomDeviceConnector {
    CustomDeviceConnector(
      id: id,
      name: name,
      transport: transport,
      endpoint: endpoint,
      commandTarget: commandTarget,
      username: username,
      authToken: authToken,
      risk: risk,
      enabled: enabled
    )
  }

  var withoutAuthToken: CustomDeviceConnector {
    CustomDeviceConnector(
      id: id,
      name: name,
      transport: transport,
      endpoint: endpoint,
      commandTarget: commandTarget,
      username: username,
      authToken: "",
      risk: risk,
      enabled: enabled
    )
  }

  var maskedAuthToken: String {
    guard !authToken.isEmpty else { return "" }
    if authToken.count <= 8 { return "****" }
    return "\(authToken.prefix(4))****\(authToken.suffix(4))"
  }

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case transport
    case endpoint
    case commandTarget = "command_target"
    case username
    case authToken = "auth_token"
    case risk
    case enabled
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
      name: try container.decodeIfPresent(String.self, forKey: .name) ?? "Custom Device",
      transport: try container.decodeIfPresent(CustomDeviceTransport.self, forKey: .transport) ?? .httpRest,
      endpoint: try container.decodeIfPresent(String.self, forKey: .endpoint) ?? "",
      commandTarget: try container.decodeIfPresent(String.self, forKey: .commandTarget) ?? "",
      username: try container.decodeIfPresent(String.self, forKey: .username) ?? "",
      authToken: try container.decodeIfPresent(String.self, forKey: .authToken) ?? "",
      risk: try container.decodeIfPresent(CustomDeviceRisk.self, forKey: .risk) ?? .medium,
      enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    )
  }
}

struct HomeAssistantSettings: Codable, Equatable {
  static let maximumBaseURLLength = 2_000
  static let maximumAccessTokenLength = 8_000
  static let maximumEntityIdLength = 240

  var enabled: Bool
  var baseUrl: String
  var accessToken: String
  var defaultEntityId: String

  init(
    enabled: Bool = false,
    baseUrl: String = "",
    accessToken: String = "",
    defaultEntityId: String = ""
  ) {
    self.enabled = enabled
    var cleanBaseURL = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    while cleanBaseURL.hasSuffix("/") {
      cleanBaseURL.removeLast()
    }
    self.baseUrl = String(cleanBaseURL.prefix(Self.maximumBaseURLLength))
    self.accessToken = String(
      accessToken.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumAccessTokenLength)
    )
    self.defaultEntityId = String(
      defaultEntityId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumEntityIdLength)
    )
  }

  static let `default` = HomeAssistantSettings()

  var credentialsConfigured: Bool {
    !baseUrl.isEmpty && !accessToken.isEmpty
  }

  var configured: Bool {
    enabled && credentialsConfigured
  }

  var normalized: HomeAssistantSettings {
    HomeAssistantSettings(
      enabled: enabled,
      baseUrl: baseUrl,
      accessToken: accessToken,
      defaultEntityId: defaultEntityId
    )
  }

  var withoutAccessToken: HomeAssistantSettings {
    HomeAssistantSettings(
      enabled: enabled,
      baseUrl: baseUrl,
      accessToken: "",
      defaultEntityId: defaultEntityId
    )
  }

  var maskedAccessToken: String {
    guard !accessToken.isEmpty else { return "" }
    if accessToken.count <= 8 { return "********" }
    return "\(accessToken.prefix(4))...\(accessToken.suffix(4))"
  }

  enum CodingKeys: String, CodingKey {
    case version
    case enabled
    case baseUrl = "base_url"
    case accessToken = "access_token"
    case defaultEntityId = "default_entity_id"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
      baseUrl: try container.decodeIfPresent(String.self, forKey: .baseUrl) ?? "",
      accessToken: try container.decodeIfPresent(String.self, forKey: .accessToken) ?? "",
      defaultEntityId: try container.decodeIfPresent(String.self, forKey: .defaultEntityId) ?? ""
    )
  }

  func encode(to encoder: Encoder) throws {
    let value = normalized
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(1, forKey: .version)
    try container.encode(value.enabled, forKey: .enabled)
    try container.encode(value.baseUrl, forKey: .baseUrl)
    try container.encode(value.accessToken, forKey: .accessToken)
    try container.encode(value.defaultEntityId, forKey: .defaultEntityId)
  }
}
