import Foundation

enum ProviderProfileCatalog {
  static let modelProviders: [ModelProviderProfileDefinition] = [
    ModelProviderProfileDefinition(
      providerId: "openai",
      displayName: "OpenAI",
      protocolFamily: "openai",
      location: .cloud,
      cost: .medium,
      latency: .normal,
      quality: .frontier,
      contextWindowTokens: 128_000,
      supportsTools: true,
      supportsStreaming: true
    ),
    ModelProviderProfileDefinition(
      providerId: "anthropic",
      displayName: "Claude",
      protocolFamily: "anthropic",
      location: .cloud,
      cost: .medium,
      latency: .normal,
      quality: .frontier,
      contextWindowTokens: 200_000,
      supportsTools: true,
      supportsStreaming: true
    ),
    ModelProviderProfileDefinition(
      providerId: "gemini",
      displayName: "Gemini",
      protocolFamily: "gemini",
      location: .cloud,
      cost: .medium,
      latency: .fast,
      quality: .frontier,
      contextWindowTokens: 1_000_000,
      supportsTools: true,
      supportsStreaming: true
    ),
    ModelProviderProfileDefinition(
      providerId: "deepseek",
      displayName: "DeepSeek",
      protocolFamily: "openai",
      location: .cloud,
      cost: .low,
      latency: .normal,
      quality: .frontier,
      contextWindowTokens: 128_000,
      supportsTools: true,
      supportsStreaming: true
    ),
    ModelProviderProfileDefinition(
      providerId: "qwen",
      displayName: "Qwen",
      protocolFamily: "openai",
      location: .cloud,
      cost: .low,
      latency: .normal,
      quality: .strong,
      contextWindowTokens: 131_072,
      supportsTools: true,
      supportsStreaming: true
    ),
    ModelProviderProfileDefinition(
      providerId: "ollama",
      displayName: "Ollama",
      protocolFamily: "ollama",
      location: .privateNetwork,
      cost: .free,
      latency: .fast,
      quality: .standard,
      contextWindowTokens: 32_768,
      supportsTools: false,
      supportsStreaming: true
    ),
    ModelProviderProfileDefinition(
      providerId: "lm-studio",
      displayName: "LM Studio",
      protocolFamily: "openai",
      location: .privateNetwork,
      cost: .free,
      latency: .fast,
      quality: .standard,
      contextWindowTokens: 32_768,
      supportsTools: false,
      supportsStreaming: true
    ),
    ModelProviderProfileDefinition(
      providerId: "openrouter",
      displayName: "OpenRouter",
      protocolFamily: "openai",
      location: .cloud,
      cost: .medium,
      latency: .normal,
      quality: .frontier,
      contextWindowTokens: 128_000,
      supportsTools: true,
      supportsStreaming: true
    )
  ]

  static func fromCloudContact(
    _ contact: GalaxySSIContact,
    apiKey: String? = nil,
    status: AgentConnectorStatus = .available,
    performance: ProviderPerformanceProfile = ProviderPerformanceProfile()
  ) -> ProviderProfile {
    let model = contact.selectedCloudModel ?? CloudModelConfig(
      id: contact.id,
      displayName: contact.cloudProvider,
      provider: contact.cloudProvider,
      modelId: "",
      endpoint: "",
      apiStyle: .openAICompatible,
      keychainAccount: "",
      updatedAt: Date(timeIntervalSince1970: 0)
    )
    return fromCloudModel(
      resourceId: contact.id,
      provider: contact.cloudProvider,
      displayName: contact.cloudProvider.isEmpty ? contact.name : contact.cloudProvider,
      model: model,
      apiKey: apiKey,
      status: status,
      performance: performance
    )
  }

  static func fromCloudModel(
    resourceId: String,
    provider: String,
    displayName: String = "",
    model: CloudModelConfig,
    apiKey: String? = nil,
    status: AgentConnectorStatus = .available,
    performance: ProviderPerformanceProfile = ProviderPerformanceProfile()
  ) -> ProviderProfile {
    let providerId = normalizeProviderId(provider.isEmpty ? model.provider : provider)
    let definition = definition(providerId)
    let endpoint = model.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    let local = isLocalEndpoint(endpoint) || definition.location == .privateNetwork
    var capabilities: Set<AgentCapability> = [.chat, .reasoning]
    if definition.supportsTools {
      capabilities.formUnion([.toolUse, .liveData])
    }
    if local {
      capabilities.insert(.localInference)
    }
    let profileName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? definition.displayName
      : displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let protocolFamily = model.apiStyle.rawValue.isEmpty ? definition.protocolFamily : model.apiStyle.rawValue
    return ProviderProfile(
      profileId: "model:\(providerId)",
      resourceId: resourceId.isEmpty ? "cloud:\(providerId)" : resourceId,
      providerId: providerId,
      productId: providerId,
      displayName: profileName,
      kind: local ? .localModel : .cloudModel,
      location: local ? .privateNetwork : definition.location,
      status: status,
      protocolFamily: protocolFamily,
      adapterType: "\(definition.protocolFamily)-model-api",
      modelId: model.modelId,
      capabilities: capabilities,
      contextWindowTokens: max(4_096, contextWindowTokens(for: model, fallback: definition.contextWindowTokens)),
      maxOutputTokens: max(512, maxOutputTokens(for: model)),
      maxParallelRuns: local ? 2 : 4,
      supportsTools: definition.supportsTools,
      supportsStreaming: definition.supportsStreaming,
      supportsBackground: true,
      latency: definition.latency,
      quality: definition.quality,
      trust: local ? .privateConfigured : .cloudConfigured,
      failureDomain: local ? "private-model:\(providerId)" : "cloud-model:\(providerId)",
      endpointConfigured: !endpoint.isEmpty,
      credentialConfigured: local || CloudModelCredentialPolicy.isStoredCredential(apiKey),
      pricing: ProviderPricingProfile(tier: definition.cost),
      performance: performance,
      metadata: ["native_product_identity": providerId]
    )
  }

  static func fromRegistration(
    _ registration: AgentRegistration,
    existing: ProviderProfile? = nil
  ) -> ProviderProfile {
    let base = existing ?? registration.providerProfile ?? agentProfile(
      resourceId: registration.agentId,
      displayName: registration.displayName,
      providerId: registration.providerId.isEmpty ? registration.agentId : registration.providerId,
      adapterType: registration.adapterType,
      location: registration.location,
      status: registration.status.toConnectorStatus(),
      capabilities: registration.capabilities,
      toolIds: registration.toolIds,
      cost: registration.cost,
      latency: registration.latency,
      trust: registration.trust,
      failureDomain: registration.failureDomain,
      maxParallelRuns: registration.maxParallelRuns
    )
    return ProviderProfile(
      profileId: base.profileId,
      resourceId: registration.agentId,
      providerId: registration.providerId.isEmpty ? base.providerId : registration.providerId,
      productId: base.productId,
      displayName: registration.displayName,
      kind: .agent,
      location: registration.location,
      status: registration.status.toConnectorStatus(),
      protocolFamily: base.protocolFamily,
      adapterType: registration.adapterType.isEmpty ? base.adapterType : registration.adapterType,
      modelId: base.modelId,
      capabilities: registration.capabilities,
      toolIds: registration.toolIds,
      contextWindowTokens: base.contextWindowTokens,
      maxOutputTokens: base.maxOutputTokens,
      maxParallelRuns: max(1, registration.maxParallelRuns),
      supportsTools: base.supportsTools,
      supportsStreaming: base.supportsStreaming,
      supportsBackground: base.supportsBackground,
      latency: registration.latency,
      quality: base.quality,
      trust: registration.trust,
      failureDomain: registration.failureDomain.isEmpty ? base.failureDomain : registration.failureDomain,
      endpointConfigured: true,
      credentialConfigured: true,
      pricing: ProviderPricingProfile(
        tier: registration.cost,
        inputMicrosPerMillionTokens: base.pricing.inputMicrosPerMillionTokens,
        outputMicrosPerMillionTokens: base.pricing.outputMicrosPerMillionTokens,
        currency: base.pricing.currency,
        source: base.pricing.source
      ),
      performance: base.performance,
      metadata: base.metadata
    )
  }

  static func fromTarget(_ target: AgentCallableTarget) -> ProviderProfile {
    if let providerProfile = target.providerProfile {
      return providerProfile
    }
    if target.kind == .model {
      let providerId = providerIdForTarget(target)
      let definition = definition(providerId)
      let local = target.capabilities.contains(.localInference) || definition.location == .privateNetwork
      return ProviderProfile(
        profileId: "model:\(providerId)",
        resourceId: target.id,
        providerId: providerId,
        productId: providerId,
        displayName: target.title,
        kind: local ? .localModel : .cloudModel,
        location: local ? .privateNetwork : definition.location,
        status: target.status,
        protocolFamily: definition.protocolFamily,
        adapterType: target.adapterType.isEmpty ? "model-api" : target.adapterType,
        capabilities: Set(target.capabilities),
        contextWindowTokens: definition.contextWindowTokens,
        maxOutputTokens: 4_096,
        maxParallelRuns: local ? 2 : 4,
        supportsTools: definition.supportsTools,
        supportsStreaming: definition.supportsStreaming,
        supportsBackground: true,
        latency: definition.latency,
        quality: definition.quality,
        trust: local ? .privateConfigured : .cloudConfigured,
        failureDomain: target.failureDomain.isEmpty ? "model:\(providerId)" : target.failureDomain,
        endpointConfigured: false,
        credentialConfigured: local,
        pricing: ProviderPricingProfile(tier: definition.cost),
        metadata: ["native_product_identity": providerId]
      )
    }
    return agentProfile(
      resourceId: target.id,
      displayName: target.title,
      providerId: providerIdForTarget(target),
      adapterType: target.adapterType,
      location: target.kind == .agent || target.failureDomain.hasPrefix("desktop") ? .trustedDesktop : .cloud,
      status: target.status,
      capabilities: Set(target.capabilities),
      failureDomain: target.failureDomain,
      maxParallelRuns: 1
    )
  }

  static func fromConnectorContact(
    _ contact: GalaxySSIContact,
    status: AgentConnectorStatus,
    capabilities: [AgentCapability],
    adapterType: String
  ) -> ProviderProfile {
    if let providerProfile = contact.connectorProviderProfile {
      return providerProfile
    }
    let agentId = contact.connectorAgentId.ifBlank(contact.id)
    let providerId = normalizeProviderId(agentId.ifBlank(contact.agentKind).ifBlank(contact.id))
    let protocolRange = contact.connectorProtocolRange
    var metadata = [
      "native_product_identity": providerId,
      "protocol_version": protocolRange.preferred,
      "protocol_min_version": protocolRange.minimum,
      "protocol_max_version": protocolRange.maximum
    ]
    if let capabilitiesHash = contact.connectorCapabilitiesHash?.trimmingCharacters(in: .whitespacesAndNewlines),
       !capabilitiesHash.isEmpty {
      metadata["capabilities_hash"] = capabilitiesHash
    }
    return agentProfile(
      resourceId: contact.id,
      displayName: contact.displayName.ifBlank(contact.name).ifBlank(contact.id),
      providerId: providerId,
      adapterType: adapterType,
      location: .trustedDesktop,
      status: status,
      capabilities: Set(capabilities),
      trust: contact.trustState == .verified ? .verifiedPaired : .unknown,
      failureDomain: contact.desktopId.isEmpty ? "agent:\(contact.id)" : "desktop:\(contact.desktopId)",
      maxParallelRuns: 1,
      metadata: metadata
    )
  }

  static func normalizeProviderId(_ value: String) -> String {
    let normalized = value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "_", with: "-")
      .replacingOccurrences(of: " ", with: "-")
    switch normalized {
    case "claude", "anthropic-claude":
      return "anthropic"
    case "google", "google-gemini":
      return "gemini"
    case "lmstudio":
      return "lm-studio"
    case "open-router":
      return "openrouter"
    case "dashscope":
      return "qwen"
    default:
      return normalized.isEmpty ? "custom" : normalized
    }
  }

  static func kind(_ value: String?, fallback: ProviderProfileKind) -> ProviderProfileKind {
    ProviderProfileKind.allCases.first { $0.rawValue == token(value) } ?? fallback
  }

  static func cost(_ value: String?, fallback: AgentResourceCost) -> AgentResourceCost {
    AgentResourceCost.allCases.first { $0.rawValue == token(value) } ?? fallback
  }

  static func latency(_ value: String?, fallback: AgentResourceLatency) -> AgentResourceLatency {
    AgentResourceLatency.allCases.first { $0.rawValue == token(value) } ?? fallback
  }

  static func quality(_ value: String?, fallback: AgentResourceQuality) -> AgentResourceQuality {
    AgentResourceQuality.allCases.first { $0.rawValue == token(value) } ?? fallback
  }

  static func trust(_ value: String?, fallback: AgentResourceTrust) -> AgentResourceTrust {
    AgentResourceTrust.allCases.first { $0.rawValue == token(value) } ?? fallback
  }

  static func capabilities(_ values: [String]?) -> Set<AgentCapability> {
    Set((values ?? []).compactMap(AgentCapability.fromWireValue))
  }

  static func connectorStatus(_ value: String?) -> AgentConnectorStatus {
    switch token(value) {
    case "READY", "CONFIGURED", "ONLINE", "AVAILABLE", "BUSY", "IDLE", "DEGRADED":
      return .available
    case "NEEDS_SETUP", "NOT_CONFIGURED", "PERMISSION_REQUIRED", "UPDATING":
      return .needsSetup
    default:
      return .disconnected
    }
  }

  private static func agentProfile(
    resourceId: String,
    displayName: String,
    providerId: String,
    adapterType: String,
    location: AgentResourceLocation,
    status: AgentConnectorStatus,
    capabilities: Set<AgentCapability>,
    toolIds: Set<String> = [],
    cost: AgentResourceCost = .free,
    latency: AgentResourceLatency = .normal,
    trust: AgentResourceTrust = .verifiedPaired,
    failureDomain: String,
    maxParallelRuns: Int,
    metadata: [String: String] = [:]
  ) -> ProviderProfile {
    let productId = normalizeProductId(resourceId)
    let mergedMetadata = ["native_product_identity": productId].merging(metadata) { _, new in new }
    return ProviderProfile(
      profileId: "agent:\(resourceId)",
      resourceId: resourceId,
      providerId: providerId.isEmpty ? productId : providerId,
      productId: productId,
      displayName: displayName,
      kind: .agent,
      location: location,
      status: status,
      protocolFamily: "galaxyssi-agent-adapter",
      adapterType: adapterType.isEmpty ? "\(productId)-native-adapter" : adapterType,
      capabilities: capabilities,
      toolIds: toolIds,
      contextWindowTokens: 64_000,
      maxOutputTokens: 16_000,
      maxParallelRuns: max(1, maxParallelRuns),
      supportsTools: !capabilities.isDisjoint(with: [.toolUse, .code, .taskExecution]),
      supportsStreaming: true,
      supportsBackground: capabilities.contains(.taskExecution),
      latency: latency,
      quality: .strong,
      trust: trust,
      failureDomain: failureDomain.isEmpty ? "agent:\(resourceId)" : failureDomain,
      endpointConfigured: true,
      credentialConfigured: true,
      pricing: ProviderPricingProfile(tier: cost),
      metadata: mergedMetadata
    )
  }

  private static func providerIdForTarget(_ target: AgentCallableTarget) -> String {
    let identity = "\(target.id) \(target.title)".lowercased()
    if identity.contains("openrouter") { return "openrouter" }
    if identity.contains("deepseek") { return "deepseek" }
    if identity.contains("qwen") { return "qwen" }
    if identity.contains("gemini") { return "gemini" }
    if identity.contains("claude") || identity.contains("anthropic") { return "anthropic" }
    if identity.contains("ollama") { return "ollama" }
    if identity.contains("lm studio") || identity.contains("lm-studio") { return "lm-studio" }
    if identity.contains("openai") || target.id == "cloud-models" { return "openai" }
    return normalizeProductId(target.id)
  }

  private static func normalizeProductId(_ resourceId: String) -> String {
    let id = resourceId
      .split(separator: ":")
      .last
      .map(String.init)?
      .lowercased() ?? resourceId.lowercased()
    return id == "claude-code" ? "claude" : id
  }

  private static func definition(_ providerId: String) -> ModelProviderProfileDefinition {
    modelProviders.first { $0.providerId == providerId } ?? ModelProviderProfileDefinition(
      providerId: providerId.isEmpty ? "custom" : providerId,
      displayName: providerId.isEmpty ? "Custom" : providerId,
      protocolFamily: "openai",
      location: .cloud,
      cost: .medium,
      latency: .normal,
      quality: .strong,
      contextWindowTokens: 64_000,
      supportsTools: true,
      supportsStreaming: true
    )
  }

  private static func isLocalEndpoint(_ endpoint: String) -> Bool {
    let value = endpoint.lowercased()
    return ["127.0.0.1", "localhost", "192.168.", "10.", "172.16."].contains { value.contains($0) }
  }

  private static func contextWindowTokens(for model: CloudModelConfig, fallback: Int) -> Int {
    let lower = model.modelId.lowercased()
    if lower.contains("gemini") { return max(fallback, 1_000_000) }
    if lower.contains("claude") { return max(fallback, 200_000) }
    if lower.contains("qwen") { return max(fallback, 131_072) }
    return fallback
  }

  private static func maxOutputTokens(for model: CloudModelConfig) -> Int {
    let lower = model.modelId.lowercased()
    if lower.contains("mini") || lower.contains("flash") { return 8_192 }
    return 4_096
  }

  private static func token(_ value: String?) -> String {
    value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
  }
}

private extension AgentEndpointStatus {
  func toConnectorStatus() -> AgentConnectorStatus {
    switch self {
    case .online, .idle, .busy:
      return .available
    case .permissionRequired, .updating:
      return .needsSetup
    case .offline, .degraded, .unreachable:
      return .disconnected
    }
  }
}
