import Foundation

enum AgentEndpointStatus: String, Codable, CaseIterable, Identifiable {
  case online = "ONLINE"
  case offline = "OFFLINE"
  case idle = "IDLE"
  case busy = "BUSY"
  case degraded = "DEGRADED"
  case updating = "UPDATING"
  case permissionRequired = "PERMISSION_REQUIRED"
  case unreachable = "UNREACHABLE"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentEndpointStatus {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .offline
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

enum AgentResourceType: String, Codable, CaseIterable, Identifiable {
  case onDeviceModel = "ON_DEVICE_MODEL"
  case remoteLocalModel = "REMOTE_LOCAL_MODEL"
  case cloudModel = "CLOUD_MODEL"
  case localAgent = "LOCAL_AGENT"
  case remoteAgent = "REMOTE_AGENT"
  case localTool = "LOCAL_TOOL"
  case localMcp = "LOCAL_MCP"
  case remoteMcp = "REMOTE_MCP"
  case cloudMcp = "CLOUD_MCP"
  case localSkill = "LOCAL_SKILL"
  case remoteSkill = "REMOTE_SKILL"
  case cloudSkill = "CLOUD_SKILL"
  case homeAssistant = "HOME_ASSISTANT"
  case customDevice = "CUSTOM_DEVICE"
  case knowledge = "KNOWLEDGE"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentResourceType {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .cloudModel
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

enum AgentResourceCost: String, Codable, CaseIterable, Comparable, Identifiable {
  case free = "FREE"
  case low = "LOW"
  case medium = "MEDIUM"
  case high = "HIGH"

  var id: String { rawValue }
  var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

  static func < (lhs: AgentResourceCost, rhs: AgentResourceCost) -> Bool {
    lhs.rank < rhs.rank
  }
}

enum AgentResourceLatency: String, Codable, CaseIterable, Comparable, Identifiable {
  case instant = "INSTANT"
  case fast = "FAST"
  case normal = "NORMAL"
  case slow = "SLOW"

  var id: String { rawValue }
  var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

  static func < (lhs: AgentResourceLatency, rhs: AgentResourceLatency) -> Bool {
    lhs.rank < rhs.rank
  }
}

enum AgentResourceQuality: String, Codable, CaseIterable, Comparable, Identifiable {
  case basic = "BASIC"
  case standard = "STANDARD"
  case strong = "STRONG"
  case frontier = "FRONTIER"

  var id: String { rawValue }
  var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

  static func < (lhs: AgentResourceQuality, rhs: AgentResourceQuality) -> Bool {
    lhs.rank < rhs.rank
  }
}

enum AgentResourceTrust: String, Codable, CaseIterable, Identifiable {
  case phoneSystem = "PHONE_SYSTEM"
  case verifiedPaired = "VERIFIED_PAIRED"
  case privateConfigured = "PRIVATE_CONFIGURED"
  case cloudConfigured = "CLOUD_CONFIGURED"
  case unknown = "UNKNOWN"

  var id: String { rawValue }
}

enum AgentResourceEnergy: String, Codable, CaseIterable, Comparable, Identifiable {
  case minimal = "MINIMAL"
  case low = "LOW"
  case moderate = "MODERATE"
  case high = "HIGH"

  var id: String { rawValue }
  var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

  static func < (lhs: AgentResourceEnergy, rhs: AgentResourceEnergy) -> Bool {
    lhs.rank < rhs.rank
  }

  static func fromWireValue(_ value: String?) -> AgentResourceEnergy {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .low
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

struct AgentProtocolRange: Codable, Equatable {
  var preferred: String
  var minimum: String
  var maximum: String
  var features: Set<String>

  init(
    preferred: String = "1.1",
    minimum: String = "1.0",
    maximum: String = "1.1",
    features: Set<String> = []
  ) {
    self.preferred = preferred
    self.minimum = minimum
    self.maximum = maximum
    self.features = features
  }
}

struct AgentRegistration: Codable, Equatable, Identifiable {
  var agentId: String
  var installationId: String
  var deviceId: String
  var providerId: String
  var displayName: String
  var kind: AgentConnectorKind
  var location: AgentResourceLocation
  var status: AgentEndpointStatus
  var capabilities: Set<AgentCapability>
  var toolIds: Set<String>
  var permissionScopes: Set<String>
  var `protocol`: AgentProtocolRange
  var connectionKind: AgentConnectionKind
  var cost: AgentResourceCost
  var latency: AgentResourceLatency
  var trust: AgentResourceTrust
  var activeRuns: Int
  var maxParallelRuns: Int
  var capabilitiesHash: String
  var failureDomain: String
  var runtimeFailureDomain: String
  var adapterType: String
  var independentlyUpgradeable: Bool
  var providerProfile: ProviderProfile?
  var lastHeartbeatMillis: Int64
  var updatedAtMillis: Int64

  var id: String { agentId }
  var hasCapacity: Bool { activeRuns < max(maxParallelRuns, 1) }

  init(
    agentId: String,
    installationId: String,
    deviceId: String,
    providerId: String,
    displayName: String,
    kind: AgentConnectorKind = .agent,
    location: AgentResourceLocation = .trustedDesktop,
    status: AgentEndpointStatus = .online,
    capabilities: Set<AgentCapability> = [.chat],
    toolIds: Set<String> = [],
    permissionScopes: Set<String> = [],
    protocol: AgentProtocolRange = AgentProtocolRange(),
    connectionKind: AgentConnectionKind = .galaxyssiLink,
    cost: AgentResourceCost = .free,
    latency: AgentResourceLatency = .normal,
    trust: AgentResourceTrust = .verifiedPaired,
    activeRuns: Int = 0,
    maxParallelRuns: Int = 1,
    capabilitiesHash: String = "",
    failureDomain: String = "",
    runtimeFailureDomain: String = "",
    adapterType: String = "",
    independentlyUpgradeable: Bool = true,
    providerProfile: ProviderProfile? = nil,
    lastHeartbeatMillis: Int64 = 0,
    updatedAtMillis: Int64 = 0
  ) {
    self.agentId = agentId
    self.installationId = installationId
    self.deviceId = deviceId
    self.providerId = providerId
    self.displayName = displayName
    self.kind = kind
    self.location = location
    self.status = status
    self.capabilities = capabilities
    self.toolIds = toolIds
    self.permissionScopes = permissionScopes
    self.`protocol` = `protocol`
    self.connectionKind = connectionKind
    self.cost = cost
    self.latency = latency
    self.trust = trust
    self.activeRuns = activeRuns
    self.maxParallelRuns = maxParallelRuns
    self.capabilitiesHash = capabilitiesHash
    self.failureDomain = failureDomain
    self.runtimeFailureDomain = runtimeFailureDomain
    self.adapterType = adapterType
    self.independentlyUpgradeable = independentlyUpgradeable
    self.providerProfile = providerProfile
    self.lastHeartbeatMillis = lastHeartbeatMillis
    self.updatedAtMillis = updatedAtMillis
  }

  enum CodingKeys: String, CodingKey {
    case agentId = "agent_id"
    case installationId = "installation_id"
    case deviceId = "device_id"
    case providerId = "provider_id"
    case displayName = "display_name"
    case kind
    case location
    case status
    case capabilities
    case toolIds = "tool_ids"
    case permissionScopes = "permission_scopes"
    case `protocol`
    case connectionKind = "connection_kind"
    case cost
    case latency
    case trust
    case activeRuns = "active_runs"
    case maxParallelRuns = "max_parallel_runs"
    case capabilitiesHash = "capabilities_hash"
    case failureDomain = "failure_domain"
    case runtimeFailureDomain = "runtime_failure_domain"
    case adapterType = "adapter_type"
    case independentlyUpgradeable = "independently_upgradeable"
    case providerProfile = "provider_profile"
    case lastHeartbeatMillis = "last_heartbeat_millis"
    case updatedAtMillis = "updated_at_millis"
  }
}

enum ProviderProfileKind: String, Codable, CaseIterable, Identifiable {
  case agent = "AGENT"
  case cloudModel = "CLOUD_MODEL"
  case localModel = "LOCAL_MODEL"

  var id: String { rawValue }
}

struct ProviderPricingProfile: Codable, Equatable {
  var tier: AgentResourceCost
  var inputMicrosPerMillionTokens: Int64?
  var outputMicrosPerMillionTokens: Int64?
  var currency: String
  var source: String

  init(
    tier: AgentResourceCost,
    inputMicrosPerMillionTokens: Int64? = nil,
    outputMicrosPerMillionTokens: Int64? = nil,
    currency: String = "USD",
    source: String = "catalog_tier"
  ) {
    self.tier = tier
    self.inputMicrosPerMillionTokens = inputMicrosPerMillionTokens
    self.outputMicrosPerMillionTokens = outputMicrosPerMillionTokens
    self.currency = currency.isEmpty ? "USD" : currency
    self.source = source.isEmpty ? "catalog_tier" : source
  }

  enum CodingKeys: String, CodingKey {
    case tier
    case inputMicrosPerMillionTokens = "input_micros_per_million_tokens"
    case outputMicrosPerMillionTokens = "output_micros_per_million_tokens"
    case currency
    case source
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      tier: ProviderProfileCatalog.cost(
        try container.decodeIfPresent(String.self, forKey: .tier),
        fallback: .free
      ),
      inputMicrosPerMillionTokens: try container.decodeIfPresent(Int64.self, forKey: .inputMicrosPerMillionTokens),
      outputMicrosPerMillionTokens: try container.decodeIfPresent(Int64.self, forKey: .outputMicrosPerMillionTokens),
      currency: try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD",
      source: try container.decodeIfPresent(String.self, forKey: .source) ?? "catalog_tier"
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(tier.rawValue.lowercased(), forKey: .tier)
    try container.encodeIfPresent(inputMicrosPerMillionTokens, forKey: .inputMicrosPerMillionTokens)
    try container.encodeIfPresent(outputMicrosPerMillionTokens, forKey: .outputMicrosPerMillionTokens)
    try container.encode(currency, forKey: .currency)
    try container.encode(source, forKey: .source)
  }
}

struct ProviderPerformanceProfile: Codable, Equatable {
  var attempts: Int
  var successes: Int
  var failures: Int
  var consecutiveFailures: Int
  var failureRate: Double
  var ewmaLatencyMs: Double
  var lastObservedAtMillis: Int64

  init(
    attempts: Int = 0,
    successes: Int = 0,
    failures: Int = 0,
    consecutiveFailures: Int = 0,
    failureRate: Double = 0,
    ewmaLatencyMs: Double = 0,
    lastObservedAtMillis: Int64 = 0
  ) {
    self.attempts = max(0, attempts)
    self.successes = max(0, successes)
    self.failures = max(0, failures)
    self.consecutiveFailures = max(0, consecutiveFailures)
    self.failureRate = min(max(failureRate, 0), 1)
    self.ewmaLatencyMs = max(0, ewmaLatencyMs)
    self.lastObservedAtMillis = max(0, lastObservedAtMillis)
  }

  enum CodingKeys: String, CodingKey {
    case attempts
    case successes
    case failures
    case consecutiveFailures = "consecutive_failures"
    case failureRate = "failure_rate"
    case ewmaLatencyMs = "ewma_latency_ms"
    case lastObservedAtMillis = "last_observed_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      attempts: try container.decodeIfPresent(Int.self, forKey: .attempts) ?? 0,
      successes: try container.decodeIfPresent(Int.self, forKey: .successes) ?? 0,
      failures: try container.decodeIfPresent(Int.self, forKey: .failures) ?? 0,
      consecutiveFailures: try container.decodeIfPresent(Int.self, forKey: .consecutiveFailures) ?? 0,
      failureRate: try container.decodeIfPresent(Double.self, forKey: .failureRate) ?? 0,
      ewmaLatencyMs: try container.decodeIfPresent(Double.self, forKey: .ewmaLatencyMs) ?? 0,
      lastObservedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .lastObservedAtMillis) ?? 0
    )
  }
}

struct ProviderProfile: Codable, Equatable, Identifiable {
  static let schemaVersion = 1

  var profileId: String
  var resourceId: String
  var providerId: String
  var productId: String
  var displayName: String
  var kind: ProviderProfileKind
  var location: AgentResourceLocation
  var status: AgentConnectorStatus
  var protocolFamily: String
  var adapterType: String
  var modelId: String
  var capabilities: Set<AgentCapability>
  var toolIds: Set<String>
  var contextWindowTokens: Int
  var maxOutputTokens: Int
  var maxParallelRuns: Int
  var supportsTools: Bool
  var supportsStreaming: Bool
  var supportsBackground: Bool
  var latency: AgentResourceLatency
  var quality: AgentResourceQuality
  var trust: AgentResourceTrust
  var failureDomain: String
  var endpointConfigured: Bool
  var credentialConfigured: Bool
  var pricing: ProviderPricingProfile
  var performance: ProviderPerformanceProfile
  var schemaVersion: Int
  var metadata: [String: String]

  var id: String { profileId }

  init(
    profileId: String,
    resourceId: String,
    providerId: String,
    productId: String,
    displayName: String,
    kind: ProviderProfileKind,
    location: AgentResourceLocation,
    status: AgentConnectorStatus,
    protocolFamily: String,
    adapterType: String,
    modelId: String = "",
    capabilities: Set<AgentCapability> = [],
    toolIds: Set<String> = [],
    contextWindowTokens: Int = 8_192,
    maxOutputTokens: Int = 4_096,
    maxParallelRuns: Int = 1,
    supportsTools: Bool = false,
    supportsStreaming: Bool = false,
    supportsBackground: Bool = false,
    latency: AgentResourceLatency = .normal,
    quality: AgentResourceQuality = .standard,
    trust: AgentResourceTrust = .unknown,
    failureDomain: String = "",
    endpointConfigured: Bool = false,
    credentialConfigured: Bool = false,
    pricing: ProviderPricingProfile = ProviderPricingProfile(tier: .free),
    performance: ProviderPerformanceProfile = ProviderPerformanceProfile(),
    schemaVersion: Int = ProviderProfile.schemaVersion,
    metadata: [String: String] = [:]
  ) {
    self.profileId = profileId
    self.resourceId = resourceId
    self.providerId = providerId
    self.productId = productId
    self.displayName = displayName
    self.kind = kind
    self.location = location
    self.status = status
    self.protocolFamily = protocolFamily
    self.adapterType = adapterType
    self.modelId = modelId
    self.capabilities = capabilities
    self.toolIds = toolIds
    self.contextWindowTokens = max(0, contextWindowTokens)
    self.maxOutputTokens = max(0, maxOutputTokens)
    self.maxParallelRuns = max(1, maxParallelRuns)
    self.supportsTools = supportsTools
    self.supportsStreaming = supportsStreaming
    self.supportsBackground = supportsBackground
    self.latency = latency
    self.quality = quality
    self.trust = trust
    self.failureDomain = failureDomain
    self.endpointConfigured = endpointConfigured
    self.credentialConfigured = credentialConfigured
    self.pricing = pricing
    self.performance = performance
    self.schemaVersion = schemaVersion
    self.metadata = metadata
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case profileId = "profile_id"
    case resourceId = "resource_id"
    case providerId = "provider_id"
    case productId = "product_id"
    case displayName = "display_name"
    case kind
    case location
    case status
    case protocolFamily = "protocol_family"
    case adapterType = "adapter_type"
    case modelId = "model_id"
    case capabilities
    case toolIds = "tool_ids"
    case contextWindowTokens = "context_window_tokens"
    case maxOutputTokens = "max_output_tokens"
    case maxParallelRuns = "max_parallel_runs"
    case supportsTools = "supports_tools"
    case supportsStreaming = "supports_streaming"
    case supportsBackground = "supports_background"
    case latency = "latency_tier"
    case quality = "quality_tier"
    case trust
    case failureDomain = "failure_domain"
    case endpointConfigured = "endpoint_configured"
    case credentialConfigured = "credential_configured"
    case pricing
    case performance
    case metadata
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let schema = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
    guard schema == Self.schemaVersion else {
      throw DecodingError.dataCorruptedError(
        forKey: .schemaVersion,
        in: container,
        debugDescription: "Unsupported provider profile schema"
      )
    }
    self.init(
      profileId: try container.decodeIfPresent(String.self, forKey: .profileId) ?? "",
      resourceId: try container.decodeIfPresent(String.self, forKey: .resourceId) ?? "",
      providerId: try container.decodeIfPresent(String.self, forKey: .providerId) ?? "",
      productId: try container.decodeIfPresent(String.self, forKey: .productId) ?? "",
      displayName: try container.decodeIfPresent(String.self, forKey: .displayName) ?? "",
      kind: ProviderProfileCatalog.kind(
        try container.decodeIfPresent(String.self, forKey: .kind),
        fallback: .agent
      ),
      location: AgentResourceLocation.fromWireValue(try container.decodeIfPresent(String.self, forKey: .location)),
      status: ProviderProfileCatalog.connectorStatus(try container.decodeIfPresent(String.self, forKey: .status)),
      protocolFamily: try container.decodeIfPresent(String.self, forKey: .protocolFamily) ?? "",
      adapterType: try container.decodeIfPresent(String.self, forKey: .adapterType) ?? "",
      modelId: try container.decodeIfPresent(String.self, forKey: .modelId) ?? "",
      capabilities: ProviderProfileCatalog.capabilities(
        try container.decodeIfPresent([String].self, forKey: .capabilities)
      ),
      toolIds: Set(try container.decodeIfPresent([String].self, forKey: .toolIds) ?? []),
      contextWindowTokens: try container.decodeIfPresent(Int.self, forKey: .contextWindowTokens) ?? 8_192,
      maxOutputTokens: try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens) ?? 4_096,
      maxParallelRuns: try container.decodeIfPresent(Int.self, forKey: .maxParallelRuns) ?? 1,
      supportsTools: try container.decodeIfPresent(Bool.self, forKey: .supportsTools) ?? false,
      supportsStreaming: try container.decodeIfPresent(Bool.self, forKey: .supportsStreaming) ?? false,
      supportsBackground: try container.decodeIfPresent(Bool.self, forKey: .supportsBackground) ?? false,
      latency: ProviderProfileCatalog.latency(
        try container.decodeIfPresent(String.self, forKey: .latency),
        fallback: .normal
      ),
      quality: ProviderProfileCatalog.quality(
        try container.decodeIfPresent(String.self, forKey: .quality),
        fallback: .standard
      ),
      trust: ProviderProfileCatalog.trust(
        try container.decodeIfPresent(String.self, forKey: .trust),
        fallback: .unknown
      ),
      failureDomain: try container.decodeIfPresent(String.self, forKey: .failureDomain) ?? "",
      endpointConfigured: try container.decodeIfPresent(Bool.self, forKey: .endpointConfigured) ?? false,
      credentialConfigured: try container.decodeIfPresent(Bool.self, forKey: .credentialConfigured) ?? false,
      pricing: try container.decodeIfPresent(ProviderPricingProfile.self, forKey: .pricing) ??
        ProviderPricingProfile(tier: .free),
      performance: try container.decodeIfPresent(ProviderPerformanceProfile.self, forKey: .performance) ??
        ProviderPerformanceProfile(),
      schemaVersion: schema,
      metadata: try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(profileId, forKey: .profileId)
    try container.encode(resourceId, forKey: .resourceId)
    try container.encode(providerId, forKey: .providerId)
    try container.encode(productId, forKey: .productId)
    try container.encode(displayName, forKey: .displayName)
    try container.encode(kind.rawValue.lowercased(), forKey: .kind)
    try container.encode(location.rawValue.lowercased(), forKey: .location)
    try container.encode(status.rawValue.lowercased(), forKey: .status)
    try container.encode(protocolFamily, forKey: .protocolFamily)
    try container.encode(adapterType, forKey: .adapterType)
    try container.encode(modelId, forKey: .modelId)
    try container.encode(capabilities.map(\.wireValue).sorted(), forKey: .capabilities)
    try container.encode(toolIds.sorted(), forKey: .toolIds)
    try container.encode(contextWindowTokens, forKey: .contextWindowTokens)
    try container.encode(maxOutputTokens, forKey: .maxOutputTokens)
    try container.encode(maxParallelRuns, forKey: .maxParallelRuns)
    try container.encode(supportsTools, forKey: .supportsTools)
    try container.encode(supportsStreaming, forKey: .supportsStreaming)
    try container.encode(supportsBackground, forKey: .supportsBackground)
    try container.encode(latency.rawValue.lowercased(), forKey: .latency)
    try container.encode(quality.rawValue.lowercased(), forKey: .quality)
    try container.encode(trust.rawValue.lowercased(), forKey: .trust)
    try container.encode(failureDomain, forKey: .failureDomain)
    try container.encode(endpointConfigured, forKey: .endpointConfigured)
    try container.encode(credentialConfigured, forKey: .credentialConfigured)
    try container.encode(pricing, forKey: .pricing)
    try container.encode(performance, forKey: .performance)
    try container.encode(metadata, forKey: .metadata)
  }
}

struct ModelProviderProfileDefinition: Equatable, Identifiable {
  var providerId: String
  var displayName: String
  var protocolFamily: String
  var location: AgentResourceLocation
  var cost: AgentResourceCost
  var latency: AgentResourceLatency
  var quality: AgentResourceQuality
  var contextWindowTokens: Int
  var supportsTools: Bool
  var supportsStreaming: Bool

  var id: String { providerId }
}
