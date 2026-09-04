import Foundation

enum AgentNoReplyReason: String, Codable, CaseIterable, Identifiable {
  case networkUnavailable = "NETWORK_UNAVAILABLE"
  case desktopOffline = "DESKTOP_OFFLINE"
  case desktopAgentStartFailed = "DESKTOP_AGENT_START_FAILED"
  case agentBusy = "AGENT_BUSY"
  case permissionWaiting = "PERMISSION_WAITING"
  case authenticationRequired = "AUTHENTICATION_REQUIRED"
  case configurationRequired = "CONFIGURATION_REQUIRED"
  case toolUnavailable = "TOOL_UNAVAILABLE"
  case agentUnavailable = "AGENT_UNAVAILABLE"
  case timedOut = "TIMED_OUT"
  case invalidRequest = "INVALID_REQUEST"
  case unknown = "UNKNOWN"

  var id: String { rawValue }
}

struct AgentNoReplySignal: Codable, Equatable {
  var taskStatus: String
  var error: String
  var currentStep: String
  var routeKind: AgentRouteKind
  var routeStatus: AgentConnectorStatus
  var endpointStatus: AgentEndpointStatus?
  var networkRequired: Bool
  var networkAvailable: Bool

  init(
    taskStatus: String = "",
    error: String = "",
    currentStep: String = "",
    routeKind: AgentRouteKind = .unknown,
    routeStatus: AgentConnectorStatus = .available,
    endpointStatus: AgentEndpointStatus? = nil,
    networkRequired: Bool = true,
    networkAvailable: Bool = true
  ) {
    self.taskStatus = taskStatus
    self.error = error
    self.currentStep = currentStep
    self.routeKind = routeKind
    self.routeStatus = routeStatus
    self.endpointStatus = endpointStatus
    self.networkRequired = networkRequired
    self.networkAvailable = networkAvailable
  }

  enum CodingKeys: String, CodingKey {
    case taskStatus = "task_status"
    case error
    case currentStep = "current_step"
    case routeKind = "route_kind"
    case routeStatus = "route_status"
    case endpointStatus = "endpoint_status"
    case networkRequired = "network_required"
    case networkAvailable = "network_available"
  }
}

struct AgentNoReplyDisplay: Codable, Equatable {
  var reason: AgentNoReplyReason
  var title: String
  var message: String
}

enum AgentNoReplyReasonPolicy {
  static func classify(_ signal: AgentNoReplySignal) -> AgentNoReplyReason {
    let status = normalize(signal.taskStatus)
    let details = normalize([status, signal.error, signal.currentStep].joined(separator: " "))

    if status == "waiting_approval" ||
      signal.endpointStatus == .permissionRequired ||
      containsAny(
        details,
        "waiting for approval",
        "waiting for permission",
        "permission required",
        "approval required",
        "needs permission",
        "\u{7b49}\u{5f85}\u{6388}\u{6743}",
        "\u{9700}\u{8981}\u{6388}\u{6743}",
        "\u{7b49}\u{5f85}\u{6279}\u{51c6}"
      ) {
      return .permissionWaiting
    }

    if (signal.networkRequired && !signal.networkAvailable) ||
      containsAny(
        details,
        "network unavailable",
        "network is offline",
        "no network",
        "mqtt disconnected",
        "network disconnected",
        "\u{7f51}\u{7edc}\u{4e0d}\u{53ef}\u{7528}",
        "\u{624b}\u{673a}\u{65e0}\u{7f51}\u{7edc}"
      ) {
      return .networkUnavailable
    }

    if signal.routeKind == .desktopAgent &&
      (signal.routeStatus == .disconnected ||
        endpointStatus(signal.endpointStatus, isAnyOf: [.offline, .unreachable]) ||
        containsAny(
          details,
          "desktop offline",
          "desktop disconnected",
          "gateway offline",
          "desktop unreachable",
          "\u{7535}\u{8111}\u{79bb}\u{7ebf}",
          "\u{684c}\u{9762}\u{7aef}\u{79bb}\u{7ebf}"
        )) {
      return .desktopOffline
    }

    if signal.routeKind == .desktopAgent &&
      signal.routeStatus == .available &&
      !endpointStatus(signal.endpointStatus, isAnyOf: [.offline, .unreachable]) &&
      (status == "start_failed" ||
        containsAny(
          details,
          "could not start",
          "failed to start",
          "launch failed",
          "process exited during startup",
          "startup failed",
          "\u{542f}\u{52a8}\u{5931}\u{8d25}",
          "\u{65e0}\u{6cd5}\u{542f}\u{52a8}",
          "\u{672a}\u{80fd}\u{542f}\u{52a8}"
        )) {
      return .desktopAgentStartFailed
    }

    if signal.endpointStatus == .busy ||
      containsAny(
        details,
        "agent busy",
        "provider busy",
        "capacity exhausted",
        "queue is full",
        "worker pool is full",
        "\u{667a}\u{80fd}\u{4f53}\u{5fd9}",
        "\u{961f}\u{5217}\u{5df2}\u{6ee1}"
      ) {
      return .agentBusy
    }

    if containsAny(
      details,
      "unauthorized",
      "authentication failed",
      "invalid api key",
      "invalid token",
      "token expired",
      "credentials expired",
      "http 401",
      "http 403",
      "\u{8ba4}\u{8bc1}\u{5931}\u{8d25}",
      "\u{5bc6}\u{94a5}\u{65e0}\u{6548}",
      "\u{4ee4}\u{724c}\u{8fc7}\u{671f}",
      "\u{767b}\u{5f55}\u{5df2}\u{8fc7}\u{671f}"
    ) {
      return .authenticationRequired
    }

    if signal.routeStatus == .needsSetup ||
      containsAny(
        details,
        "not configured",
        "missing api key",
        "missing credentials",
        "setup required",
        "needs setup",
        "\u{672a}\u{914d}\u{7f6e}",
        "\u{7f3a}\u{5c11}\u{5bc6}\u{94a5}",
        "\u{9700}\u{8981}\u{914d}\u{7f6e}"
      ) {
      return .configurationRequired
    }

    if containsAny(
      details,
      "command not found",
      "executable not found",
      "tool unavailable",
      "runtime pack missing",
      "dependency missing",
      "no such executable",
      "\u{547d}\u{4ee4}\u{4e0d}\u{5b58}\u{5728}",
      "\u{5de5}\u{5177}\u{4e0d}\u{53ef}\u{7528}",
      "\u{7f3a}\u{5c11}\u{8fd0}\u{884c}\u{5305}",
      "\u{7f3a}\u{5c11}\u{4f9d}\u{8d56}"
    ) {
      return .toolUnavailable
    }

    if signal.routeStatus == .disconnected ||
      endpointStatus(signal.endpointStatus, isAnyOf: [.offline, .unreachable]) ||
      containsAny(
        details,
        "agent unavailable",
        "provider unavailable",
        "not installed",
        "not configured",
        "could not start",
        "failed to start",
        "not found",
        "\u{667a}\u{80fd}\u{4f53}\u{4e0d}\u{53ef}\u{7528}",
        "\u{672a}\u{5b89}\u{88c5}",
        "\u{65e0}\u{6cd5}\u{4f7f}\u{7528}"
      ) {
      return .agentUnavailable
    }

    if status == "timed_out" ||
      containsAny(details, "timed out", "timeout", "\u{8d85}\u{65f6}") {
      return .timedOut
    }

    if ["invalid", "invalid_request", "unsupported"].contains(status) ||
      containsAny(
        details,
        "invalid request",
        "invalid input",
        "unsupported file",
        "unsupported format",
        "malformed",
        "\u{8bf7}\u{6c42}\u{65e0}\u{6548}",
        "\u{8f93}\u{5165}\u{65e0}\u{6548}",
        "\u{683c}\u{5f0f}\u{4e0d}\u{652f}\u{6301}",
        "\u{6587}\u{4ef6}\u{4e0d}\u{652f}\u{6301}"
      ) {
      return .invalidRequest
    }

    return .unknown
  }

  static func display(
    for signal: AgentNoReplySignal,
    chinese: Bool = false
  ) -> AgentNoReplyDisplay {
    display(for: classify(signal), chinese: chinese)
  }

  static func display(
    for reason: AgentNoReplyReason,
    chinese: Bool = false
  ) -> AgentNoReplyDisplay {
    let text = displayText[reason] ?? displayText[.unknown]!
    let language = chinese ? LanguagePolicySettings.zhCN : LanguagePolicySettings.enUS
    let key = reason.rawValue.lowercased()
    return AgentNoReplyDisplay(
      reason: reason,
      title: GalaxySSILocalization.string(
        "agent_no_reply.\(key).title",
        fallback: text.title,
        language: language
      ),
      message: GalaxySSILocalization.string(
        "agent_no_reply.\(key).message",
        fallback: text.message,
        language: language
      )
    )
  }

  private static func normalize(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static func containsAny(_ value: String, _ candidates: String...) -> Bool {
    candidates.contains { value.contains($0) }
  }

  private static func endpointStatus(
    _ value: AgentEndpointStatus?,
    isAnyOf candidates: Set<AgentEndpointStatus>
  ) -> Bool {
    guard let value else { return false }
    return candidates.contains(value)
  }

  private static let displayText: [AgentNoReplyReason: (title: String, message: String)] = [
    .networkUnavailable: (
      "Network unavailable",
      "GalaxySSI could not reach the route because this phone is offline."
    ),
    .desktopOffline: (
      "Desktop offline",
      "The desktop route is disconnected or unreachable."
    ),
    .desktopAgentStartFailed: (
      "Desktop agent did not start",
      "The desktop was reachable, but the agent process failed during startup."
    ),
    .agentBusy: (
      "Agent busy",
      "The selected agent is at capacity or still handling another task."
    ),
    .permissionWaiting: (
      "Waiting for permission",
      "The task is paused until the required approval or permission is granted."
    ),
    .authenticationRequired: (
      "Authentication required",
      "Saved credentials are missing, invalid, expired, or rejected."
    ),
    .configurationRequired: (
      "Configuration required",
      "The selected route needs setup before it can respond."
    ),
    .toolUnavailable: (
      "Tool unavailable",
      "A required executable, runtime pack, or dependency is missing."
    ),
    .agentUnavailable: (
      "Agent unavailable",
      "The selected provider could not be reached or started."
    ),
    .timedOut: (
      "Timed out",
      "The task did not finish before its response window closed."
    ),
    .invalidRequest: (
      "Invalid request",
      "The request or one of its inputs is unsupported or malformed."
    ),
    .unknown: (
      "No reply",
      "GalaxySSI did not receive a usable response for this turn."
    )
  ]

}
