import Foundation

enum AgentAvatarStyle: String, Codable, CaseIterable, Identifiable {
  case codex = "CODEX"
  case claude = "CLAUDE"
  case hermes = "HERMES"
  case openclaw = "OPENCLAW"
  case localModel = "LOCAL_MODEL"
  case cloudModel = "CLOUD_MODEL"
  case device = "DEVICE"
  case generic = "GENERIC"

  var id: String { rawValue }

  var androidParityAssetName: String? {
    switch self {
    case .codex:
      return "CodexLogo"
    case .claude:
      return "ClaudeLogo"
    case .hermes:
      return "HermesLogo"
    case .openclaw, .localModel, .cloudModel, .device, .generic:
      return nil
    }
  }
}

enum SignalASIAgentAvatarAssetCatalog {
  static func assetName(for fields: [String]) -> String? {
    let identity = fields
      .joined(separator: " ")
      .lowercased()

    if identity.contains("codex") {
      return AgentAvatarStyle.codex.androidParityAssetName
    }
    if identity.contains("claude") || identity.contains("anthropic") {
      return AgentAvatarStyle.claude.androidParityAssetName
    }
    if identity.contains("gemini") || identity.contains("google-gemini") {
      return "CloudProviderGemini"
    }
    if identity.contains("hermes") {
      return AgentAvatarStyle.hermes.androidParityAssetName
    }
    return nil
  }

  static func cloudProviderAssetName(for fields: [String]) -> String? {
    let identity = fields
      .joined(separator: " ")
      .lowercased()

    // Keep provider matching ahead of generic model-name matching so an
    // OpenRouter GPT contact still uses the OpenRouter brand mark.
    if identity.contains("openrouter") || identity.contains("open-router") {
      return "CloudProviderOpenRouter"
    }
    if identity.contains("deepseek") {
      return "CloudProviderDeepSeek"
    }
    if identity.contains("qwen") {
      return "CloudProviderQwen"
    }
    if identity.contains("gemini") || identity.contains("google") {
      return "CloudProviderGemini"
    }
    if identity.contains("anthropic") || identity.contains("claude") {
      return "CloudProviderAnthropic"
    }
    if identity.contains("openai") || identity.contains("gpt") {
      return "CloudProviderOpenAI"
    }
    return nil
  }
}

struct AgentIdentityPresentation: Codable, Equatable, Identifiable {
  var agentId: String
  var displayName: String
  var avatarStyle: AgentAvatarStyle
  var status: AgentEndpointStatus
  var capabilities: [AgentCapability]
  var cost: AgentResourceCost
  var latency: AgentResourceLatency
  var location: AgentResourceLocation

  var id: String { agentId }
}

enum AgentIdentityPresenter {
  static func present(_ registration: AgentRegistration) -> AgentIdentityPresentation {
    let effectiveStatus: AgentEndpointStatus
    if !registration.hasCapacity && [.online, .idle].contains(registration.status) {
      effectiveStatus = .busy
    } else {
      effectiveStatus = registration.status
    }
    return AgentIdentityPresentation(
      agentId: registration.agentId,
      displayName: registration.displayName,
      avatarStyle: avatarStyle(for: registration),
      status: effectiveStatus,
      capabilities: sortedCapabilities(registration.capabilities),
      cost: registration.cost,
      latency: registration.latency,
      location: registration.location
    )
  }

  private static func sortedCapabilities(_ capabilities: Set<AgentCapability>) -> [AgentCapability] {
    capabilities.sorted { lhs, rhs in
      let lhsPriority = capabilityPriority[lhs] ?? Int.max
      let rhsPriority = capabilityPriority[rhs] ?? Int.max
      if lhsPriority == rhsPriority {
        return lhs.rawValue < rhs.rawValue
      }
      return lhsPriority < rhsPriority
    }
  }

  private static func avatarStyle(for registration: AgentRegistration) -> AgentAvatarStyle {
    let identity = [
      registration.agentId,
      registration.providerId,
      registration.displayName,
      registration.adapterType
    ]
      .joined(separator: " ")
      .lowercased()

    if identity.contains("codex") {
      return .codex
    }
    if identity.contains("claude") || identity.contains("anthropic") {
      return .claude
    }
    if identity.contains("hermes") {
      return .hermes
    }
    if identity.contains("openclaw") {
      return .openclaw
    }
    if registration.kind == .device {
      return .device
    }
    if registration.kind == .model && registration.location == .phone {
      return .localModel
    }
    if registration.kind == .model {
      return .cloudModel
    }
    return .generic
  }

  private static let capabilityPriority: [AgentCapability: Int] = {
    var priorities: [AgentCapability: Int] = [:]
    for (index, capability) in orderedCapabilities.enumerated() {
      priorities[capability] = index
    }
    return priorities
  }()

  private static let orderedCapabilities: [AgentCapability] = [
    .code,
    .reasoning,
    .research,
    .liveData,
    .taskExecution,
    .toolUse,
    .mcp,
    .skill,
    .localInference,
    .knowledgeSearch,
    .deviceControl,
    .smartHome,
    .chat,
    .screenReading,
    .appNavigation,
    .systemSettings,
    .clipboard,
    .alarm
  ]
}
