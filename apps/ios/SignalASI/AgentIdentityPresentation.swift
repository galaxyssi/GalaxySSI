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
