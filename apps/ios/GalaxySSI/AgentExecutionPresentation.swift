import Foundation

enum AgentRouteKind: String, Codable, CaseIterable, Identifiable {
  case localSystem = "LOCAL_SYSTEM"
  case cloudModel = "CLOUD_MODEL"
  case localModel = "LOCAL_MODEL"
  case desktopAgent = "DESKTOP_AGENT"
  case deviceConnector = "DEVICE_CONNECTOR"
  case knowledge = "KNOWLEDGE"
  case unknown = "UNKNOWN"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentRouteKind {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
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

enum AgentExecutionLocationKind: String, Codable, CaseIterable, Identifiable {
  case phone = "PHONE"
  case desktop = "DESKTOP"
  case cloud = "CLOUD"
  case connectedDevice = "CONNECTED_DEVICE"
  case unknown = "UNKNOWN"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentExecutionLocationKind {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
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

enum AgentExecutionRuntimeKind: String, Codable, CaseIterable, Identifiable {
  case phoneNative = "PHONE_NATIVE"
  case phoneLinux = "PHONE_LINUX"
  case phoneLocalModel = "PHONE_LOCAL_MODEL"
  case phoneCloudAPI = "PHONE_CLOUD_API"
  case desktopAgent = "DESKTOP_AGENT"
  case desktopTool = "DESKTOP_TOOL"
  case connectedDevice = "CONNECTED_DEVICE"
  case knowledge = "KNOWLEDGE"
  case unknown = "UNKNOWN"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentExecutionRuntimeKind {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
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

struct AgentExecutionLocation: Codable, Equatable {
  var contract: String
  var locationKind: AgentExecutionLocationKind
  var runtimeKind: AgentExecutionRuntimeKind
  var locationId: String
  var locationName: String
  var runtimeId: String
  var trusted: Bool

  init(
    contract: String = AgentExecutionLocationContract.version,
    locationKind: AgentExecutionLocationKind,
    runtimeKind: AgentExecutionRuntimeKind,
    locationId: String = "",
    locationName: String = "",
    runtimeId: String = "",
    trusted: Bool = true
  ) {
    self.contract = contract
    self.locationKind = locationKind
    self.runtimeKind = runtimeKind
    self.locationId = locationId
    self.locationName = locationName
    self.runtimeId = runtimeId
    self.trusted = trusted
  }
}

enum AgentExecutionLocationContract {
  static let version = "galaxyssi.execution-location/1.0"
}

struct AgentExecutionPresentation: Codable, Equatable {
  var executorId: String
  var executorLabel: String
  var locationKind: AgentExecutionLocationKind
  var locationLabelHint: String
  var runtimeKind: AgentExecutionRuntimeKind
  var runtimeLabelHint: String
  var runtimeId: String
  var locationId: String
  var locationTrusted: Bool
  var currentStep: String
  var phase: AgentPhase
  var cancellable: Bool
  var startedAtMillis: Int64
  var completedAtMillis: Int64

  init(
    executorId: String,
    executorLabel: String,
    locationKind: AgentExecutionLocationKind,
    locationLabelHint: String,
    runtimeKind: AgentExecutionRuntimeKind = .unknown,
    runtimeLabelHint: String = "",
    runtimeId: String = "",
    locationId: String = "",
    locationTrusted: Bool = true,
    currentStep: String,
    phase: AgentPhase,
    cancellable: Bool,
    startedAtMillis: Int64,
    completedAtMillis: Int64 = 0
  ) {
    self.executorId = executorId
    self.executorLabel = executorLabel
    self.locationKind = locationKind
    self.locationLabelHint = locationLabelHint
    self.runtimeKind = runtimeKind
    self.runtimeLabelHint = runtimeLabelHint
    self.runtimeId = runtimeId
    self.locationId = locationId
    self.locationTrusted = locationTrusted
    self.currentStep = currentStep
    self.phase = phase
    self.cancellable = cancellable
    self.startedAtMillis = startedAtMillis
    self.completedAtMillis = completedAtMillis
  }

  enum CodingKeys: String, CodingKey {
    case executorId
    case executorLabel
    case locationKind
    case locationLabelHint
    case runtimeKind
    case runtimeLabelHint
    case runtimeId
    case locationId
    case locationTrusted
    case currentStep
    case phase
    case cancellable
    case startedAtMillis
    case completedAtMillis
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      executorId: try container.decodeIfPresent(String.self, forKey: .executorId) ?? "",
      executorLabel: try container.decodeIfPresent(String.self, forKey: .executorLabel) ?? "",
      locationKind: try container.decodeIfPresent(AgentExecutionLocationKind.self, forKey: .locationKind) ?? .unknown,
      locationLabelHint: try container.decodeIfPresent(String.self, forKey: .locationLabelHint) ?? "",
      runtimeKind: try container.decodeIfPresent(AgentExecutionRuntimeKind.self, forKey: .runtimeKind) ?? .unknown,
      runtimeLabelHint: try container.decodeIfPresent(String.self, forKey: .runtimeLabelHint) ?? "",
      runtimeId: try container.decodeIfPresent(String.self, forKey: .runtimeId) ?? "",
      locationId: try container.decodeIfPresent(String.self, forKey: .locationId) ?? "",
      locationTrusted: try container.decodeIfPresent(Bool.self, forKey: .locationTrusted) ?? true,
      currentStep: try container.decodeIfPresent(String.self, forKey: .currentStep) ?? "",
      phase: try container.decodeIfPresent(AgentPhase.self, forKey: .phase) ?? .executing,
      cancellable: try container.decodeIfPresent(Bool.self, forKey: .cancellable) ?? true,
      startedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .startedAtMillis) ?? 0,
      completedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .completedAtMillis) ?? 0
    )
  }
}

enum AgentExecutionPresentationPolicy {
  static func location(route: AgentRoute?, action: AgentAction? = nil) -> AgentExecutionLocation {
    let routeKind = route?.kind ?? .unknown
    let targetParts = targetParts(route?.targetTitle ?? "")
    let toolId = trim(action?.parameters["tool_id"] ?? "")
    let declaredLocation = route?.executionLocationKind == .unknown ? nil : route?.executionLocationKind
    let declaredRuntime = route?.executionRuntimeKind == .unknown ? nil : route?.executionRuntimeKind
    let locationKind = declaredLocation ?? inferredLocationKind(
      routeKind: routeKind,
      toolId: toolId,
      executionDeviceId: route?.executionDeviceId ?? ""
    )
    let runtimeKind = declaredRuntime ?? inferredRuntimeKind(
      routeKind: routeKind,
      locationKind: locationKind,
      toolId: toolId
    )
    return AgentExecutionLocation(
      locationKind: locationKind,
      runtimeKind: runtimeKind,
      locationId: route?.executionDeviceId ?? "",
      locationName: firstNonBlank(
        route?.executionDeviceName ?? "",
        locationKind == .desktop ? targetParts.dropFirst().first ?? "" : ""
      ),
      runtimeId: firstNonBlank(toolId, route?.targetId ?? ""),
      trusted: true
    )
  }

  static func location(record: AgentTaskRecord) -> AgentExecutionLocation {
    if record.executionLocationKind != .unknown || record.executionRuntimeKind != .unknown {
      return AgentExecutionLocation(
        locationKind: record.executionLocationKind,
        runtimeKind: record.executionRuntimeKind,
        locationId: record.executionLocationId,
        locationName: record.executionLocationName,
        runtimeId: record.executionRuntimeId,
        trusted: record.executionLocationTrusted
      )
    }
    return location(
      route: AgentRoute(
        kind: record.routeKind,
        targetTitle: record.targetTitle
      )
    )
  }

  static func local(
    route: AgentRoute,
    action: AgentAction?,
    selectedAgentOrModel: String,
    phase: AgentPhase,
    currentStep: String,
    startedAtMillis: Int64,
    completedAtMillis: Int64 = 0
  ) -> AgentExecutionPresentation {
    local(
      routeKind: route.kind,
      targetTitle: route.targetTitle,
      selectedAgentOrModel: selectedAgentOrModel,
      phase: phase,
      currentStep: currentStep,
      startedAtMillis: startedAtMillis,
      completedAtMillis: completedAtMillis,
      resolvedLocation: location(route: route, action: action)
    )
  }

  static func local(
    routeKind: AgentRouteKind,
    targetTitle: String,
    selectedAgentOrModel: String,
    phase: AgentPhase,
    currentStep: String,
    startedAtMillis: Int64,
    completedAtMillis: Int64 = 0,
    resolvedLocation: AgentExecutionLocation? = nil
  ) -> AgentExecutionPresentation {
    let targetTitle = trim(targetTitle)
    let fallbackTarget = trim(selectedAgentOrModel)
    let target = targetTitle.isEmpty ? fallbackTarget : targetTitle
    let targetParts = targetParts(target)
    let firstTarget = targetParts.first ?? ""
    let locationKind: AgentExecutionLocationKind
    switch routeKind {
    case .cloudModel:
      locationKind = .phone
    case .desktopAgent:
      locationKind = .desktop
    case .deviceConnector:
      locationKind = .connectedDevice
    case .localSystem, .localModel, .knowledge:
      locationKind = .phone
    case .unknown:
      locationKind = .unknown
    }
    let executor: String
    switch routeKind {
    case .localSystem, .knowledge, .unknown:
      executor = "GalaxySSI"
    default:
      executor = firstTarget.isEmpty ? "GalaxySSI" : firstTarget
    }
    let location = resolvedLocation ?? AgentExecutionLocation(
      locationKind: locationKind,
      runtimeKind: inferredRuntimeKind(routeKind: routeKind, locationKind: locationKind, toolId: ""),
      locationName: locationKind == .desktop && targetParts.count > 1 ? targetParts[1] : ""
    )
    return AgentExecutionPresentation(
      executorId: firstTarget.isEmpty ? "galaxyssi" : firstTarget,
      executorLabel: executor,
      locationKind: location.locationKind,
      locationLabelHint: location.locationName,
      runtimeKind: location.runtimeKind,
      runtimeLabelHint: "",
      runtimeId: location.runtimeId,
      locationId: location.locationId,
      locationTrusted: location.trusted,
      currentStep: trim(currentStep),
      phase: phase,
      cancellable: isCancellable(phase),
      startedAtMillis: startedAtMillis,
      completedAtMillis: completedAtMillis
    )
  }

  static func remote(
    executorId: String,
    executorLabel: String,
    locationKind: String,
    locationId: String = "",
    locationName: String,
    runtimeKind: String = "",
    runtimeId: String = "",
    runtimeName: String = "",
    contract: String = "",
    status: String,
    currentStep: String,
    startedAtMillis: Int64,
    completedAtMillis: Int64,
    advertisedCancellable: Bool
  ) -> AgentExecutionPresentation {
    let phase = phaseForRemoteStatus(status)
    let cleanExecutorId = trim(executorId)
    let cleanExecutorLabel = trim(executorLabel)
    let resolvedExecutorId = cleanExecutorId.isEmpty ? cleanExecutorLabel : cleanExecutorId
    let resolvedExecutorLabel: String
    if cleanExecutorLabel.isEmpty {
      resolvedExecutorLabel = cleanExecutorId.isEmpty ? "Agent" : cleanExecutorId
    } else {
      resolvedExecutorLabel = cleanExecutorLabel
    }
    let declaredLocation = remoteDeclaredLocationKind(locationKind)
    let trustedLocation = contract == AgentExecutionLocationContract.version &&
      declaredLocation == .desktop &&
      !trim(locationId).isEmpty
    return AgentExecutionPresentation(
      executorId: resolvedExecutorId,
      executorLabel: resolvedExecutorLabel,
      locationKind: .desktop,
      locationLabelHint: trim(locationName),
      runtimeKind: remoteRuntimeKind(runtimeKind),
      runtimeLabelHint: trim(runtimeName),
      runtimeId: trim(runtimeId),
      locationId: trim(locationId),
      locationTrusted: trustedLocation,
      currentStep: trim(currentStep),
      phase: phase,
      cancellable: advertisedCancellable && isCancellable(phase),
      startedAtMillis: startedAtMillis,
      completedAtMillis: completedAtMillis
    )
  }

  static func isCancellable(_ phase: AgentPhase) -> Bool {
    ![.completed, .failed, .cancelled, .blocked].contains(phase)
  }

  static func phaseForRemoteStatus(_ status: String) -> AgentPhase {
    AgentRemoteTaskStatusPolicy.phase(status)
  }

  private static func inferredLocationKind(
    routeKind: AgentRouteKind,
    toolId: String,
    executionDeviceId: String
  ) -> AgentExecutionLocationKind {
    if toolId == AgentIOSOnDeviceRuntimeNativeToolCatalog.execute {
      return .phone
    }
    switch routeKind {
    case .desktopAgent:
      return .desktop
    case .localModel where !trim(executionDeviceId).isEmpty:
      return .desktop
    case .deviceConnector:
      return .connectedDevice
    case .cloudModel, .localSystem, .localModel, .knowledge:
      return .phone
    case .unknown:
      return .unknown
    }
  }

  private static func inferredRuntimeKind(
    routeKind: AgentRouteKind,
    locationKind: AgentExecutionLocationKind,
    toolId: String
  ) -> AgentExecutionRuntimeKind {
    if toolId == AgentIOSOnDeviceRuntimeNativeToolCatalog.execute {
      return .phoneLinux
    }
    switch routeKind {
    case .desktopAgent:
      return .desktopAgent
    case .localModel where locationKind == .desktop:
      return .desktopAgent
    case .localModel:
      return .phoneLocalModel
    case .cloudModel:
      return .phoneCloudAPI
    case .deviceConnector:
      return .connectedDevice
    case .knowledge:
      return .knowledge
    case .localSystem:
      return .phoneNative
    case .unknown:
      return .unknown
    }
  }

  private static func remoteDeclaredLocationKind(_ value: String) -> AgentExecutionLocationKind {
    switch trim(value).lowercased() {
    case "desktop", "windows", "macos", "linux":
      return .desktop
    default:
      return .unknown
    }
  }

  private static func remoteRuntimeKind(_ value: String) -> AgentExecutionRuntimeKind {
    switch trim(value).lowercased() {
    case "desktop_tool":
      return .desktopTool
    case "desktop_agent", "agent":
      return .desktopAgent
    default:
      return .desktopAgent
    }
  }

  private static func targetParts(_ value: String) -> [String] {
    trim(value).components(separatedBy: targetSeparator).map(trim)
  }

  private static func firstNonBlank(_ values: String...) -> String {
    values.lazy.map(trim).first { !$0.isEmpty } ?? ""
  }

  private static func trim(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static let targetSeparator = " \u{00b7} "
}
