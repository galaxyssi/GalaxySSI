import CryptoKit
import Foundation

enum SignalASITrustState: String, Codable, CaseIterable {
  case unverified
  case verified
  case deleted
}

enum SignalASIDeliveryMode: String, Codable, CaseIterable {
  case local
  case link
  case cloudAPI
  case pcConnector = "pc_connector"

  var isSignalASILinkFamily: Bool {
    switch self {
    case .link, .pcConnector:
      return true
    case .local, .cloudAPI:
      return false
    }
  }

  static func fromWireValue(_ value: String?) -> SignalASIDeliveryMode {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "-", with: "_") ?? ""
    switch normalized {
    case "cloudapi", "cloud_api":
      return .cloudAPI
    case "link", "signalasi_link":
      return .link
    case "pc_connector", "pcconnector":
      return .pcConnector
    case "local":
      return .local
    default:
      return .local
    }
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

enum SignalASICloudAPIStyle: String, Codable, CaseIterable, Identifiable {
  case openAICompatible = "openai"
  case anthropic
  case gemini

  var id: String { rawValue }
}

struct SignalASIProfile: Codable, Equatable {
  var signalASIId: String
  var name: String
  var identityFingerprint: String
  var identityPublicKey: String
  var avatarData: Data? = nil
}

struct SignalASIContact: Codable, Identifiable, Equatable, Hashable {
  var id: String
  var signalASIId: String
  var name: String
  var displayName: String
  var type: String
  var agentKind: String
  var deliveryMode: SignalASIDeliveryMode
  var trustState: SignalASITrustState
  var desktopId: String
  var desktopName: String
  var identityFingerprint: String
  var setupStatus: String
  var setupDetail: String
  var cloudProvider: String
  var cloudModels: [CloudModelConfig]
  var selectedCloudModelId: String
  var agentId: String? = nil
  var deleted: Bool
  var createdAt: Date
  var updatedAt: Date
  var mqttTopic: String? = nil
  var mqttInboxTopic: String? = nil
  var linkClientRouteId: String? = nil
  var linkSecret: String? = nil
  var linkLocalFingerprint: String? = nil
  var signalBundleRef: String? = nil
  var setupNextStep: String? = nil
  var desktopAccessProfile: String? = nil
  var desktopAccessScopes: [String]? = nil
  var connectorCapabilities: [String]? = nil
  var connectorCapabilitiesHash: String? = nil
  var connectorProtocols: [String]? = nil
  var connectorProtocolFeatures: [String]? = nil
  var connectorAdapterType: String? = nil
  var connectorProviderProfileJSON: Data? = nil
  var deletedAt: Date? = nil
  var deviceName: String? = nil
  var deviceManufacturer: String? = nil
  var deviceModel: String? = nil
  var devicePlatform: String? = nil
  var devicePlatformVersion: String? = nil
  var deviceProfileName: String? = nil
  var deviceHostName: String? = nil

  var selectedCloudModel: CloudModelConfig? {
    cloudModels.first { $0.modelId == selectedCloudModelId } ?? cloudModels.first
  }

  var isCommunicable: Bool {
    !deleted && trustState == .verified
  }

  var isDesktopDeviceContact: Bool {
    type.caseInsensitiveCompare("device") == .orderedSame &&
      agentKind.caseInsensitiveCompare("device") == .orderedSame &&
      connectorAgentId.caseInsensitiveCompare("desktop") == .orderedSame &&
      !desktopId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var connectorAgentId: String {
    let stored = (agentId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !stored.isEmpty {
      return stored
    }
    let rawIds = [id, signalASIId].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    for rawId in rawIds where !rawId.isEmpty {
      if !desktopId.isEmpty, rawId.hasPrefix("\(desktopId):") {
        return String(rawId.dropFirst(desktopId.count + 1))
      }
      if deliveryMode.isSignalASILinkFamily, rawId.contains(":") {
        return rawId.split(separator: ":", maxSplits: 1).last.map(String.init) ?? rawId
      }
    }
    return ""
  }

  var connectorCapabilitySet: Set<AgentCapability> {
    Set((connectorCapabilities ?? []).compactMap(AgentCapability.fromWireValue))
  }

  var connectorProtocolRange: AgentProtocolRange {
    let versions = (connectorProtocols ?? [])
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return AgentProtocolRange(
      preferred: versions.first ?? "1.1",
      minimum: versions.last ?? "1.0",
      maximum: versions.first ?? "1.1",
      features: Set((connectorProtocolFeatures ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    )
  }

  var connectorAdapterName: String {
    (connectorAdapterType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var connectorProviderProfile: ProviderProfile? {
    guard let connectorProviderProfileJSON else { return nil }
    return try? JSONDecoder().decode(ProviderProfile.self, from: connectorProviderProfileJSON)
  }

  static func hermes() -> SignalASIContact {
    SignalASIContact(
      id: "hermes",
      signalASIId: "hermes",
      name: "Hermes Agent",
      displayName: "Hermes Agent",
      type: "hermes",
      agentKind: "desktop-agent",
      deliveryMode: .link,
      trustState: .unverified,
      desktopId: "",
      desktopName: "",
      identityFingerprint: "",
      setupStatus: "needs_pairing",
      setupDetail: "Waiting for SignalASI Desktop pairing",
      cloudProvider: "",
      cloudModels: [],
      selectedCloudModelId: "",
      deleted: false,
      createdAt: Date(),
      updatedAt: Date()
    )
  }

  static func system() -> SignalASIContact {
    SignalASIContact(
      id: "system",
      signalASIId: "system",
      name: "System",
      displayName: "System",
      type: "system",
      agentKind: "local",
      deliveryMode: .local,
      trustState: .verified,
      desktopId: "",
      desktopName: "",
      identityFingerprint: "",
      setupStatus: "ready",
      setupDetail: "Local notices",
      cloudProvider: "",
      cloudModels: [],
      selectedCloudModelId: "",
      deleted: false,
      createdAt: Date(),
      updatedAt: Date()
    )
  }
}

extension SignalASIContact {
  var opaquePhoneRoutes: SignalASILinkRoutes? {
    guard let clientRouteId = linkClientRouteId,
          let linkSecret,
          let localFingerprint = linkLocalFingerprint else { return nil }
    let routes = SignalASILinkRoutes(
      clientRouteId: clientRouteId,
      linkSecret: linkSecret,
      localFingerprint: localFingerprint,
      remoteFingerprint: identityFingerprint
    )
    return routes.isOpaqueV2Valid ? routes : nil
  }

  var connectorSetupNextStep: String {
    (setupNextStep ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var connectorDesktopAccessProfile: String {
    (desktopAccessProfile ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var connectorDesktopAccessScopes: [String] {
    (desktopAccessScopes ?? [])
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}

extension SignalASIFriendRequest {
  var opaquePhoneRoutes: SignalASILinkRoutes? {
    let routes = SignalASILinkRoutes(
      clientRouteId: linkClientRouteId,
      linkSecret: linkSecret,
      localFingerprint: linkLocalFingerprint,
      remoteFingerprint: identityFingerprint
    )
    return routes.isOpaqueV2Valid ? routes : nil
  }
}

enum SignalASIFriendRequestStatus: String, Codable, CaseIterable {
  case pending
  case approved
  case rejected
  case deleted
}

struct SignalASIFriendRequest: Codable, Identifiable, Equatable, Hashable {
  var id: String
  var signalASIId: String
  var name: String
  var type: String
  var identityPublicKey: String
  var identityFingerprint: String
  var mqttTopic: String
  var mqttInboxTopic: String
  var linkClientRouteId: String
  var linkSecret: String
  var linkLocalFingerprint: String
  var signalBundleRef: String
  var agentKind: String
  var desktopId: String
  var desktopName: String
  var deviceId: String
  var deviceName: String
  var deviceManufacturer: String
  var deviceModel: String
  var devicePlatform: String
  var devicePlatformVersion: String
  var deviceProfileName: String
  var deviceHostName: String
  var setupDetail: String
  var setupNextStep: String
  var desktopAccessProfile: String
  var desktopAccessScopes: [String]
  var connectorCapabilities: [String]
  var connectorCapabilitiesHash: String
  var connectorProtocols: [String]
  var connectorProtocolFeatures: [String]
  var connectorAdapterType: String
  var connectorProviderProfileJSON: Data?
  var source: String
  var status: SignalASIFriendRequestStatus
  var createdAt: Date
  var approvedAt: Date?
  var rejectedAt: Date?
  var deletedAt: Date?
  var previouslyDeleted: Bool
  var readdRequired: Bool

  init(
    id: String,
    signalASIId: String,
    name: String,
    type: String,
    identityPublicKey: String,
    identityFingerprint: String,
    mqttTopic: String,
    mqttInboxTopic: String,
    linkClientRouteId: String = "",
    linkSecret: String = "",
    linkLocalFingerprint: String = "",
    signalBundleRef: String = "",
    agentKind: String = "",
    desktopId: String = "",
    desktopName: String = "",
    deviceId: String = "",
    deviceName: String = "",
    deviceManufacturer: String = "",
    deviceModel: String = "",
    devicePlatform: String = "",
    devicePlatformVersion: String = "",
    deviceProfileName: String = "",
    deviceHostName: String = "",
    setupDetail: String = "",
    setupNextStep: String = "",
    desktopAccessProfile: String = "",
    desktopAccessScopes: [String] = [],
    connectorCapabilities: [String] = [],
    connectorCapabilitiesHash: String = "",
    connectorProtocols: [String] = [],
    connectorProtocolFeatures: [String] = [],
    connectorAdapterType: String = "",
    connectorProviderProfileJSON: Data? = nil,
    source: String = "qr",
    status: SignalASIFriendRequestStatus = .pending,
    createdAt: Date = Date(),
    approvedAt: Date? = nil,
    rejectedAt: Date? = nil,
    deletedAt: Date? = nil,
    previouslyDeleted: Bool = false,
    readdRequired: Bool = false
  ) {
    self.id = id
    self.signalASIId = signalASIId
    self.name = name
    self.type = type
    self.identityPublicKey = identityPublicKey
    self.identityFingerprint = identityFingerprint
    self.mqttTopic = mqttTopic
    self.mqttInboxTopic = mqttInboxTopic
    self.linkClientRouteId = linkClientRouteId
    self.linkSecret = linkSecret
    self.linkLocalFingerprint = linkLocalFingerprint
    self.signalBundleRef = signalBundleRef
    self.agentKind = agentKind
    self.desktopId = desktopId
    self.desktopName = desktopName
    self.deviceId = deviceId
    self.deviceName = deviceName
    self.deviceManufacturer = deviceManufacturer
    self.deviceModel = deviceModel
    self.devicePlatform = devicePlatform
    self.devicePlatformVersion = devicePlatformVersion
    self.deviceProfileName = deviceProfileName
    self.deviceHostName = deviceHostName
    self.setupDetail = setupDetail
    self.setupNextStep = setupNextStep
    self.desktopAccessProfile = desktopAccessProfile
    self.desktopAccessScopes = desktopAccessScopes
    self.connectorCapabilities = connectorCapabilities
    self.connectorCapabilitiesHash = connectorCapabilitiesHash
    self.connectorProtocols = connectorProtocols
    self.connectorProtocolFeatures = connectorProtocolFeatures
    self.connectorAdapterType = connectorAdapterType
    self.connectorProviderProfileJSON = connectorProviderProfileJSON
    self.source = source
    self.status = status
    self.createdAt = createdAt
    self.approvedAt = approvedAt
    self.rejectedAt = rejectedAt
    self.deletedAt = deletedAt
    self.previouslyDeleted = previouslyDeleted
    self.readdRequired = readdRequired
  }

  enum CodingKeys: String, CodingKey {
    case id
    case signalASIId = "signalasi_id"
    case name
    case type
    case identityPublicKey = "identity_public_key"
    case identityFingerprint = "identity_fingerprint"
    case mqttTopic = "mqtt_topic"
    case mqttInboxTopic = "mqtt_inbox_topic"
    case linkClientRouteId = "client_route_id"
    case linkSecret = "link_secret"
    case linkLocalFingerprint = "local_identity_fingerprint"
    case signalBundleRef = "signal_bundle_ref"
    case agentKind = "agent_kind"
    case desktopId = "desktop_id"
    case desktopName = "desktop_name"
    case deviceId = "device_id"
    case deviceName = "device_name"
    case deviceManufacturer = "device_manufacturer"
    case deviceModel = "device_model"
    case devicePlatform = "platform"
    case devicePlatformVersion = "platform_version"
    case deviceProfileName = "profile_name"
    case deviceHostName = "host_name"
    case setupDetail = "setup_detail"
    case setupNextStep = "setup_next_step"
    case desktopAccessProfile = "desktop_access_profile"
    case desktopAccessScopes = "desktop_access_scopes"
    case connectorCapabilities = "capabilities"
    case connectorCapabilitiesHash = "capabilities_hash"
    case connectorProtocols = "protocols"
    case connectorProtocolFeatures = "protocol_features"
    case connectorAdapterType = "adapter_type"
    case connectorProviderProfileJSON = "provider_profile_json"
    case source
    case status
    case createdAt = "created_at"
    case approvedAt = "approved_at"
    case rejectedAt = "rejected_at"
    case deletedAt = "deleted_at"
    case previouslyDeleted = "previously_deleted"
    case readdRequired = "readd_required"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
    signalASIId = try container.decodeIfPresent(String.self, forKey: .signalASIId) ?? ""
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Friend"
    type = try container.decodeIfPresent(String.self, forKey: .type) ?? "person"
    identityPublicKey = try container.decodeIfPresent(String.self, forKey: .identityPublicKey) ?? ""
    identityFingerprint = try container.decodeIfPresent(String.self, forKey: .identityFingerprint) ?? ""
    mqttTopic = try container.decodeIfPresent(String.self, forKey: .mqttTopic) ?? ""
    mqttInboxTopic = try container.decodeIfPresent(String.self, forKey: .mqttInboxTopic) ?? mqttTopic
    linkClientRouteId = try container.decodeIfPresent(String.self, forKey: .linkClientRouteId) ?? ""
    linkSecret = try container.decodeIfPresent(String.self, forKey: .linkSecret) ?? ""
    linkLocalFingerprint = try container.decodeIfPresent(String.self, forKey: .linkLocalFingerprint) ?? ""
    signalBundleRef = try container.decodeIfPresent(String.self, forKey: .signalBundleRef) ?? ""
    agentKind = try container.decodeIfPresent(String.self, forKey: .agentKind) ?? ""
    desktopId = try container.decodeIfPresent(String.self, forKey: .desktopId) ?? ""
    desktopName = try container.decodeIfPresent(String.self, forKey: .desktopName) ?? ""
    deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
    deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName) ?? ""
    deviceManufacturer = try container.decodeIfPresent(String.self, forKey: .deviceManufacturer) ?? ""
    deviceModel = try container.decodeIfPresent(String.self, forKey: .deviceModel) ?? ""
    devicePlatform = try container.decodeIfPresent(String.self, forKey: .devicePlatform) ?? ""
    devicePlatformVersion = try container.decodeIfPresent(String.self, forKey: .devicePlatformVersion) ?? ""
    deviceProfileName = try container.decodeIfPresent(String.self, forKey: .deviceProfileName) ?? ""
    deviceHostName = try container.decodeIfPresent(String.self, forKey: .deviceHostName) ?? ""
    setupDetail = try container.decodeIfPresent(String.self, forKey: .setupDetail) ?? ""
    setupNextStep = try container.decodeIfPresent(String.self, forKey: .setupNextStep) ?? ""
    desktopAccessProfile = try container.decodeIfPresent(String.self, forKey: .desktopAccessProfile) ?? ""
    desktopAccessScopes = try container.decodeIfPresent([String].self, forKey: .desktopAccessScopes) ?? []
    connectorCapabilities = try container.decodeIfPresent([String].self, forKey: .connectorCapabilities) ?? []
    connectorCapabilitiesHash = try container.decodeIfPresent(String.self, forKey: .connectorCapabilitiesHash) ?? ""
    connectorProtocols = try container.decodeIfPresent([String].self, forKey: .connectorProtocols) ?? []
    connectorProtocolFeatures = try container.decodeIfPresent([String].self, forKey: .connectorProtocolFeatures) ?? []
    connectorAdapterType = try container.decodeIfPresent(String.self, forKey: .connectorAdapterType) ?? ""
    connectorProviderProfileJSON = try container.decodeIfPresent(Data.self, forKey: .connectorProviderProfileJSON)
    source = try container.decodeIfPresent(String.self, forKey: .source) ?? "qr"
    status = try container.decodeIfPresent(SignalASIFriendRequestStatus.self, forKey: .status) ?? .pending
    createdAt = Self.decodeDate(container, key: .createdAt) ?? Date()
    approvedAt = Self.decodeDate(container, key: .approvedAt)
    rejectedAt = Self.decodeDate(container, key: .rejectedAt)
    deletedAt = Self.decodeDate(container, key: .deletedAt)
    previouslyDeleted = try container.decodeIfPresent(Bool.self, forKey: .previouslyDeleted) ?? false
    readdRequired = try container.decodeIfPresent(Bool.self, forKey: .readdRequired) ?? previouslyDeleted
  }

  private static func decodeDate(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Date? {
    if let date = try? container.decode(Date.self, forKey: key) {
      return date
    }
    if let milliseconds = try? container.decode(Double.self, forKey: key), milliseconds > 0 {
      return Date(timeIntervalSince1970: (milliseconds < 10_000_000_000 ? milliseconds * 1000 : milliseconds) / 1000)
    }
    if let value = try? container.decode(String.self, forKey: key),
       let milliseconds = Double(value), milliseconds > 0 {
      return Date(timeIntervalSince1970: (milliseconds < 10_000_000_000 ? milliseconds * 1000 : milliseconds) / 1000)
    }
    return nil
  }
}

struct CloudModelConfig: Codable, Identifiable, Equatable, Hashable {
  var id: String
  var displayName: String
  var provider: String
  var modelId: String
  var endpoint: String
  var apiStyle: SignalASICloudAPIStyle
  var keychainAccount: String
  var updatedAt: Date
}

struct CloudModelPreset: Identifiable, Equatable, Hashable {
  var id: String { "\(provider)-\(modelId)" }
  var provider: String
  var name: String
  var modelId: String
  var endpoint: String
  var apiStyle: SignalASICloudAPIStyle

  static let androidParity: [CloudModelPreset] = [
    CloudModelPreset(provider: "OpenAI", name: "GPT-5.5", modelId: "gpt-5.5", endpoint: "https://api.openai.com/v1/chat/completions", apiStyle: .openAICompatible),
    CloudModelPreset(provider: "OpenAI", name: "GPT-5.4 mini", modelId: "gpt-5.4-mini", endpoint: "https://api.openai.com/v1/chat/completions", apiStyle: .openAICompatible),
    CloudModelPreset(provider: "OpenAI", name: "GPT-5.4 nano", modelId: "gpt-5.4-nano", endpoint: "https://api.openai.com/v1/chat/completions", apiStyle: .openAICompatible),
    CloudModelPreset(provider: "OpenAI", name: "GPT-5", modelId: "gpt-5", endpoint: "https://api.openai.com/v1/chat/completions", apiStyle: .openAICompatible),
    CloudModelPreset(provider: "Anthropic", name: "Claude Opus 4.7", modelId: "claude-opus-4-7-latest", endpoint: "https://api.anthropic.com/v1/messages", apiStyle: .anthropic),
    CloudModelPreset(provider: "Anthropic", name: "Claude Sonnet 5", modelId: "claude-sonnet-5-latest", endpoint: "https://api.anthropic.com/v1/messages", apiStyle: .anthropic),
    CloudModelPreset(provider: "Anthropic", name: "Claude Haiku 4.5", modelId: "claude-haiku-4-5-latest", endpoint: "https://api.anthropic.com/v1/messages", apiStyle: .anthropic),
    CloudModelPreset(provider: "Google Gemini", name: "Gemini 3.5 Flash", modelId: "gemini-3.5-flash", endpoint: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent", apiStyle: .gemini),
    CloudModelPreset(provider: "Google Gemini", name: "Gemini 3.1 Pro", modelId: "gemini-3.1-pro", endpoint: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-pro:generateContent", apiStyle: .gemini),
    CloudModelPreset(provider: "Google Gemini", name: "Gemini 3.1 Flash Lite", modelId: "gemini-3.1-flash-lite", endpoint: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent", apiStyle: .gemini),
    CloudModelPreset(provider: "DeepSeek", name: "DeepSeek V4 Pro", modelId: "deepseek-v4-pro", endpoint: "https://api.deepseek.com/chat/completions", apiStyle: .openAICompatible),
    CloudModelPreset(provider: "DeepSeek", name: "DeepSeek V4 Flash", modelId: "deepseek-v4-flash", endpoint: "https://api.deepseek.com/chat/completions", apiStyle: .openAICompatible),
    CloudModelPreset(provider: "Qwen", name: "Qwen 3.7 Max", modelId: "qwen3.7-max", endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", apiStyle: .openAICompatible),
    CloudModelPreset(provider: "Qwen", name: "Qwen 3.7 Plus", modelId: "qwen3.7-plus", endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", apiStyle: .openAICompatible),
    CloudModelPreset(provider: "Qwen", name: "Qwen 3.6 Flash", modelId: "qwen3.6-flash", endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", apiStyle: .openAICompatible),
    CloudModelPreset(provider: "OpenRouter", name: "OpenRouter Auto", modelId: "openrouter/auto", endpoint: "https://openrouter.ai/api/v1/chat/completions", apiStyle: .openAICompatible),
    CloudModelPreset(provider: "OpenRouter", name: "OpenAI GPT-5.5 via OpenRouter", modelId: "openai/gpt-5.5", endpoint: "https://openrouter.ai/api/v1/chat/completions", apiStyle: .openAICompatible),
    CloudModelPreset(provider: "Custom", name: "OpenAI Compatible", modelId: "model-id", endpoint: "https://api.example.com/v1/chat/completions", apiStyle: .openAICompatible)
  ]
}

enum AgentConnectorAvailability {
  static func desktopAgentReady(
    setupStatus: String,
    setupUpdatedAtMillis: Int64,
    nowMillis: Int64
  ) -> Bool {
    let statusReady = routableDesktopStates.contains(
      setupStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    )
    guard statusReady, setupUpdatedAtMillis > 0 else {
      return false
    }
    let ageMillis = nowMillis - setupUpdatedAtMillis
    return ageMillis >= -maximumClockSkewMillis && ageMillis <= desktopStatusTtlMillis
  }

  static func desktopAgentReady(
    contact: SignalASIContact,
    now: Date = Date()
  ) -> Bool {
    desktopAgentReady(
      setupStatus: contact.setupStatus,
      setupUpdatedAtMillis: milliseconds(contact.updatedAt),
      nowMillis: milliseconds(now)
    )
  }

  static func cloudModelReady(
    model: CloudModelConfig,
    apiKey: String?,
    provider: String,
    setupStatus: String = "ready"
  ) -> Bool {
    CloudModelCredentialPolicy.isAutoRoutable(
      model: model,
      apiKey: apiKey,
      provider: provider,
      setupStatus: setupStatus
    )
  }

  static func cloudModelReady(
    contact: SignalASIContact,
    apiKey: String?
  ) -> Bool {
    guard let model = contact.selectedCloudModel else {
      return false
    }
    return cloudModelReady(
      model: model,
      apiKey: apiKey,
      provider: contact.cloudProvider,
      setupStatus: contact.setupStatus
    )
  }

  private static func milliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }

  private static let routableDesktopStates: Set<String> = ["ready", "busy"]
  private static let desktopStatusTtlMillis: Int64 = 10 * 60_000
  private static let maximumClockSkewMillis: Int64 = 60_000
}

enum ChatDeliveryStatus: String, Codable, Equatable {
  case local
  case queued
  case sent
  case delivered
  case read
  case failed
}

struct DeliveryTraceEvent: Codable, Equatable, Identifiable {
  var id: UUID
  var stage: String
  var detail: String
  var createdAt: Date

  init(id: UUID = UUID(), stage: String, detail: String = "", createdAt: Date = Date()) {
    self.id = id
    self.stage = stage
    self.detail = detail
    self.createdAt = createdAt
  }

  var displayTitle: String {
    switch stage {
    case "created": return "Created"
    case "persisted": return "Persisted"
    case "queued": return "Queued"
    case "sent": return "Sent"
    case "delivered": return "Delivered"
    case "read": return "Read"
    case "failed": return "Failed"
    case "mqtt_published": return "Published to MQTT"
    case "publish_failed": return "Publish failed"
    case "delivered_local_estimate": return "Delivery estimated"
    case "desktop_received": return "Desktop received"
    case "desktop_plain": return "Desktop plaintext debug"
    case "desktop_decrypted": return "Desktop decrypted"
    case "agent_started": return "Agent started"
    case "agent_first_output": return "First Agent output"
    case "agent_replied": return "Agent replied"
    case "agent_accepted": return "Accepted"
    case "agent_queued": return "Queued"
    case "agent_starting": return "Starting"
    case "agent_recovering": return "Recovering"
    case "agent_running": return "Running"
    case "agent_waiting_input": return "Waiting for input"
    case "agent_waiting_approval": return "Waiting for approval"
    case "agent_completed": return "Completed"
    case "agent_failed": return "Failed"
    case "agent_cancelled": return "Cancelled"
    case "agent_timed_out": return "Timed out"
    case "agent_cancelling": return "Cancelling"
    case "desktop_reply_publish_queued": return "Desktop reply queued"
    case "desktop_reply_broker_ack": return "Desktop reply Broker ACK"
    case "desktop_broker_ack": return "Broker confirmed"
    case "phone_contact_delivered": return "Phone contact confirmed delivery"
    case "desktop_mobile_test_queued": return "Desktop test queued"
    case "desktop_agent_push_queued": return "Agent Push queued"
    case "desktop_connector_status": return "Connector status synced"
    case "desktop_pairing_confirmed": return "Pairing confirmed"
    case "desktop_pairing_revocation_queued": return "Pairing revocation queued"
    case "received": return "Received"
    case "decrypted": return "Decrypted"
    case "cloud_request": return "Model request"
    case "cloud_reply": return "Model replied"
    case "cloud_reply_received": return "Model reply received"
    case "cloud_error": return "Model error"
    case "local_saved": return "Saved locally"
    default: return stage
    }
  }
}

struct ChatMessage: Codable, Identifiable, Equatable {
  var id: UUID
  var contactId: String
  var content: String
  var isMine: Bool
  var isSystem: Bool
  var createdAt: Date
  var deliveryStatus: ChatDeliveryStatus
  var deliveryTrace: [DeliveryTraceEvent]
  var conversationId: String
  var turnId: String
  var remoteMessageId: String
  var richOutputJson: String
  var sourceConversationId: String
  var sourceConversationTitle: String

  enum CodingKeys: String, CodingKey {
    case id
    case contactId
    case content
    case isMine
    case isSystem
    case createdAt
    case deliveryStatus
    case deliveryTrace
    case conversationId
    case turnId
    case remoteMessageId
    case richOutputJson
    case sourceConversationId
    case sourceConversationTitle
  }

  init(
    id: UUID = UUID(),
    contactId: String,
    content: String,
    isMine: Bool,
    isSystem: Bool = false,
    createdAt: Date = Date(),
    deliveryStatus: ChatDeliveryStatus = .local,
    deliveryTrace: [DeliveryTraceEvent] = [],
    conversationId: String = "",
    turnId: String = "",
    remoteMessageId: String = "",
    richOutputJson: String = "",
    sourceConversationId: String = "",
    sourceConversationTitle: String = ""
  ) {
    self.id = id
    self.contactId = contactId
    self.content = content
    self.isMine = isMine
    self.isSystem = isSystem
    self.createdAt = createdAt
    self.deliveryStatus = deliveryStatus
    self.deliveryTrace = deliveryTrace
    self.conversationId = conversationId
    self.turnId = turnId
    self.remoteMessageId = remoteMessageId
    self.richOutputJson = richOutputJson
    self.sourceConversationId = sourceConversationId
    self.sourceConversationTitle = sourceConversationTitle
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    contactId = try container.decodeIfPresent(String.self, forKey: .contactId) ?? ""
    content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
    isMine = try container.decodeIfPresent(Bool.self, forKey: .isMine) ?? false
    isSystem = try container.decodeIfPresent(Bool.self, forKey: .isSystem) ?? false
    createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    deliveryStatus = try container.decodeIfPresent(ChatDeliveryStatus.self, forKey: .deliveryStatus) ?? .local
    deliveryTrace = try container.decodeIfPresent([DeliveryTraceEvent].self, forKey: .deliveryTrace) ?? []
    conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId) ?? ""
    turnId = try container.decodeIfPresent(String.self, forKey: .turnId) ?? ""
    remoteMessageId = try container.decodeIfPresent(String.self, forKey: .remoteMessageId) ?? ""
    richOutputJson = try container.decodeIfPresent(String.self, forKey: .richOutputJson) ?? ""
    sourceConversationId = try container.decodeIfPresent(String.self, forKey: .sourceConversationId) ?? ""
    sourceConversationTitle = try container.decodeIfPresent(String.self, forKey: .sourceConversationTitle) ?? ""
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(contactId, forKey: .contactId)
    try container.encode(content, forKey: .content)
    try container.encode(isMine, forKey: .isMine)
    try container.encode(isSystem, forKey: .isSystem)
    try container.encode(createdAt, forKey: .createdAt)
    try container.encode(deliveryStatus, forKey: .deliveryStatus)
    try container.encode(deliveryTrace, forKey: .deliveryTrace)
    try container.encode(conversationId, forKey: .conversationId)
    try container.encode(turnId, forKey: .turnId)
    try container.encode(remoteMessageId, forKey: .remoteMessageId)
    try container.encode(richOutputJson, forKey: .richOutputJson)
    try container.encode(sourceConversationId, forKey: .sourceConversationId)
    try container.encode(sourceConversationTitle, forKey: .sourceConversationTitle)
  }
}

struct SignalASILinkRoutes: Codable, Equatable, Hashable {
  var clientRouteId: String
  var linkSecret: String
  var localFingerprint: String
  var remoteFingerprint: String

  init(
    clientRouteId: String,
    linkSecret: String,
    localFingerprint: String,
    remoteFingerprint: String
  ) {
    self.clientRouteId = clientRouteId
    self.linkSecret = linkSecret
    self.localFingerprint = localFingerprint
    self.remoteFingerprint = remoteFingerprint
  }

  var upTopic: String {
    SignalASILinkProtocol.relationshipTopic(
      linkSecret: linkSecret,
      senderFingerprint: localFingerprint,
      receiverFingerprint: remoteFingerprint
    )
  }

  var downTopic: String {
    SignalASILinkProtocol.relationshipTopic(
      linkSecret: linkSecret,
      senderFingerprint: remoteFingerprint,
      receiverFingerprint: localFingerprint
    )
  }

  var controlTopic: String {
    upTopic
  }

  var receiveWindow: Set<String> {
    SignalASILinkProtocol.topicWindow(
      linkSecret: linkSecret,
      senderFingerprint: remoteFingerprint,
      receiverFingerprint: localFingerprint
    )
  }

  var sendWindow: Set<String> {
    SignalASILinkProtocol.topicWindow(
      linkSecret: linkSecret,
      senderFingerprint: localFingerprint,
      receiverFingerprint: remoteFingerprint
    )
  }

  var isOpaqueV2Valid: Bool {
    SignalASILinkProtocol.validRouteId(clientRouteId) &&
      SignalASILinkProtocol.validLinkSecret(linkSecret) &&
      !localFingerprint.isEmpty &&
      !remoteFingerprint.isEmpty &&
      localFingerprint != remoteFingerprint
  }

  enum CodingKeys: String, CodingKey {
    case clientRouteId
    case linkSecret
    case localFingerprint
    case remoteFingerprint
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      clientRouteId: try container.decodeIfPresent(String.self, forKey: .clientRouteId) ?? "",
      linkSecret: try container.decodeIfPresent(String.self, forKey: .linkSecret) ?? "",
      localFingerprint: try container.decodeIfPresent(String.self, forKey: .localFingerprint) ?? "",
      remoteFingerprint: try container.decodeIfPresent(String.self, forKey: .remoteFingerprint) ?? ""
    )
  }
}

struct PairingAccess: Codable, Equatable, Hashable {
  var profile: String
  var scopes: Set<String>

  var fullDesktopExecutor: Bool {
    profile == SignalASILinkProtocol.accessDesktopExecutor &&
      scopes.contains(SignalASILinkProtocol.scopeDesktopExecutor)
  }
}

struct ServerLink: Codable, Identifiable, Equatable, Hashable {
  var id: String { desktopId }
  var desktopId: String
  var desktopName: String
  var desktopFingerprint: String
  var signalName: String
  var routes: SignalASILinkRoutes
  var paired: Bool
  var accessProfile: String
  var accessScopes: Set<String>
  var capabilityManifestVersion: Int
  var deviceMetadata: SignalASIDesktopDeviceMetadata?
  var updatedAt: Date

  init(
    desktopId: String,
    desktopName: String,
    desktopFingerprint: String,
    signalName: String,
    routes: SignalASILinkRoutes,
    paired: Bool,
    accessProfile: String,
    accessScopes: Set<String>,
    capabilityManifestVersion: Int = 0,
    deviceMetadata: SignalASIDesktopDeviceMetadata? = nil,
    updatedAt: Date
  ) {
    self.desktopId = desktopId
    self.desktopName = desktopName
    self.desktopFingerprint = desktopFingerprint
    self.signalName = signalName
    self.routes = routes
    self.paired = paired
    self.accessProfile = accessProfile
    self.accessScopes = accessScopes
    self.capabilityManifestVersion = max(capabilityManifestVersion, 0)
    self.deviceMetadata = deviceMetadata
    self.updatedAt = updatedAt
  }

  var fullDesktopExecutor: Bool {
    accessProfile == SignalASILinkProtocol.accessDesktopExecutor &&
      accessScopes.contains(SignalASILinkProtocol.scopeDesktopExecutor)
  }

  enum CodingKeys: String, CodingKey {
    case desktopId
    case desktopName
    case desktopFingerprint
    case signalName
    case routes
    case paired
    case accessProfile
    case accessScopes
    case capabilityManifestVersion = "capability_manifest_version"
    case deviceMetadata = "device_metadata"
    case updatedAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      desktopId: try container.decode(String.self, forKey: .desktopId),
      desktopName: try container.decode(String.self, forKey: .desktopName),
      desktopFingerprint: try container.decode(String.self, forKey: .desktopFingerprint),
      signalName: try container.decode(String.self, forKey: .signalName),
      routes: try container.decode(SignalASILinkRoutes.self, forKey: .routes),
      paired: try container.decode(Bool.self, forKey: .paired),
      accessProfile: try container.decode(String.self, forKey: .accessProfile),
      accessScopes: try container.decode(Set<String>.self, forKey: .accessScopes),
      capabilityManifestVersion: try container.decodeIfPresent(Int.self, forKey: .capabilityManifestVersion) ?? 0,
      deviceMetadata: try container.decodeIfPresent(SignalASIDesktopDeviceMetadata.self, forKey: .deviceMetadata),
      updatedAt: try container.decode(Date.self, forKey: .updatedAt)
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(desktopId, forKey: .desktopId)
    try container.encode(desktopName, forKey: .desktopName)
    try container.encode(desktopFingerprint, forKey: .desktopFingerprint)
    try container.encode(signalName, forKey: .signalName)
    try container.encode(routes, forKey: .routes)
    try container.encode(paired, forKey: .paired)
    try container.encode(accessProfile, forKey: .accessProfile)
    try container.encode(accessScopes, forKey: .accessScopes)
    try container.encode(capabilityManifestVersion, forKey: .capabilityManifestVersion)
    try container.encodeIfPresent(deviceMetadata, forKey: .deviceMetadata)
    try container.encode(updatedAt, forKey: .updatedAt)
  }
}

enum VoiceRoutingMode: String, Codable, CaseIterable, Identifiable {
  case nativeAgent = "native_agent"
  case contact

  var id: String { rawValue }

  var displayTitle: String {
    switch self {
    case .nativeAgent: return "Native Agent"
    case .contact: return "Chat Contact"
    }
  }
}

enum WakeWordPolicy {
  static let wakeWord = "hello"
  static let configuredWords = [wakeWord]

  static func matches(_ transcript: String) -> Bool {
    commandText(from: transcript) != nil
  }

  /// Returns the spoken command after removing the fixed wake word.
  static func commandText(from transcript: String) -> String? {
    let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTranscript.isEmpty else { return nil }

    for wakeWord in configuredWords {
      guard let range = trimmedTranscript.range(
        of: wakeWord,
        options: [.caseInsensitive],
        range: nil,
        locale: Locale(identifier: "en_US_POSIX")
      ) else {
        continue
      }
      guard !requiresWordBoundaries(wakeWord) ||
        hasPhraseBoundaries(in: trimmedTranscript, range: range) else {
        continue
      }
      let command = (String(trimmedTranscript[..<range.lowerBound]) +
        String(trimmedTranscript[range.upperBound...]))
        .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
      return command.isEmpty ? "" : command
    }
    return nil
  }

  private static func hasPhraseBoundaries(
    in transcript: String,
    range: Range<String.Index>
  ) -> Bool {
    let beforeIsWord = range.lowerBound > transcript.startIndex &&
      isLetterOrNumber(transcript[transcript.index(before: range.lowerBound)])
    let afterIsWord = range.upperBound < transcript.endIndex &&
      isLetterOrNumber(transcript[range.upperBound])
    return !beforeIsWord && !afterIsWord
  }

  private static func requiresWordBoundaries(_ phrase: String) -> Bool {
    phrase.unicodeScalars.allSatisfy { scalar in
      (scalar.value >= 48 && scalar.value <= 57) ||
        (scalar.value >= 65 && scalar.value <= 90) ||
        (scalar.value >= 97 && scalar.value <= 122)
    }
  }

  private static func isLetterOrNumber(_ character: Character) -> Bool {
    character.isLetter || character.isNumber
  }
}

struct VoiceSettings: Codable, Equatable {
  var wakeListeningEnabled: Bool
  var speechRecognitionEnabled: Bool
  var textToSpeechEnabled: Bool
  var autoSendTranscripts: Bool
  var preferredLocaleIdentifier: String
  var wakeWords: [String]
  var wakeProvider: VoiceWakeProvider
  var wakeModel: String
  var wakeThreshold: Double
  var welcomeText: String
  var asrProvider: VoiceASRProvider
  var asrRecognitionPreference: VoiceRecognitionPreference
  var asrModelId: String
  var asrRuntimeMode: VoiceWhisperUserVoiceMode
  var onlineAsrAllowed: Bool
  var onlineAsrWifiOnly: Bool
  var onlineAsrMobileAllowed: Bool
  var onlineAsrAudioUploadAllowed: Bool
  var onlineAsrRequestServerDeletion: Bool
  var localAsrAlwaysPreferred: Bool
  var remoteWhisperAllowed: Bool
  var ttsProvider: VoiceTTSProvider
  var microsoftVoice: String
  var targetContactId: String
  var speakReplies: Bool
  var routingMode: VoiceRoutingMode

  init(
    wakeListeningEnabled: Bool,
    speechRecognitionEnabled: Bool,
    textToSpeechEnabled: Bool,
    autoSendTranscripts: Bool,
    preferredLocaleIdentifier: String,
    wakeWords _: [String] = VoiceSettings.defaultWakeWords,
    wakeProvider: VoiceWakeProvider = VoiceWakeProvider.defaultValue,
    wakeModel: String = VoiceSettings.defaultWakeModel,
    wakeThreshold: Double = 0.5,
    welcomeText: String = VoiceSettings.defaultWelcomeText,
    asrProvider: VoiceASRProvider = VoiceASRProvider.defaultValue,
    asrRecognitionPreference: VoiceRecognitionPreference? = nil,
    asrModelId: String = VoiceSettings.defaultAsrModelId,
    asrRuntimeMode: VoiceWhisperUserVoiceMode = .automatic,
    onlineAsrAllowed: Bool = false,
    onlineAsrWifiOnly: Bool = true,
    onlineAsrMobileAllowed: Bool = false,
    onlineAsrAudioUploadAllowed: Bool = false,
    onlineAsrRequestServerDeletion: Bool = true,
    localAsrAlwaysPreferred: Bool = false,
    remoteWhisperAllowed: Bool = false,
    ttsProvider: VoiceTTSProvider = VoiceTTSProvider.defaultValue,
    microsoftVoice: String = VoiceSettings.defaultMicrosoftVoice,
    targetContactId: String = "hermes",
    speakReplies: Bool = true,
    routingMode: VoiceRoutingMode = .nativeAgent
  ) {
    self.wakeListeningEnabled = wakeListeningEnabled
    self.speechRecognitionEnabled = speechRecognitionEnabled
    self.textToSpeechEnabled = textToSpeechEnabled
    self.autoSendTranscripts = autoSendTranscripts
    self.preferredLocaleIdentifier = preferredLocaleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(Locale.current.identifier)
    self.wakeWords = Self.defaultWakeWords
    self.wakeProvider = wakeProvider
    self.wakeModel = Self.normalizedWakeModel(wakeModel)
    self.wakeThreshold = min(max(wakeThreshold, 0.01), 0.99)
    self.welcomeText = welcomeText.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(Self.defaultWelcomeText)
    let recognitionPreference = asrRecognitionPreference ?? VoiceRecognitionPreference.migrated(
      provider: asrProvider,
      runtimeMode: asrRuntimeMode
    )
    self.asrProvider = recognitionPreference.provider
    self.asrRecognitionPreference = recognitionPreference
    self.asrModelId = VoiceWhisperModelCatalog.normalizedModelId(asrModelId)
    self.asrRuntimeMode = asrRuntimeMode
    self.onlineAsrAllowed = onlineAsrAllowed
    self.onlineAsrWifiOnly = onlineAsrWifiOnly
    self.onlineAsrMobileAllowed = onlineAsrMobileAllowed
    self.onlineAsrAudioUploadAllowed = onlineAsrAudioUploadAllowed
    self.onlineAsrRequestServerDeletion = onlineAsrRequestServerDeletion
    self.localAsrAlwaysPreferred = localAsrAlwaysPreferred
    self.remoteWhisperAllowed = remoteWhisperAllowed
    self.ttsProvider = ttsProvider
    self.microsoftVoice = microsoftVoice.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(Self.defaultMicrosoftVoice)
    self.targetContactId = targetContactId.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("hermes")
    self.speakReplies = speakReplies
    self.routingMode = routingMode
  }

  static let `default` = VoiceSettings(
    wakeListeningEnabled: true,
    speechRecognitionEnabled: true,
    textToSpeechEnabled: true,
    autoSendTranscripts: false,
    preferredLocaleIdentifier: Locale.current.identifier,
    wakeWords: defaultWakeWords,
    wakeProvider: VoiceWakeProvider.defaultValue,
    wakeModel: defaultWakeModel,
    wakeThreshold: 0.5,
    welcomeText: defaultWelcomeText,
    asrProvider: VoiceASRProvider.defaultValue,
    asrRecognitionPreference: .automatic,
    asrModelId: defaultAsrModelId,
    asrRuntimeMode: .automatic,
    onlineAsrAllowed: false,
    onlineAsrWifiOnly: true,
    onlineAsrMobileAllowed: false,
    onlineAsrAudioUploadAllowed: false,
    onlineAsrRequestServerDeletion: true,
    localAsrAlwaysPreferred: false,
    remoteWhisperAllowed: false,
    ttsProvider: VoiceTTSProvider.defaultValue,
    microsoftVoice: defaultMicrosoftVoice,
    targetContactId: "hermes",
    speakReplies: true,
    routingMode: .nativeAgent
  )

  static let defaultWakeWords = WakeWordPolicy.configuredWords

  static let defaultWelcomeText = "I am here. Welcome to SignalASI. Say your question or task."
  static let defaultWakeModel = "hello_world.onnx"
  static let supportedWakeModels = [defaultWakeModel]
  static let defaultAsrModelId = "tiny"
  static let defaultMicrosoftVoice = "zh-CN-XiaoxiaoNeural"

  var wakeWordsText: String {
    WakeWordPolicy.wakeWord
  }

  mutating func setASRRecognitionPreference(_ preference: VoiceRecognitionPreference) {
    asrRecognitionPreference = preference
    asrProvider = preference.provider
    asrRuntimeMode = preference.runtimeMode
  }

  var normalized: VoiceSettings {
    let recognitionPreference = asrRecognitionPreference.provider == asrProvider
      ? asrRecognitionPreference
      : VoiceRecognitionPreference.migrated(provider: asrProvider, runtimeMode: asrRuntimeMode)
    return VoiceSettings(
      wakeListeningEnabled: wakeListeningEnabled,
      speechRecognitionEnabled: speechRecognitionEnabled,
      textToSpeechEnabled: textToSpeechEnabled,
      autoSendTranscripts: autoSendTranscripts,
      preferredLocaleIdentifier: preferredLocaleIdentifier,
      wakeWords: wakeWords,
      wakeProvider: wakeProvider,
      wakeModel: wakeModel,
      wakeThreshold: wakeThreshold,
      welcomeText: welcomeText,
      asrProvider: asrProvider,
      asrRecognitionPreference: recognitionPreference,
      asrModelId: asrModelId,
      asrRuntimeMode: asrRuntimeMode,
      onlineAsrAllowed: onlineAsrAllowed,
      onlineAsrWifiOnly: onlineAsrWifiOnly,
      onlineAsrMobileAllowed: onlineAsrMobileAllowed,
      onlineAsrAudioUploadAllowed: onlineAsrAudioUploadAllowed,
      onlineAsrRequestServerDeletion: onlineAsrRequestServerDeletion,
      localAsrAlwaysPreferred: localAsrAlwaysPreferred,
      remoteWhisperAllowed: remoteWhisperAllowed,
      ttsProvider: ttsProvider,
      microsoftVoice: microsoftVoice,
      targetContactId: targetContactId,
      speakReplies: speakReplies,
      routingMode: routingMode
    )
  }

  enum CodingKeys: String, CodingKey {
    case wakeListeningEnabled
    case speechRecognitionEnabled
    case textToSpeechEnabled
    case autoSendTranscripts
    case preferredLocaleIdentifier
    case wakeWords = "wake_words"
    case wakeProvider = "wake_provider"
    case wakeModel = "wake_model"
    case wakeThreshold = "wake_threshold"
    case welcomeText = "welcome_text"
    case asrProvider = "asr_provider"
    case asrRecognitionPreference = "asr_recognition_preference"
    case asrModelId = "asr_model"
    case asrRuntimeMode = "asr_runtime_mode"
    case onlineAsrAllowed = "online_asr_allowed"
    case onlineAsrWifiOnly = "online_asr_wifi_only"
    case onlineAsrMobileAllowed = "online_asr_mobile_allowed"
    case onlineAsrAudioUploadAllowed = "online_asr_audio_upload_allowed"
    case onlineAsrRequestServerDeletion = "online_asr_request_server_deletion"
    case localAsrAlwaysPreferred = "local_asr_always_preferred"
    case remoteWhisperAllowed = "remote_whisper_allowed"
    case ttsProvider = "tts_provider"
    case microsoftVoice = "microsoft_voice"
    case targetContactId = "target_contact_id"
    case speakReplies = "speak_replies"
    case routingMode = "routing_mode"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      wakeListeningEnabled: try container.decodeIfPresent(Bool.self, forKey: .wakeListeningEnabled) ?? true,
      speechRecognitionEnabled: try container.decodeIfPresent(Bool.self, forKey: .speechRecognitionEnabled) ?? true,
      textToSpeechEnabled: try container.decodeIfPresent(Bool.self, forKey: .textToSpeechEnabled) ?? true,
      autoSendTranscripts: try container.decodeIfPresent(Bool.self, forKey: .autoSendTranscripts) ?? false,
      preferredLocaleIdentifier: try container.decodeIfPresent(String.self, forKey: .preferredLocaleIdentifier) ?? Locale.current.identifier,
      wakeWords: try container.decodeIfPresent([String].self, forKey: .wakeWords) ?? Self.defaultWakeWords,
      wakeProvider: VoiceWakeProvider.normalized(try container.decodeIfPresent(String.self, forKey: .wakeProvider)),
      wakeModel: try container.decodeIfPresent(String.self, forKey: .wakeModel) ?? Self.defaultWakeModel,
      wakeThreshold: try container.decodeIfPresent(Double.self, forKey: .wakeThreshold) ?? 0.5,
      welcomeText: try container.decodeIfPresent(String.self, forKey: .welcomeText) ?? Self.defaultWelcomeText,
      asrProvider: VoiceASRProvider.normalized(try container.decodeIfPresent(String.self, forKey: .asrProvider)),
      asrRecognitionPreference: (try container.decodeIfPresent(String.self, forKey: .asrRecognitionPreference))
        .map { VoiceRecognitionPreference.normalized($0) },
      asrModelId: try container.decodeIfPresent(String.self, forKey: .asrModelId) ?? Self.defaultAsrModelId,
      asrRuntimeMode: VoiceWhisperUserVoiceMode.normalized(
        try container.decodeIfPresent(String.self, forKey: .asrRuntimeMode)
      ),
      onlineAsrAllowed: try container.decodeIfPresent(Bool.self, forKey: .onlineAsrAllowed) ?? false,
      onlineAsrWifiOnly: try container.decodeIfPresent(Bool.self, forKey: .onlineAsrWifiOnly) ?? true,
      onlineAsrMobileAllowed: try container.decodeIfPresent(Bool.self, forKey: .onlineAsrMobileAllowed) ?? false,
      onlineAsrAudioUploadAllowed: try container.decodeIfPresent(Bool.self, forKey: .onlineAsrAudioUploadAllowed) ?? false,
      onlineAsrRequestServerDeletion: try container.decodeIfPresent(Bool.self, forKey: .onlineAsrRequestServerDeletion) ?? true,
      localAsrAlwaysPreferred: try container.decodeIfPresent(Bool.self, forKey: .localAsrAlwaysPreferred) ?? false,
      remoteWhisperAllowed: try container.decodeIfPresent(Bool.self, forKey: .remoteWhisperAllowed) ?? false,
      ttsProvider: VoiceTTSProvider.normalized(try container.decodeIfPresent(String.self, forKey: .ttsProvider)),
      microsoftVoice: try container.decodeIfPresent(String.self, forKey: .microsoftVoice) ?? Self.defaultMicrosoftVoice,
      targetContactId: try container.decodeIfPresent(String.self, forKey: .targetContactId) ?? "hermes",
      speakReplies: try container.decodeIfPresent(Bool.self, forKey: .speakReplies) ?? true,
      routingMode: try container.decodeIfPresent(VoiceRoutingMode.self, forKey: .routingMode) ?? .nativeAgent
    )
  }

  static func wakeWords(from text: String) -> [String] {
    _ = text
    return defaultWakeWords
  }

  private static func normalizedWakeModel(_ value: String) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return supportedWakeModels.contains(normalized) ? normalized : defaultWakeModel
  }
}

enum AgentActionKind: String, Codable, CaseIterable, Identifiable {
  case readScreen = "READ_SCREEN"
  case saveScreenKnowledge = "SAVE_SCREEN_KNOWLEDGE"
  case draftPlan = "DRAFT_PLAN"
  case tap = "TAP"
  case typeText = "TYPE_TEXT"
  case swipe = "SWIPE"
  case longPress = "LONG_PRESS"
  case back = "BACK"
  case home = "HOME"
  case recents = "RECENTS"
  case lockScreen = "LOCK_SCREEN"
  case openApp = "OPEN_APP"
  case openURL = "OPEN_URL"
  case setAlarm = "SET_ALARM"
  case createNotification = "CREATE_NOTIFICATION"
  case replyNotification = "REPLY_NOTIFICATION"
  case importWebKnowledge = "IMPORT_WEB_KNOWLEDGE"
  case copyScreenText = "COPY_SCREEN_TEXT"
  case deleteText = "DELETE_TEXT"
  case pasteText = "PASTE_TEXT"
  case callConnector = "CALL_CONNECTOR"
  case callNativeTool = "CALL_NATIVE_TOOL"
  case controlDevice = "CONTROL_DEVICE"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentActionKind {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .draftPlan
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

enum AgentActionStatus: String, Codable, CaseIterable, Identifiable {
  case proposed = "PROPOSED"
  case pendingConfirmation = "PENDING_CONFIRMATION"
  case running = "RUNNING"
  case waitingResponse = "WAITING_RESPONSE"
  case completed = "COMPLETED"
  case failed = "FAILED"
  case blocked = "BLOCKED"
  case rolledBack = "ROLLED_BACK"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentActionStatus {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .pendingConfirmation
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

enum AgentRisk: String, Codable, CaseIterable, Identifiable {
  case low = "LOW"
  case medium = "MEDIUM"
  case high = "HIGH"
  case blocked = "BLOCKED"

  var id: String { rawValue }

  var weight: Int {
    switch self {
    case .low: return 1
    case .medium: return 2
    case .high: return 3
    case .blocked: return 4
    }
  }

  static func fromWireValue(_ value: String?) -> AgentRisk {
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

enum AgentElementOrigin: String, Codable, CaseIterable, Identifiable {
  case accessibility = "ACCESSIBILITY"
  case visualOcr = "VISUAL_OCR"
  case fused = "FUSED"
  case manual = "MANUAL"
  case unknown = "UNKNOWN"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentElementOrigin {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()
      .replacingOccurrences(of: "-", with: "_")
      .replacingOccurrences(of: " ", with: "_") ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .unknown
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

enum AgentVisualRole: String, Codable, CaseIterable, Identifiable {
  case title = "TITLE"
  case button = "BUTTON"
  case input = "INPUT"
  case navigation = "NAVIGATION"
  case listItem = "LIST_ITEM"
  case text = "TEXT"
  case unknown = "UNKNOWN"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentVisualRole {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()
      .replacingOccurrences(of: "-", with: "_")
      .replacingOccurrences(of: " ", with: "_") ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .unknown
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

struct AgentVisualElement: Codable, Equatable {
  var text: String
  var bounds: String
  var confidence: Double
  var role: AgentVisualRole
  var actionable: Bool
  var inputCandidate: Bool

  init(
    text: String,
    bounds: String,
    confidence: Double = 1,
    role: AgentVisualRole = .unknown,
    actionable: Bool = false,
    inputCandidate: Bool = false
  ) {
    self.text = String(text.prefix(Self.maximumTextLength))
    self.bounds = bounds
    self.confidence = min(max(confidence, 0), 1)
    self.role = role
    self.actionable = actionable
    self.inputCandidate = inputCandidate
  }

  enum CodingKeys: String, CodingKey {
    case text
    case bounds
    case confidence
    case role
    case actionable
    case inputCandidate = "input_candidate"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      text: try container.decodeIfPresent(String.self, forKey: .text) ?? "",
      bounds: try container.decodeIfPresent(String.self, forKey: .bounds) ?? "",
      confidence: try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 1,
      role: try container.decodeIfPresent(AgentVisualRole.self, forKey: .role) ?? .unknown,
      actionable: try container.decodeIfPresent(Bool.self, forKey: .actionable) ?? false,
      inputCandidate: try container.decodeIfPresent(Bool.self, forKey: .inputCandidate) ?? false
    )
  }

  private static let maximumTextLength = 500
}

struct AgentVisualScene: Codable, Equatable {
  var width: Int
  var height: Int
  var modelProfile: String
  var elements: [AgentVisualElement]
  var actionCandidateCount: Int
  var inputCandidateCount: Int
  var timestampMillis: Int64

  init(
    width: Int = 0,
    height: Int = 0,
    modelProfile: String = "none",
    elements: [AgentVisualElement] = [],
    actionCandidateCount: Int? = nil,
    inputCandidateCount: Int? = nil,
    timestampMillis: Int64 = 0
  ) {
    self.width = max(width, 0)
    self.height = max(height, 0)
    self.modelProfile = modelProfile
    self.elements = elements
    self.actionCandidateCount = max(actionCandidateCount ?? elements.filter(\.actionable).count, 0)
    self.inputCandidateCount = max(inputCandidateCount ?? elements.filter(\.inputCandidate).count, 0)
    self.timestampMillis = max(timestampMillis, 0)
  }

  var available: Bool {
    width > 0 && height > 0 && !elements.isEmpty
  }

  enum CodingKeys: String, CodingKey {
    case width
    case height
    case modelProfile = "model_profile"
    case elements
    case actionCandidateCount = "action_candidate_count"
    case inputCandidateCount = "input_candidate_count"
    case timestampMillis = "timestamp_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      width: try container.decodeIfPresent(Int.self, forKey: .width) ?? 0,
      height: try container.decodeIfPresent(Int.self, forKey: .height) ?? 0,
      modelProfile: try container.decodeIfPresent(String.self, forKey: .modelProfile) ?? "none",
      elements: try container.decodeIfPresent([AgentVisualElement].self, forKey: .elements) ?? [],
      actionCandidateCount: try container.decodeIfPresent(Int.self, forKey: .actionCandidateCount),
      inputCandidateCount: try container.decodeIfPresent(Int.self, forKey: .inputCandidateCount),
      timestampMillis: try container.decodeIfPresent(Int64.self, forKey: .timestampMillis) ?? 0
    )
  }
}

struct AgentScreenElement: Codable, Equatable, Identifiable {
  var label: String
  var viewId: String
  var className: String
  var bounds: String
  var origin: AgentElementOrigin
  var confidence: Double
  var visualRole: AgentVisualRole
  var actionable: Bool

  var id: String {
    [viewId, label, bounds].joined(separator: "|")
  }

  init(
    label: String,
    viewId: String,
    className: String,
    bounds: String,
    origin: AgentElementOrigin = .accessibility,
    confidence: Double = 1,
    visualRole: AgentVisualRole = .unknown,
    actionable: Bool = true
  ) {
    self.label = String(label.prefix(Self.maximumLabelLength))
    self.viewId = String(viewId.prefix(Self.maximumIdentifierLength))
    self.className = String(className.prefix(Self.maximumIdentifierLength))
    self.bounds = bounds
    self.origin = origin
    self.confidence = min(max(confidence, 0), 1)
    self.visualRole = visualRole
    self.actionable = actionable
  }

  enum CodingKeys: String, CodingKey {
    case label
    case viewId = "view_id"
    case className = "class_name"
    case bounds
    case origin
    case confidence
    case visualRole = "visual_role"
    case actionable
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      label: try container.decodeIfPresent(String.self, forKey: .label) ?? "",
      viewId: try container.decodeIfPresent(String.self, forKey: .viewId) ?? "",
      className: try container.decodeIfPresent(String.self, forKey: .className) ?? "",
      bounds: try container.decodeIfPresent(String.self, forKey: .bounds) ?? "",
      origin: try container.decodeIfPresent(AgentElementOrigin.self, forKey: .origin) ?? .accessibility,
      confidence: try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 1,
      visualRole: try container.decodeIfPresent(AgentVisualRole.self, forKey: .visualRole) ?? .unknown,
      actionable: try container.decodeIfPresent(Bool.self, forKey: .actionable) ?? true
    )
  }

  private static let maximumLabelLength = 500
  private static let maximumIdentifierLength = 300
}

enum AgentVisualGrounding {
  static func analyze(
    rawElements: [AgentVisualElement],
    width: Int,
    height: Int,
    timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> AgentVisualScene {
    guard width > 0 && height > 0 else {
      return AgentVisualScene()
    }
    var seen: Set<String> = []
    var elements: [AgentVisualElement] = []
    for raw in rawElements {
      let text = normalizedText(raw.text)
      guard !text.isEmpty,
            let rect = AgentVisualBounds.parse(raw.bounds),
            rect.width > 1,
            rect.height > 1 else {
        continue
      }
      let dedupeKey = "\(text.lowercased()):\(raw.bounds)"
      guard seen.insert(dedupeKey).inserted else {
        continue
      }
      let role = inferRole(text: text, rect: rect, width: width, height: height)
      elements.append(
        AgentVisualElement(
          text: text,
          bounds: raw.bounds,
          confidence: raw.confidence,
          role: role,
          actionable: actionableRoles.contains(role),
          inputCandidate: role == .input
        )
      )
      if elements.count >= maxVisualElements {
        break
      }
    }
    return AgentVisualScene(
      width: width,
      height: height,
      modelProfile: "mlkit-ocr-layout-v1",
      elements: elements,
      timestampMillis: timestampMillis
    )
  }

  static func fuseClickableElements(
    accessibilityElements: [AgentScreenElement],
    scene: AgentVisualScene
  ) -> [AgentScreenElement] {
    fuse(
      accessibilityElements: accessibilityElements,
      visualElements: scene.elements.filter(\.actionable),
      limit: maxFusedActions,
      requireInput: false
    )
  }

  static func fuseInputFields(
    accessibilityElements: [AgentScreenElement],
    scene: AgentVisualScene
  ) -> [AgentScreenElement] {
    fuse(
      accessibilityElements: accessibilityElements,
      visualElements: scene.elements.filter(\.inputCandidate),
      limit: maxFusedFields,
      requireInput: true
    )
  }

  private static func fuse(
    accessibilityElements: [AgentScreenElement],
    visualElements: [AgentVisualElement],
    limit: Int,
    requireInput: Bool
  ) -> [AgentScreenElement] {
    var visualPool = visualElements
    var fused = accessibilityElements.map { accessibility -> AgentScreenElement in
      guard let matchIndex = bestMatchIndex(for: accessibility, in: visualPool),
            matchScore(accessibility: accessibility, visual: visualPool[matchIndex]) >= minimumFusionScore else {
        return accessibility
      }
      let match = visualPool.remove(at: matchIndex)
      return AgentScreenElement(
        label: accessibility.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? match.text : accessibility.label,
        viewId: accessibility.viewId,
        className: accessibility.className,
        bounds: accessibility.bounds,
        origin: .fused,
        confidence: max(accessibility.confidence, match.confidence),
        visualRole: match.role,
        actionable: accessibility.actionable || match.actionable
      )
    }
    var visualIndex = 0
    for visual in visualPool where fused.count < limit {
      guard visual.confidence >= minVisualActionConfidence,
            !requireInput || visual.inputCandidate,
            !fused.contains(where: { overlapRatio($0.bounds, visual.bounds) >= duplicateOverlapThreshold }) else {
        continue
      }
      let roleName = visual.role.rawValue.lowercased()
      let classRole = roleName.prefix(1).uppercased() + String(roleName.dropFirst())
      fused.append(
        AgentScreenElement(
          label: visual.text,
          viewId: "visual:\(roleName):\(visualIndex)",
          className: "AgentVisual\(classRole)",
          bounds: visual.bounds,
          origin: .visualOcr,
          confidence: visual.confidence,
          visualRole: visual.role,
          actionable: visual.actionable
        )
      )
      visualIndex += 1
    }
    return Array(fused.prefix(limit))
  }

  private static func bestMatchIndex(for accessibility: AgentScreenElement, in visualPool: [AgentVisualElement]) -> Int? {
    var bestIndex: Int?
    var bestScore = 0.0
    for (index, visual) in visualPool.enumerated() {
      let score = matchScore(accessibility: accessibility, visual: visual)
      if score > bestScore {
        bestScore = score
        bestIndex = index
      }
    }
    return bestIndex
  }

  private static func inferRole(text: String, rect: AgentVisualBounds, width: Int, height: Int) -> AgentVisualRole {
    let normalized = text.lowercased()
    let centerY = Double(rect.centerY) / Double(height)
    let widthRatio = Double(rect.width) / Double(width)
    let shortLabel = text.count <= 36
    if inputTerms.contains(where: normalized.contains) {
      return .input
    }
    if actionTerms.contains(normalized) ||
      (shortLabel && actionTerms.contains(where: { normalized.hasPrefix($0) })) {
      return .button
    }
    if centerY >= 0.82 && shortLabel {
      return .navigation
    }
    if centerY <= 0.18 && widthRatio >= 0.18 {
      return .title
    }
    if shortLabel && widthRatio >= 0.22 && (0.18...0.82).contains(centerY) {
      return .listItem
    }
    return .text
  }

  private static func matchScore(accessibility: AgentScreenElement, visual: AgentVisualElement) -> Double {
    let overlap = overlapRatio(accessibility.bounds, visual.bounds)
    let accessibilityLabel = accessibility.label.normalizedElementLabel()
    let visualLabel = visual.text.normalizedElementLabel()
    let labelScore: Double
    if accessibilityLabel.isEmpty || visualLabel.isEmpty {
      labelScore = 0
    } else if accessibilityLabel == visualLabel {
      labelScore = 1
    } else if accessibilityLabel.contains(visualLabel) || visualLabel.contains(accessibilityLabel) {
      labelScore = 0.75
    } else {
      labelScore = 0
    }
    return max(overlap, labelScore)
  }

  private static func overlapRatio(_ firstBounds: String, _ secondBounds: String) -> Double {
    guard let first = AgentVisualBounds.parse(firstBounds),
          let second = AgentVisualBounds.parse(secondBounds),
          let intersection = first.intersection(second) else {
      return 0
    }
    let smallerArea = min(first.area, second.area)
    guard smallerArea > 0 else {
      return 0
    }
    return Double(intersection.area) / Double(smallerArea)
  }

  private static func normalizedText(_ value: String) -> String {
    String(
      value
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .prefix(500)
    )
  }

  private static let maxVisualElements = 160
  private static let maxFusedActions = 80
  private static let maxFusedFields = 30
  private static let minVisualActionConfidence = 0.55
  private static let minimumFusionScore = 0.45
  private static let duplicateOverlapThreshold = 0.65
  private static let actionableRoles: Set<AgentVisualRole> = [
    .button,
    .navigation,
    .listItem
  ]
  private static let actionTerms = [
    "ok", "yes", "no", "done", "next", "continue", "confirm", "cancel", "save", "send", "search",
    "open", "close", "add", "delete", "edit", "allow", "deny", "login", "sign in", "submit", "share",
    "\u{786e}\u{5b9a}", "\u{53d6}\u{6d88}", "\u{4fdd}\u{5b58}", "\u{53d1}\u{9001}",
    "\u{641c}\u{7d22}", "\u{4e0b}\u{4e00}\u{6b65}", "\u{7ee7}\u{7eed}",
    "\u{786e}\u{8ba4}", "\u{5141}\u{8bb8}", "\u{62d2}\u{7edd}", "\u{767b}\u{5f55}",
    "\u{63d0}\u{4ea4}", "\u{6dfb}\u{52a0}", "\u{5220}\u{9664}", "\u{7f16}\u{8f91}",
    "\u{5173}\u{95ed}", "\u{6253}\u{5f00}", "\u{5206}\u{4eab}"
  ]
  private static let inputTerms = [
    "search", "type", "enter", "message", "email", "phone", "name", "password", "input",
    "\u{641c}\u{7d22}", "\u{8f93}\u{5165}", "\u{6d88}\u{606f}", "\u{90ae}\u{7bb1}",
    "\u{624b}\u{673a}\u{53f7}", "\u{59d3}\u{540d}", "\u{5bc6}\u{7801}"
  ]
}

enum AgentScreenElementMatcher {
  static func resolve(query: String, elements: [AgentScreenElement]) -> AgentScreenElement? {
    let clean = query.normalizedElementLabel()
    guard !clean.isEmpty else {
      return nil
    }
    return elements
      .map { ($0, score(query: clean, element: $0)) }
      .filter { $0.1 > 0 }
      .sorted { first, second in
        if first.1 != second.1 {
          return first.1 > second.1
        }
        if first.0.confidence != second.0.confidence {
          return first.0.confidence > second.0.confidence
        }
        return first.0.origin != .visualOcr && second.0.origin == .visualOcr
      }
      .first?
      .0
  }

  private static func score(query: String, element: AgentScreenElement) -> Int {
    let label = element.label.normalizedElementLabel()
    let viewId = element.viewId.normalizedElementLabel()
    let className = element.className.normalizedElementLabel()
    let role = element.visualRole.rawValue.normalizedElementLabel()
    if viewId == query { return 140 }
    if label == query { return 120 }
    if label.hasPrefix(query) { return 100 }
    if label.contains(query) { return 90 }
    if query.contains(label) && label.count >= 2 { return 75 }
    if viewId.contains(query) { return 65 }
    if className.contains(query) { return 35 }
    if role == query { return 25 }
    return 0
  }
}

private struct AgentVisualBounds: Equatable {
  var left: Int
  var top: Int
  var right: Int
  var bottom: Int

  var width: Int { right - left }
  var height: Int { bottom - top }
  var centerY: Int { (top + bottom) / 2 }
  var area: Int { width * height }

  static func parse(_ value: String) -> AgentVisualBounds? {
    let parts = value.split(separator: ",").map {
      Int(String($0).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    guard parts.count == 4,
          let left = parts[0],
          let top = parts[1],
          let right = parts[2],
          let bottom = parts[3],
          right > left,
          bottom > top else {
      return nil
    }
    return AgentVisualBounds(left: left, top: top, right: right, bottom: bottom)
  }

  func intersection(_ other: AgentVisualBounds) -> AgentVisualBounds? {
    let nextLeft = max(left, other.left)
    let nextTop = max(top, other.top)
    let nextRight = min(right, other.right)
    let nextBottom = min(bottom, other.bottom)
    guard nextRight > nextLeft && nextBottom > nextTop else {
      return nil
    }
    return AgentVisualBounds(left: nextLeft, top: nextTop, right: nextRight, bottom: nextBottom)
  }
}

private extension String {
  func normalizedElementLabel() -> String {
    unicodeScalars
      .filter { CharacterSet.alphanumerics.contains($0) }
      .map(String.init)
      .joined()
      .lowercased()
  }
}
