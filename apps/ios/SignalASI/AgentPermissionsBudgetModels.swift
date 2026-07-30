import Foundation

enum AgentConfirmationTier: String, Codable, CaseIterable, Identifiable {
  case direct = "DIRECT"
  case confirmOnce = "CONFIRM_ONCE"
  case confirmAlways = "CONFIRM_ALWAYS"

  var id: String { rawValue }
}
struct AgentAction: Codable, Equatable, Identifiable {
  var id: String
  var kind: AgentActionKind
  var target: String
  var risk: AgentRisk
  var status: AgentActionStatus
  var description: String
  var parameters: [String: String]
  var requiresConfirmation: Bool
  var result: String
  var evidence: String

  init(
    id: String,
    kind: AgentActionKind,
    target: String,
    risk: AgentRisk,
    status: AgentActionStatus,
    description: String,
    parameters: [String: String] = [:],
    requiresConfirmation: Bool = true,
    result: String = "",
    evidence: String = ""
  ) {
    self.id = id
    self.kind = kind
    self.target = target
    self.risk = risk
    self.status = status
    self.description = description
    self.parameters = parameters
    self.requiresConfirmation = requiresConfirmation
    self.result = result
    self.evidence = evidence
  }

  enum CodingKeys: String, CodingKey {
    case id
    case kind
    case target
    case risk
    case status
    case description
    case parameters
    case requiresConfirmation = "requires_confirmation"
    case result
    case evidence
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      kind: try container.decodeIfPresent(AgentActionKind.self, forKey: .kind) ?? .draftPlan,
      target: try container.decodeIfPresent(String.self, forKey: .target) ?? "",
      risk: try container.decodeIfPresent(AgentRisk.self, forKey: .risk) ?? .medium,
      status: try container.decodeIfPresent(AgentActionStatus.self, forKey: .status) ?? .pendingConfirmation,
      description: try container.decodeIfPresent(String.self, forKey: .description) ?? "",
      parameters: try container.decodeIfPresent([String: String].self, forKey: .parameters) ?? [:],
      requiresConfirmation: try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) ?? true,
      result: try container.decodeIfPresent(String.self, forKey: .result) ?? "",
      evidence: try container.decodeIfPresent(String.self, forKey: .evidence) ?? ""
    )
  }
}

protocol AgentActionExecutor {
  func execute(action: AgentAction, screen: AgentScreenContext) -> AgentActionResult
}

struct PhoneExecutionAuthoritySnapshot: Codable, Equatable {
  var activeSideEffectTaskId: String
  var queuedSideEffectTasks: Int
  var cancelledTaskCount: Int

  init(
    activeSideEffectTaskId: String = "",
    queuedSideEffectTasks: Int = 0,
    cancelledTaskCount: Int = 0
  ) {
    self.activeSideEffectTaskId = activeSideEffectTaskId
    self.queuedSideEffectTasks = max(queuedSideEffectTasks, 0)
    self.cancelledTaskCount = max(cancelledTaskCount, 0)
  }

  enum CodingKeys: String, CodingKey {
    case activeSideEffectTaskId = "active_side_effect_task_id"
    case queuedSideEffectTasks = "queued_side_effect_tasks"
    case cancelledTaskCount = "cancelled_task_count"
  }
}

enum PhoneExecutionAuthority {
  static func guarded(_ delegate: AgentActionExecutor) -> AgentActionExecutor {
    GuardedExecutor(delegate: delegate)
  }

  static func requestCancellation(taskId: String) {
    let normalized = normalize(taskId)
    guard !normalized.isEmpty else { return }
    stateLock.lock()
    cancelledTasks.insert(normalized)
    stateLock.unlock()
  }

  static func clearCancellation(taskId: String) {
    let normalized = normalize(taskId)
    guard !normalized.isEmpty else { return }
    stateLock.lock()
    cancelledTasks.remove(normalized)
    stateLock.unlock()
  }

  static func isCancelled(taskId: String) -> Bool {
    let normalized = normalize(taskId)
    guard !normalized.isEmpty else { return false }
    stateLock.lock()
    let cancelled = cancelledTasks.contains(normalized)
    stateLock.unlock()
    return cancelled
  }

  static func snapshot() -> PhoneExecutionAuthoritySnapshot {
    stateLock.lock()
    let snapshot = PhoneExecutionAuthoritySnapshot(
      activeSideEffectTaskId: activeSideEffectTask,
      queuedSideEffectTasks: queuedSideEffectTasks,
      cancelledTaskCount: cancelledTasks.count
    )
    stateLock.unlock()
    return snapshot
  }

  fileprivate static func execute(
    delegate: AgentActionExecutor,
    action: AgentAction,
    screen: AgentScreenContext
  ) -> AgentActionResult {
    let taskId = taskId(for: action)
    if isCancelled(taskId: taskId) {
      return cancelledResult(action: action, taskId: taskId)
    }
    if action.kind.isConcurrentPhoneRead {
      return delegate.execute(action: action, screen: screen)
        .withAuthorityMetadata(taskId: taskId, serialized: false)
    }

    stateLock.lock()
    queuedSideEffectTasks += 1
    stateLock.unlock()
    sideEffectLock.lock()
    stateLock.lock()
    queuedSideEffectTasks = max(queuedSideEffectTasks - 1, 0)
    activeSideEffectTask = taskId
    stateLock.unlock()
    defer {
      stateLock.lock()
      if activeSideEffectTask == taskId {
        activeSideEffectTask = ""
      }
      stateLock.unlock()
      sideEffectLock.unlock()
    }

    if isCancelled(taskId: taskId) {
      return cancelledResult(action: action, taskId: taskId)
    }
    return delegate.execute(action: action, screen: screen)
      .withAuthorityMetadata(taskId: taskId, serialized: true)
  }

  private static func taskId(for action: AgentAction) -> String {
    let candidate = normalize(action.parameters[taskIdParameter] ?? "")
    return candidate.isEmpty ? action.id : candidate
  }

  private static func cancelledResult(action: AgentAction, taskId: String) -> AgentActionResult {
    AgentActionResult(
      actionId: action.id,
      success: false,
      message: "Phone tool execution was cancelled",
      metadata: [
        "execution_location": "phone",
        "execution_authority": "signalasi-phone",
        "task_id": taskId,
        "cancelled": "true"
      ]
    )
  }

  private static func normalize(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static let taskIdParameter = "_signalasi_task_id"
  private static let sideEffectLock = NSLock()
  private static let stateLock = NSLock()
  private static var activeSideEffectTask = ""
  private static var queuedSideEffectTasks = 0
  private static var cancelledTasks: Set<String> = []

  private final class GuardedExecutor: AgentActionExecutor {
    private let delegate: AgentActionExecutor

    init(delegate: AgentActionExecutor) {
      self.delegate = delegate
    }

    func execute(action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
      PhoneExecutionAuthority.execute(delegate: delegate, action: action, screen: screen)
    }
  }
}

private extension AgentActionKind {
  var isConcurrentPhoneRead: Bool {
    self == .readScreen || self == .draftPlan
  }
}

private extension AgentActionResult {
  func withAuthorityMetadata(taskId: String, serialized: Bool) -> AgentActionResult {
    var value = self
    value.metadata.merge([
      "execution_location": "phone",
      "execution_authority": "signalasi-phone",
      "task_id": taskId,
      "serialized_side_effect": serialized.description
    ]) { _, new in new }
    return value
  }
}

struct AgentAutonomyDecision: Codable, Equatable {
  var allowed: Bool
  var reason: String
  var completedToolCalls: Int
  var repeatedCalls: Int

  init(
    allowed: Bool,
    reason: String = "",
    completedToolCalls: Int = 0,
    repeatedCalls: Int = 0
  ) {
    self.allowed = allowed
    self.reason = reason
    self.completedToolCalls = max(completedToolCalls, 0)
    self.repeatedCalls = max(repeatedCalls, 0)
  }

  enum CodingKeys: String, CodingKey {
    case allowed
    case reason
    case completedToolCalls = "completed_tool_calls"
    case repeatedCalls = "repeated_calls"
  }
}

enum AgentAutonomyGuard {
  static let maxRepeatedToolCalls = 2

  static func completedToolCalls(plan: AgentPlan) -> Int {
    (plan.actionHistory + plan.actions).filter {
      $0.kind.isBudgetedAutonomyToolCall && terminalToolStatuses.contains($0.status)
    }.count
  }

  static func review(
    plan: AgentPlan,
    action: AgentAction,
    settings: AgentModelPlannerSettings
  ) -> AgentAutonomyDecision {
    let history = plan.actionHistory + plan.actions
    let completedCalls = completedToolCalls(plan: plan)
    if completedCalls >= settings.normalized.maxToolCalls {
      return AgentAutonomyDecision(
        allowed: false,
        reason: "Autonomous tool-call budget reached",
        completedToolCalls: completedCalls
      )
    }

    let signature = autonomySignature(for: action)
    let repeatedCalls = history.filter {
      $0.kind.isLoopSensitiveAutonomyToolCall &&
        terminalToolStatuses.contains($0.status) &&
        autonomySignature(for: $0) == signature
    }.count
    if action.kind.isLoopSensitiveAutonomyToolCall && repeatedCalls >= maxRepeatedToolCalls {
      return AgentAutonomyDecision(
        allowed: false,
        reason: "Repeated autonomous tool-call loop blocked",
        completedToolCalls: completedCalls,
        repeatedCalls: repeatedCalls
      )
    }

    return AgentAutonomyDecision(
      allowed: true,
      completedToolCalls: completedCalls,
      repeatedCalls: repeatedCalls
    )
  }

  private static func autonomySignature(for action: AgentAction) -> String {
    [
      action.kind.rawValue,
      action.parameters["connector_id"] ?? "",
      action.parameters["package"] ?? "",
      action.parameters["url"] ?? "",
      androidStringHash(action.parameters["prompt"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
      action.target
    ].joined(separator: "|")
  }

  private static func androidStringHash(_ value: String) -> String {
    var hash = Int32(0)
    for unit in value.utf16 {
      hash = hash &* 31 &+ Int32(unit)
    }
    return String(hash)
  }

  private static let terminalToolStatuses: Set<AgentActionStatus> = [
    .completed,
    .failed,
    .blocked,
    .rolledBack
  ]
}

private extension AgentActionKind {
  var isBudgetedAutonomyToolCall: Bool {
    ![.readScreen, .draftPlan].contains(self)
  }

  var isLoopSensitiveAutonomyToolCall: Bool {
    [.callConnector, .controlDevice, .openURL, .openApp].contains(self)
  }
}

struct AgentActionRecoveryController {
  func recover(
    action: AgentAction,
    failedResult: AgentActionResult?,
    failedObservation: AgentObservationOutcome,
    retry: () -> AgentRecoveryAttempt
  ) -> AgentRecoveryOutcome {
    guard failedResult?.success == false else {
      return AgentRecoveryOutcome(
        result: failedResult,
        observation: failedObservation,
        decision: .notNeeded,
        attemptCount: 0
      )
    }
    guard supportsAutomaticRecovery(action),
      failedObservation.decision == .timedOut else {
      return AgentRecoveryOutcome(
        result: failedResult,
        observation: failedObservation,
        decision: .manualRequired,
        attemptCount: 0
      )
    }

    let attempt = retry()
    return AgentRecoveryOutcome(
      result: attempt.result,
      observation: attempt.observation,
      decision: attempt.result?.success == true ? .retrySucceeded : .retryFailed,
      attemptCount: 1
    )
  }

  private func supportsAutomaticRecovery(_ action: AgentAction) -> Bool {
    action.risk == .low && Self.safeRetryActions.contains(action.kind)
  }

  private static let safeRetryActions: Set<AgentActionKind> = [.openApp, .home, .recents]
}

enum AgentActionRiskHardener {
  static let minConfidentVisualAction = 0.70

  static func enforce(plan: AgentPlan) -> AgentPlan {
    enforce(plan: plan, customDeviceRisks: [:])
  }

  static func enforce(
    plan: AgentPlan,
    customDeviceConnectors: [CustomDeviceConnector],
    homeAssistantSettings: HomeAssistantSettings = .default
  ) -> AgentPlan {
    var customDeviceRisks: [String: CustomDeviceRisk] = [:]
    for connector in customDeviceConnectors {
      customDeviceRisks[connector.id] = connector.risk
    }
    return enforce(
      plan: plan,
      customDeviceRisks: customDeviceRisks,
      homeAssistantDefaultEntityId: homeAssistantSettings.defaultEntityId
    )
  }

  static func enforce(
    plan: AgentPlan,
    customDeviceRisks: [String: CustomDeviceRisk],
    homeAssistantDefaultEntityId: String = ""
  ) -> AgentPlan {
    let actions = plan.actions.map { action in
      var copy = action
      copy.risk = higherRisk(
        action.risk,
        hardenedRisk(
          for: action,
          customDeviceRisks: customDeviceRisks,
          homeAssistantDefaultEntityId: homeAssistantDefaultEntityId
        )
      )
      return copy
    }
    var hardened = plan
    hardened.actions = actions
    hardened.validation = AgentPlanValidator.validate(hardened)
    return hardened
  }

  private static func hardenedRisk(
    for action: AgentAction,
    customDeviceRisks: [String: CustomDeviceRisk],
    homeAssistantDefaultEntityId: String
  ) -> AgentRisk {
    switch action.kind {
    case .controlDevice:
      return deviceRisk(
        action,
        customDeviceRisks: customDeviceRisks,
        homeAssistantDefaultEntityId: homeAssistantDefaultEntityId
      )
    case .callConnector:
      return connectorRisk(action)
    case .tap, .longPress:
      return visualGroundingRisk(
        origin: action.parameters["element_origin"] ?? "",
        confidenceValue: action.parameters["element_confidence"] ?? ""
      )
    case .typeText, .deleteText, .pasteText:
      return visualGroundingRisk(
        origin: action.parameters["field_origin"] ?? "",
        confidenceValue: action.parameters["field_confidence"] ?? ""
      )
    default:
      return action.risk
    }
  }

  private static func deviceRisk(
    _ action: AgentAction,
    customDeviceRisks: [String: CustomDeviceRisk],
    homeAssistantDefaultEntityId: String
  ) -> AgentRisk {
    let connectorId = (action.parameters["connector_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if connectorId.hasPrefix(customDevicePrefix) {
      let customDeviceId = String(connectorId.dropFirst(customDevicePrefix.count))
      guard let risk = customDeviceRisks[customDeviceId] else { return .high }
      return agentRisk(for: risk)
    }
    if connectorId == homeAssistantConnectorId {
      return AgentHomeAssistantRiskPolicy.riskForPrompt(
        action.parameters["prompt"] ?? "",
        defaultEntityId: homeAssistantDefaultEntityId
      )
    }
    return .high
  }

  private static func connectorRisk(_ action: AgentAction) -> AgentRisk {
    let value = [
      action.description,
      action.target,
      action.parameters["prompt"] ?? ""
    ].joined(separator: " ").lowercased()
    return highRiskConnectorTerms.contains(where: { value.contains($0) }) ? .high : action.risk
  }

  private static func visualGroundingRisk(origin: String, confidenceValue: String) -> AgentRisk {
    guard AgentElementOrigin.fromWireValue(origin) == .visualOcr else {
      return .low
    }
    let confidence = Double(confidenceValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    return confidence < minConfidentVisualAction ? .high : .medium
  }

  private static func higherRisk(_ first: AgentRisk, _ second: AgentRisk) -> AgentRisk {
    first.weight >= second.weight ? first : second
  }

  private static func agentRisk(for risk: CustomDeviceRisk) -> AgentRisk {
    switch risk {
    case .low: return .low
    case .medium: return .medium
    case .high: return .high
    }
  }

  private static let customDevicePrefix = "custom-device:"
  private static let homeAssistantConnectorId = "home-assistant"
  private static let highRiskConnectorTerms = [
    "delete", "erase", "remove account", "install", "uninstall", "deploy", "publish",
    "send message", "send email", "payment", "purchase", "buy", "order", "transfer",
    "credential", "password", "private key", "api key", "unlock", "open door",
    "\u{5220}\u{9664}", "\u{6e05}\u{9664}", "\u{5b89}\u{88c5}", "\u{5378}\u{8f7d}",
    "\u{90e8}\u{7f72}", "\u{53d1}\u{5e03}", "\u{53d1}\u{9001}", "\u{652f}\u{4ed8}",
    "\u{8d2d}\u{4e70}", "\u{8f6c}\u{8d26}", "\u{5bc6}\u{7801}", "\u{79c1}\u{94a5}",
    "\u{89e3}\u{9501}", "\u{5f00}\u{95e8}"
  ]
}

enum AgentHomeAssistantRiskPolicy {
  static func riskForPrompt(_ prompt: String, defaultEntityId: String = "") -> AgentRisk {
    riskForEntity(
      prompt: prompt,
      entityId: entityId(for: prompt, defaultEntityId: defaultEntityId)
    )
  }

  static func entityId(for prompt: String, defaultEntityId: String = "") -> String {
    if let range = prompt.range(of: entityIdPattern, options: .regularExpression) {
      return String(prompt[range]).lowercased()
    }
    return defaultEntityId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static func riskForEntity(prompt: String, entityId: String) -> AgentRisk {
    let lower = prompt.lowercased()
    let domain = entityId.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
    if highRiskControlDomains.contains(domain) {
      return .high
    }
    if domain == "cover" && highRiskControlTerms.contains(where: { lower.contains($0) }) {
      return .high
    }
    if mediumRiskControlDomains.contains(domain) {
      return .medium
    }
    if highRiskControlTerms.contains(where: { lower.contains($0) }) {
      return .high
    }
    if mediumRiskControlTerms.contains(where: { lower.contains($0) }) {
      return .medium
    }
    return .low
  }

  private static let entityIdPattern = #"[A-Za-z0-9_]+\.[A-Za-z0-9_]+"#
  private static let highRiskControlDomains: Set<String> = [
    "alarm_control_panel",
    "automation",
    "camera",
    "lock",
    "siren",
    "script",
    "valve"
  ]
  private static let mediumRiskControlDomains: Set<String> = [
    "climate",
    "cover",
    "fan",
    "scene",
    "switch",
    "vacuum"
  ]
  private static let highRiskControlTerms = [
    "alarm",
    "camera",
    "door",
    "gate",
    "garage",
    "lock",
    "security",
    "siren",
    "valve"
  ]
  private static let mediumRiskControlTerms = [
    "automation",
    "blind",
    "climate",
    "cover",
    "curtain",
    "scene",
    "script",
    "switch",
    "thermostat"
  ]
}

enum AgentConfirmationPolicy {
  static func tier(for action: AgentAction) -> AgentConfirmationTier {
    let value = searchableValue(action)
    let toolId = nativeToolId(action)
    if toolId == homeAssistantServiceCall && requiresAlwaysHomeAssistantConfirmation(action.parameters["input_json"] ?? "") {
      return .confirmAlways
    }
    if alwaysConfirmNativeToolIds.contains(toolId) {
      return .confirmAlways
    }
    if confirmOnceNativeToolIds.contains(toolId) {
      return .confirmOnce
    }
    if desktopRemoteNativeToolIds.contains(toolId) {
      return .direct
    }
    if toolId == webSearch || webIntelligenceToolIds.contains(toolId) {
      return .direct
    }
    if alwaysConfirmKinds.contains(action.kind) || alwaysConfirmTerms.contains(where: value.contains) {
      return .confirmAlways
    }
    if action.kind == .callConnector {
      return .direct
    }
    if confirmOnceTerms.contains(where: value.contains) || action.kind == .controlDevice {
      return .confirmOnce
    }
    if action.kind == .setAlarm ||
      action.kind == .openApp ||
      directActionIds.contains(action.id) ||
      directNativeToolIds.contains(toolId) ||
      directTerms.contains(where: value.contains) {
      return .direct
    }
    switch action.risk {
    case .low:
      return .direct
    case .medium:
      return .confirmOnce
    case .high, .blocked:
      return .confirmAlways
    }
  }

  static func consentKey(for action: AgentAction) -> String {
    let value = searchableValue(action)
    let toolId = nativeToolId(action)
    if locationTerms.contains(where: value.contains) {
      return "location"
    }
    if microphoneTerms.contains(where: value.contains) {
      return "microphone"
    }
    if downloadTerms.contains(where: value.contains) {
      return "downloads"
    }
    if contactWriteTerms.contains(where: value.contains) {
      return "contacts_write"
    }
    if calendarWriteTerms.contains(where: value.contains) {
      return "calendar_write"
    }
    if toolId == bluetoothDiscoveryForeground {
      return "bluetooth_discovery"
    }
    if toolId == wifiScanStart {
      return "wifi_scan"
    }
    if toolId == installedAppsList || toolId == packageDetail {
      return "installed_apps_read"
    }
    if toolId == homeAssistantEntitiesList || toolId == homeAssistantEntityRead {
      return "home_assistant_read"
    }
    if toolId == homeAssistantServiceCall {
      return homeAssistantConsentScope(action.parameters["input_json"] ?? "")
    }
    if action.kind == .controlDevice {
      return "device_control:\(action.target.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
    }
    return "action:\(action.kind.rawValue.lowercased()):\(action.id.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
  }

  private static func nativeToolId(_ action: AgentAction) -> String {
    action.parameters["tool_id"] ?? ""
  }

  private static func searchableValue(_ action: AgentAction) -> String {
    var parts = [action.id, action.kind.rawValue, action.target, action.description]
    for (key, value) in action.parameters where !key.hasPrefix(internalParameterPrefix) {
      parts.append(key)
      parts.append(value)
    }
    return parts.joined(separator: " ").lowercased()
  }

  private static func requiresAlwaysHomeAssistantConfirmation(_ inputJson: String) -> Bool {
    let input = homeAssistantInput(inputJson)
    let cleanEntity = input.entityId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let entityDomain = cleanEntity.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
    let identity = "\(cleanEntity) \(input.serviceDomain.lowercased()) \(input.service.lowercased())"
    return homeAssistantAlwaysConfirmDomains.contains(entityDomain) ||
      homeAssistantAlwaysConfirmServices.contains(input.service.lowercased()) ||
      homeAssistantAlwaysConfirmIdentityTerms.contains(where: identity.contains)
  }

  private static func homeAssistantConsentScope(_ inputJson: String) -> String {
    let entityId = homeAssistantInput(inputJson).entityId
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if entityId.range(of: #"^[a-z0-9_]+\.[a-z0-9_]+$"#, options: .regularExpression) != nil {
      return "home_assistant_control:\(entityId)"
    }
    return "home_assistant_control"
  }

  private static func homeAssistantInput(_ inputJson: String) -> (entityId: String, serviceDomain: String, service: String) {
    guard let data = inputJson.data(using: .utf8),
          let rawObject = try? JSONSerialization.jsonObject(with: data),
          let object = rawObject as? [String: Any] else {
      return ("", "", "")
    }
    return (
      object["entity_id"] as? String ?? "",
      object["service_domain"] as? String ?? "",
      object["service"] as? String ?? ""
    )
  }

  private static let internalParameterPrefix = "_signalasi_"
  private static let homeAssistantServiceCall = "signalasi.home_assistant.service.call"
  private static let homeAssistantEntitiesList = "signalasi.home_assistant.entities.list"
  private static let homeAssistantEntityRead = "signalasi.home_assistant.entity.read"
  private static let bluetoothDiscoveryForeground = "signalasi.hardware.bluetooth.discovery.foreground"
  private static let installedAppsList = "signalasi.hardware.apps.installed.list"
  private static let packageDetail = "signalasi.hardware.apps.package.detail"
  private static let wifiScanStart = "signalasi.android.wifi.scan.start"
  private static let webSearch = "web.search"

  private static let alwaysConfirmKinds: Set<AgentActionKind> = [.replyNotification, .deleteText, .lockScreen]
  private static let directActionIds: Set<String> = [
    "set-timer", "open-timer", "set-alarm", "open-camera", "open-flashlight",
    "battery-status", "device-status"
  ]
  private static let desktopRemoteNativeToolIds: Set<String> = [
    "signalasi.desktop.windows.system.status",
    "signalasi.desktop.windows.process.list",
    "signalasi.desktop.workspace.file.list",
    "signalasi.desktop.workspace.file.read.text",
    "signalasi.desktop.workspace.file.write.text",
    "signalasi.desktop.workspace.file.sha256",
    "signalasi.desktop.workspace.archive.create",
    "signalasi.desktop.terminal.run",
    "signalasi.desktop.office.document.inspect",
    "signalasi.desktop.office.document.convert"
  ]
  private static let webIntelligenceToolIds: Set<String> = [
    "signalasi.web.intelligence.search",
    "signalasi.web.intelligence.fetch",
    "signalasi.web.intelligence.crawl",
    "signalasi.web.intelligence.extract",
    "signalasi.web.intelligence.cache",
    "signalasi.web.intelligence.find_similar",
    "signalasi.web.intelligence.research",
    "signalasi.web.intelligence.agent",
    "signalasi.web.intelligence.diff",
    "signalasi.web.intelligence.watch"
  ]
  private static let directNativeToolIds = Set([
    "signalasi.hardware.battery.status",
    "signalasi.hardware.power.status",
    "signalasi.hardware.storage.status",
    "signalasi.hardware.network.status",
    "signalasi.hardware.sensors.list",
    "signalasi.hardware.sensor.sample",
    "signalasi.hardware.bluetooth.status",
    "signalasi.hardware.nfc.status",
    "signalasi.hardware.flashlight.set",
    "signalasi.camera.capture.visible",
    "web.search",
    "signalasi.media.ffmpeg.transcode",
    "signalasi.runtime.execute",
    "signalasi.hardware.bluetooth.pairing.handoff",
    "signalasi.android.audio.status",
    "signalasi.android.audio.volume.set",
    "signalasi.android.audio.mute.set",
    "signalasi.android.wifi.panel.open",
    "signalasi.android.wifi.hotspot.panel.open",
    "signalasi.android.biometric.enrollment.open"
  ])
    .union(webIntelligenceToolIds)
    .union(AgentIOSWebMediaNativeToolCatalog.directToolIds)
  private static let confirmOnceNativeToolIds: Set<String> = Set([
    "signalasi.microphone.record.visible",
    "signalasi.notifications.list",
    bluetoothDiscoveryForeground,
    installedAppsList,
    packageDetail,
    wifiScanStart,
    "signalasi.runtime.packs.install",
    homeAssistantEntitiesList,
    homeAssistantEntityRead,
    homeAssistantServiceCall
  ]).union(AgentIOSWebMediaNativeToolCatalog.confirmOnceToolIds)
  private static let alwaysConfirmNativeToolIds: Set<String> = [
    "signalasi.notifications.reply",
    "signalasi.desktop.terminal.run"
  ]

  private static let alwaysConfirmTerms = [
    "send sms", "sms.send", "reply sms", "send message", "reply message", "reply notification",
    "send email", "reply email", "phone call", "dial", "telephony.dial", "delete", "remove",
    "install", "uninstall", "payment", "purchase", "checkout", "transfer", "grant permission",
    "authorize", "security setting", "screen lock", "lock device", "device_policy.lock", "reboot",
    "door lock", "smart lock", "garage door", "alarm panel", "private key", "password",
    "\u{53D1}\u{9001}\u{77ED}\u{4FE1}", "\u{56DE}\u{590D}\u{77ED}\u{4FE1}",
    "\u{53D1}\u{6D88}\u{606F}", "\u{56DE}\u{590D}\u{6D88}\u{606F}",
    "\u{6253}\u{7535}\u{8BDD}", "\u{62E8}\u{53F7}", "\u{5220}\u{9664}",
    "\u{5B89}\u{88C5}", "\u{5378}\u{8F7D}", "\u{652F}\u{4ED8}",
    "\u{8F6C}\u{8D26}", "\u{6388}\u{6743}", "\u{6743}\u{9650}",
    "\u{5B89}\u{5168}\u{8BBE}\u{7F6E}", "\u{9501}\u{5C4F}",
    "\u{91CD}\u{542F}", "\u{95E8}\u{9501}", "\u{8F66}\u{5E93}\u{95E8}"
  ]
  private static let directTerms = [
    "timer", "alarm clock", "set alarm", "camera capture", "take photo", "flashlight", "torch",
    "audio volume", "set volume", "audio mute", "open app", "launch app", "battery status",
    "device status", "read battery", "read device", "\u{8BA1}\u{65F6}\u{5668}",
    "\u{95F9}\u{949F}", "\u{62CD}\u{7167}", "\u{624B}\u{7535}\u{7B52}",
    "\u{97F3}\u{91CF}", "\u{6253}\u{5F00}app", "\u{6253}\u{5F00} app",
    "\u{7535}\u{91CF}", "\u{8BBE}\u{5907}\u{72B6}\u{6001}"
  ]
  private static let locationTerms = ["location", "gps", "\u{5B9A}\u{4F4D}", "\u{4F4D}\u{7F6E}"]
  private static let microphoneTerms = ["microphone", "record audio", "\u{9EA6}\u{514B}\u{98CE}", "\u{5F55}\u{97F3}"]
  private static let downloadTerms = ["download", "\u{4E0B}\u{8F7D}"]
  private static let contactWriteTerms = [
    "contacts.write", "contact upsert", "create contact", "update contact",
    "\u{65B0}\u{5EFA}\u{8054}\u{7CFB}\u{4EBA}", "\u{4FEE}\u{6539}\u{8054}\u{7CFB}\u{4EBA}",
    "\u{66F4}\u{65B0}\u{8054}\u{7CFB}\u{4EBA}"
  ]
  private static let calendarWriteTerms = [
    "calendar.write", "calendar event upsert", "create calendar event", "update calendar event",
    "\u{65B0}\u{5EFA}\u{65E5}\u{7A0B}", "\u{4FEE}\u{6539}\u{65E5}\u{7A0B}",
    "\u{66F4}\u{65B0}\u{65E5}\u{7A0B}"
  ]
  private static let confirmOnceTerms = locationTerms + microphoneTerms + downloadTerms + contactWriteTerms + calendarWriteTerms
  private static let homeAssistantAlwaysConfirmDomains: Set<String> = [
    "alarm_control_panel", "automation", "camera", "lock", "script", "siren", "valve"
  ]
  private static let homeAssistantAlwaysConfirmServices: Set<String> = [
    "alarm_arm_away", "alarm_arm_home", "alarm_arm_night", "alarm_disarm", "alarm_trigger", "unlock"
  ]
  private static let homeAssistantAlwaysConfirmIdentityTerms = [
    "alarm", "door", "gate", "garage", "lock", "security", "siren"
  ]
}

enum AgentPermissionSubjectType: String, Codable, CaseIterable, Identifiable {
  case model = "MODEL"
  case agent = "AGENT"
  case tool = "TOOL"
  case android = "ANDROID"
  case device = "DEVICE"
  case file = "FILE"
  case app = "APP"
  case consequentialAction = "CONSEQUENTIAL_ACTION"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPermissionSubjectType {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .tool
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

enum AgentPermissionGrantLifetime: String, Codable, CaseIterable, Identifiable {
  case singleUse = "SINGLE_USE"
  case temporary = "TEMPORARY"
  case permanent = "PERMANENT"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPermissionGrantLifetime {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .singleUse
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

enum AgentPermissionGrantStatus: String, Codable, CaseIterable, Identifiable {
  case active = "ACTIVE"
  case consumed = "CONSUMED"
  case revoked = "REVOKED"
  case expired = "EXPIRED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPermissionGrantStatus {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .active
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

enum AgentPermissionGrantIssuer: String, Codable, CaseIterable, Identifiable {
  case user = "USER"
  case hostPolicy = "HOST_POLICY"
  case admin = "ADMIN"
  case `import` = "IMPORT"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPermissionGrantIssuer {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .user
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

struct AgentPermissionGrantLedgerError: Error, Equatable {
  var message: String
}

struct AgentPermissionGrant: Codable, Equatable, Identifiable {
  var grantId: String
  var subjectType: AgentPermissionSubjectType
  var subjectId: String
  var scope: String
  var action: String
  var resource: String
  var target: String
  var constraintsJson: String
  var issuer: AgentPermissionGrantIssuer
  var evidence: String
  var lifetime: AgentPermissionGrantLifetime
  var status: AgentPermissionGrantStatus
  var maxUses: Int
  var uses: Int
  var createdAtMillis: Int64
  var expiresAtMillis: Int64
  var consumedAtMillis: Int64
  var revokedAtMillis: Int64
  var revocationReason: String

  var id: String { grantId }

  init(
    grantId: String = UUID().uuidString,
    subjectType: AgentPermissionSubjectType,
    subjectId: String,
    scope: String,
    action: String = "",
    resource: String = "",
    target: String = "",
    constraintsJson: String = "{}",
    issuer: AgentPermissionGrantIssuer,
    evidence: String,
    lifetime: AgentPermissionGrantLifetime,
    status: AgentPermissionGrantStatus = .active,
    maxUses: Int? = nil,
    uses: Int = 0,
    createdAtMillis: Int64 = 0,
    expiresAtMillis: Int64 = 0,
    consumedAtMillis: Int64 = 0,
    revokedAtMillis: Int64 = 0,
    revocationReason: String = ""
  ) {
    self.grantId = grantId
    self.subjectType = subjectType
    self.subjectId = subjectId
    self.scope = scope
    self.action = action
    self.resource = resource
    self.target = target
    self.constraintsJson = constraintsJson
    self.issuer = issuer
    self.evidence = evidence
    self.lifetime = lifetime
    self.status = status
    self.maxUses = maxUses ?? (lifetime == .singleUse ? 1 : 0)
    self.uses = uses
    self.createdAtMillis = createdAtMillis
    self.expiresAtMillis = expiresAtMillis
    self.consumedAtMillis = consumedAtMillis
    self.revokedAtMillis = revokedAtMillis
    self.revocationReason = revocationReason
  }

  enum CodingKeys: String, CodingKey {
    case grantId = "grant_id"
    case subjectType = "subject_type"
    case subjectId = "subject_id"
    case scope
    case action
    case resource
    case target
    case constraintsJson = "constraints_json"
    case issuer
    case evidence
    case lifetime
    case status
    case maxUses = "max_uses"
    case uses
    case createdAtMillis = "created_at_millis"
    case expiresAtMillis = "expires_at_millis"
    case consumedAtMillis = "consumed_at_millis"
    case revokedAtMillis = "revoked_at_millis"
    case revocationReason = "revocation_reason"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let lifetime = try container.decodeIfPresent(AgentPermissionGrantLifetime.self, forKey: .lifetime) ?? .singleUse
    self.init(
      grantId: try container.decodeIfPresent(String.self, forKey: .grantId) ?? UUID().uuidString,
      subjectType: try container.decodeIfPresent(AgentPermissionSubjectType.self, forKey: .subjectType) ?? .tool,
      subjectId: try container.decodeIfPresent(String.self, forKey: .subjectId) ?? "",
      scope: try container.decodeIfPresent(String.self, forKey: .scope) ?? "",
      action: try container.decodeIfPresent(String.self, forKey: .action) ?? "",
      resource: try container.decodeIfPresent(String.self, forKey: .resource) ?? "",
      target: try container.decodeIfPresent(String.self, forKey: .target) ?? "",
      constraintsJson: try container.decodeIfPresent(String.self, forKey: .constraintsJson) ?? "{}",
      issuer: try container.decodeIfPresent(AgentPermissionGrantIssuer.self, forKey: .issuer) ?? .user,
      evidence: try container.decodeIfPresent(String.self, forKey: .evidence) ?? "",
      lifetime: lifetime,
      status: try container.decodeIfPresent(AgentPermissionGrantStatus.self, forKey: .status) ?? .active,
      maxUses: try container.decodeIfPresent(Int.self, forKey: .maxUses),
      uses: try container.decodeIfPresent(Int.self, forKey: .uses) ?? 0,
      createdAtMillis: try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? 0,
      expiresAtMillis: try container.decodeIfPresent(Int64.self, forKey: .expiresAtMillis) ?? 0,
      consumedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .consumedAtMillis) ?? 0,
      revokedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .revokedAtMillis) ?? 0,
      revocationReason: try container.decodeIfPresent(String.self, forKey: .revocationReason) ?? ""
    )
  }

  func isUsable(nowMillis: Int64) -> Bool {
    status == .active &&
      (expiresAtMillis <= 0 || nowMillis < expiresAtMillis) &&
      (maxUses <= 0 || uses < maxUses)
  }
}

struct AgentPermissionRequest: Codable, Equatable {
  var subjectType: AgentPermissionSubjectType
  var subjectId: String
  var scope: String
  var action: String
  var resource: String
  var target: String

  init(
    subjectType: AgentPermissionSubjectType,
    subjectId: String,
    scope: String,
    action: String = "",
    resource: String = "",
    target: String = ""
  ) {
    self.subjectType = subjectType
    self.subjectId = subjectId
    self.scope = scope
    self.action = action
    self.resource = resource
    self.target = target
  }

  enum CodingKeys: String, CodingKey {
    case subjectType = "subject_type"
    case subjectId = "subject_id"
    case scope
    case action
    case resource
    case target
  }
}

struct AgentPermissionDecision: Codable, Equatable {
  var granted: Bool
  var grant: AgentPermissionGrant?
  var reason: String
}

struct AgentPermissionRevocation: Codable, Equatable {
  var revokedGrantIds: Set<String>
  var scopes: Set<String>
  var reason: String
  var revokedAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case revokedGrantIds = "revoked_grant_ids"
    case scopes
    case reason
    case revokedAtMillis = "revoked_at_millis"
  }
}

final class InMemoryAgentPermissionGrantStore {
  private let lock = NSRecursiveLock()
  private let nowMillis: () -> Int64
  private var grants: [AgentPermissionGrant]

  init(
    serialized: String = "[]",
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.nowMillis = nowMillis
    self.grants = AgentPermissionGrantJsonCodec.decode(serialized)
  }

  func grant(_ grant: AgentPermissionGrant) throws -> AgentPermissionGrant {
    try synchronized {
      let now = currentTime()
      let normalized = try normalize(grant, now: now)
      var refreshed = refreshExpired(grants, now: now)
      if let equivalent = refreshed.first(where: { existing in
        existing.status == .active &&
          existing.subjectType == normalized.subjectType &&
          existing.subjectId == normalized.subjectId &&
          existing.scope == normalized.scope &&
          existing.action == normalized.action &&
          existing.resource == normalized.resource &&
          existing.target == normalized.target &&
          existing.constraintsJson == normalized.constraintsJson &&
          existing.lifetime == normalized.lifetime &&
          existing.expiresAtMillis == normalized.expiresAtMillis
      }) {
        grants = bound(refreshed)
        return equivalent
      }
      guard !refreshed.contains(where: { $0.grantId == normalized.grantId }) else {
        throw AgentPermissionGrantLedgerError(message: "Permission grant id was already used")
      }
      refreshed.append(normalized)
      grants = bound(refreshed)
      return normalized
    }
  }

  func authorize(
    _ request: AgentPermissionRequest,
    consume: Bool = false
  ) throws -> AgentPermissionDecision {
    try synchronized {
      let normalizedRequest = try normalize(request)
      let now = currentTime()
      var refreshed = refreshExpired(grants, now: now)
      guard let match = refreshed
        .filter({ $0.isUsable(nowMillis: now) && matches($0, request: normalizedRequest) })
        .sorted(by: { left, right in
          let leftScore = matchSpecificity(left, request: normalizedRequest)
          let rightScore = matchSpecificity(right, request: normalizedRequest)
          if leftScore == rightScore {
            return left.createdAtMillis > right.createdAtMillis
          }
          return leftScore > rightScore
        })
        .first else {
        grants = bound(refreshed)
        return AgentPermissionDecision(granted: false, grant: nil, reason: "no_matching_host_grant")
      }
      guard consume else {
        grants = bound(refreshed)
        return AgentPermissionDecision(granted: true, grant: match, reason: "host_grant_active")
      }
      let updatedUses = match.uses + 1
      var consumed = match
      consumed.uses = updatedUses
      consumed.status = match.maxUses > 0 && updatedUses >= match.maxUses ? .consumed : .active
      consumed.consumedAtMillis = now
      if let index = refreshed.firstIndex(where: { $0.grantId == match.grantId }) {
        refreshed[index] = consumed
      }
      grants = bound(refreshed)
      return AgentPermissionDecision(granted: true, grant: consumed, reason: "host_grant_consumed")
    }
  }

  func list(includeInactive: Bool = true) -> [AgentPermissionGrant] {
    synchronized {
      let now = currentTime()
      grants = bound(refreshExpired(grants, now: now))
      return grants
        .filter { includeInactive || $0.status == .active }
        .sorted {
          if $0.createdAtMillis == $1.createdAtMillis {
            return $0.grantId < $1.grantId
          }
          return $0.createdAtMillis > $1.createdAtMillis
        }
    }
  }

  func revokeGrant(
    grantId: String,
    reason: String
  ) -> AgentPermissionRevocation {
    let cleanId = grantId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanId.isEmpty else {
      return emptyRevocation(reason: reason)
    }
    return revoke(reason: reason) { $0.grantId == cleanId }
  }

  func revokeScope(
    scope: String,
    reason: String
  ) -> AgentPermissionRevocation {
    let cleanScope = scope.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanScope.isEmpty else {
      return emptyRevocation(reason: reason)
    }
    return revoke(reason: reason) { $0.scope == cleanScope }
  }

  func clear() {
    synchronized {
      grants = []
    }
  }

  func serializedSnapshot() -> String {
    synchronized {
      AgentPermissionGrantJsonCodec.encode(grants)
    }
  }

  private func synchronized<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private func revoke(
    reason: String,
    predicate: (AgentPermissionGrant) -> Bool
  ) -> AgentPermissionRevocation {
    synchronized {
      let now = currentTime()
      let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        .prefix(Self.maxReasonCharacters)
        .description
        .ifBlank("revoked_by_host")
      let refreshed = refreshExpired(grants, now: now)
      let revoked = refreshed.filter { $0.status == .active && predicate($0) }
      guard !revoked.isEmpty else {
        grants = bound(refreshed)
        return emptyRevocation(reason: cleanReason, now: now)
      }
      let revokedIds = Set(revoked.map(\.grantId))
      grants = bound(refreshed.map { grant in
        guard revokedIds.contains(grant.grantId) else {
          return grant
        }
        var updated = grant
        updated.status = .revoked
        updated.revokedAtMillis = now
        updated.revocationReason = cleanReason
        return updated
      })
      return AgentPermissionRevocation(
        revokedGrantIds: revokedIds,
        scopes: Set(revoked.map(\.scope)),
        reason: cleanReason,
        revokedAtMillis: now
      )
    }
  }

  private func normalize(_ grant: AgentPermissionGrant, now: Int64) throws -> AgentPermissionGrant {
    let grantId = try required(grant.grantId, limit: Self.maxIdCharacters, label: "grant id")
    let subjectId = try required(grant.subjectId, limit: Self.maxIdCharacters, label: "subject id")
    let scope = try required(grant.scope, limit: Self.maxScopeCharacters, label: "scope")
    let evidence = try required(grant.evidence, limit: Self.maxEvidenceCharacters, label: "evidence")
    let createdAt = grant.createdAtMillis > 0 ? grant.createdAtMillis : now
    guard grant.status == .active else {
      throw AgentPermissionGrantLedgerError(message: "Only active permission grants can be issued")
    }
    guard grant.uses == 0 && grant.consumedAtMillis == 0 && grant.revokedAtMillis == 0 else {
      throw AgentPermissionGrantLedgerError(message: "A new permission grant cannot contain prior usage or revocation state")
    }
    switch grant.lifetime {
    case .singleUse:
      guard grant.maxUses == 1 else {
        throw AgentPermissionGrantLedgerError(message: "Single-use permission grants must allow exactly one use")
      }
    case .temporary:
      guard grant.expiresAtMillis > createdAt else {
        throw AgentPermissionGrantLedgerError(message: "Temporary permission grants require a future expiry")
      }
    case .permanent:
      guard grant.expiresAtMillis == 0 else {
        throw AgentPermissionGrantLedgerError(message: "Permanent permission grants cannot expire")
      }
    }
    var normalized = grant
    normalized.grantId = grantId
    normalized.subjectId = subjectId
    normalized.scope = scope
    normalized.action = String(grant.action.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxScopeCharacters))
    normalized.resource = String(grant.resource.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxResourceCharacters))
    normalized.target = String(grant.target.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxResourceCharacters))
    normalized.constraintsJson = try normalizeJson(grant.constraintsJson)
    normalized.evidence = evidence
    normalized.createdAtMillis = createdAt
    normalized.revocationReason = ""
    return normalized
  }

  private func normalize(_ request: AgentPermissionRequest) throws -> AgentPermissionRequest {
    AgentPermissionRequest(
      subjectType: request.subjectType,
      subjectId: try required(request.subjectId, limit: Self.maxIdCharacters, label: "subject id"),
      scope: try required(request.scope, limit: Self.maxScopeCharacters, label: "scope"),
      action: String(request.action.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxScopeCharacters)),
      resource: String(request.resource.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxResourceCharacters)),
      target: String(request.target.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxResourceCharacters))
    )
  }

  private func refreshExpired(
    _ grants: [AgentPermissionGrant],
    now: Int64
  ) -> [AgentPermissionGrant] {
    grants.map { grant in
      guard grant.status == .active,
            grant.expiresAtMillis > 0,
            now >= grant.expiresAtMillis else {
        return grant
      }
      var expired = grant
      expired.status = .expired
      return expired
    }
  }

  private func matches(
    _ grant: AgentPermissionGrant,
    request: AgentPermissionRequest
  ) -> Bool {
    grant.subjectType == request.subjectType &&
      (grant.subjectId == request.subjectId || grant.subjectId == Self.wildcard) &&
      (grant.scope == request.scope || grant.scope == Self.wildcard) &&
      (grant.action.isEmpty || grant.action == request.action) &&
      (grant.resource.isEmpty || grant.resource == request.resource) &&
      (grant.target.isEmpty || grant.target == request.target)
  }

  private func matchSpecificity(
    _ grant: AgentPermissionGrant,
    request: AgentPermissionRequest
  ) -> Int {
    (grant.subjectId == request.subjectId ? 16 : 0) +
      (grant.scope == request.scope ? 8 : 0) +
      (grant.action.isEmpty ? 0 : 4) +
      (grant.resource.isEmpty ? 0 : 2) +
      (grant.target.isEmpty ? 0 : 1)
  }

  private func bound(_ grants: [AgentPermissionGrant]) -> [AgentPermissionGrant] {
    Array(grants.sorted {
      if $0.createdAtMillis == $1.createdAtMillis {
        return $0.grantId < $1.grantId
      }
      return $0.createdAtMillis < $1.createdAtMillis
    }.suffix(Self.maxGrants))
  }

  private func required(
    _ value: String,
    limit: Int,
    label: String
  ) throws -> String {
    let clean = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    guard !clean.isEmpty else {
      throw AgentPermissionGrantLedgerError(message: "Permission \(label) must not be blank")
    }
    return clean
  }

  private func normalizeJson(_ value: String) throws -> String {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("{}")
    guard let data = clean.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          JSONSerialization.isValidJSONObject(object),
          object is [String: Any],
          let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
      throw AgentPermissionGrantLedgerError(message: "Permission grant constraints must be a JSON object")
    }
    return String(decoding: encoded, as: UTF8.self)
  }

  private func emptyRevocation(
    reason: String,
    now: Int64? = nil
  ) -> AgentPermissionRevocation {
    AgentPermissionRevocation(
      revokedGrantIds: [],
      scopes: [],
      reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
      revokedAtMillis: now ?? currentTime()
    )
  }

  private func currentTime() -> Int64 {
    max(nowMillis(), 0)
  }

  private static let maxGrants = 2_000
  private static let maxIdCharacters = 256
  private static let maxScopeCharacters = 256
  private static let maxResourceCharacters = 2_048
  private static let maxEvidenceCharacters = 2_048
  private static let maxReasonCharacters = 1_024
  private static let wildcard = "*"
}

enum AgentPermissionGrantJsonCodec {
  static func encode(_ grants: [AgentPermissionGrant]) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(grants) else {
      return "[]"
    }
    return String(decoding: data, as: UTF8.self)
  }

  static func decode(_ raw: String) -> [AgentPermissionGrant] {
    guard let data = raw.data(using: .utf8),
          let grants = try? JSONDecoder().decode([AgentPermissionGrant].self, from: data) else {
      return []
    }
    return grants
  }
}

struct AgentRemoteApprovalRequest: Codable, Equatable {
  var taskId: String
  var clientRouteId: String
  var conversationId: String
  var turnId: String
  var contactId: String
  var sourceMessageId: Int64
  var approvalId: String
  var actionHash: String
  var kind: String
  var title: String
  var detail: String
  var target: String
  var reason: String
  var requestedAtMillis: Int64
  var expiresAtMillis: Int64
  var parametersJson: String

  var dedupeKey: String {
    "remote-approval:\(taskId):\(approvalId)"
  }

  var compactActionHash: String {
    "\(actionHash.prefix(8))...\(actionHash.suffix(8))"
  }

  func decision(approved: Bool) -> AgentRemoteApprovalDecision {
    AgentRemoteApprovalDecision(
      taskId: taskId,
      clientRouteId: clientRouteId,
      conversationId: conversationId,
      turnId: turnId,
      contactId: contactId,
      sourceMessageId: sourceMessageId,
      approvalId: approvalId,
      actionHash: actionHash,
      approved: approved
    )
  }

  enum CodingKeys: String, CodingKey {
    case taskId = "task_id"
    case clientRouteId = "client_route_id"
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case contactId = "contact_id"
    case sourceMessageId = "source_message_id"
    case approvalId = "approval_id"
    case actionHash = "action_hash"
    case kind
    case title
    case detail
    case target
    case reason
    case requestedAtMillis = "requested_at_millis"
    case expiresAtMillis = "expires_at_millis"
    case parametersJson = "parameters_json"
  }

  static func fromTaskEvent(
    _ raw: String,
    nowMillis: Int64 = AgentRemoteApprovalClock.nowMillis()
  ) -> AgentRemoteApprovalRequest? {
    guard let data = raw.data(using: .utf8),
      let object = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data) else {
      return nil
    }
    return fromTaskEvent(object, nowMillis: nowMillis)
  }

  static func fromTaskEvent(
    _ envelope: AgentMcpJSONObject?,
    nowMillis: Int64 = AgentRemoteApprovalClock.nowMillis()
  ) -> AgentRemoteApprovalRequest? {
    guard let envelope,
      envelope.string("type") == "agent_task_event",
      envelope.string("task_status") == "waiting_approval",
      let approval = envelope.object("approval_request") else {
      return nil
    }

    let taskId = envelope.string("task_id").clampedTrimmed(to: 160)
    let clientRouteId = envelope.string("client_route_id").clampedTrimmed(to: 200)
    let conversationId = envelope.string("conversation_id").clampedTrimmed(to: 200)
    let turnId = envelope.string("turn_id").clampedTrimmed(to: 200)
    let contactId = envelope.string("contact_id").clampedTrimmed(to: 160)
    let sourceMessageId = envelope.int64("source_message_id")
    let approvalId = approval.string("approval_id").trimmingCharacters(in: .whitespacesAndNewlines)
    let actionHash = approval.string("action_hash")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let requestedAt = approval.int64("requested_at_ms")
    let expiresAt = approval.int64("expires_at_ms")

    guard !taskId.isEmpty,
      !clientRouteId.isEmpty,
      !conversationId.isEmpty,
      !turnId.isEmpty,
      !contactId.isEmpty,
      sourceMessageId > 0,
      approvalId.range(of: AgentRemoteApprovalValidation.idPattern, options: .regularExpression) != nil,
      actionHash.range(of: AgentRemoteApprovalValidation.hashPattern, options: .regularExpression) != nil,
      requestedAt > 0,
      expiresAt > nowMillis,
      expiresAt > requestedAt,
      expiresAt - requestedAt <= AgentRemoteApprovalValidation.maximumLifetimeMillis else {
      return nil
    }

    let parameters = approval.object("parameters").map(AgentMcpJSONCodec.stringify) ?? ""
    return AgentRemoteApprovalRequest(
      taskId: taskId,
      clientRouteId: clientRouteId,
      conversationId: conversationId,
      turnId: turnId,
      contactId: contactId,
      sourceMessageId: sourceMessageId,
      approvalId: approvalId,
      actionHash: actionHash,
      kind: approval.string("kind").clampedTrimmed(to: 80),
      title: approval.string("title").clampedTrimmed(to: 500),
      detail: approval.string("detail").clampedTrimmed(to: 4_000),
      target: approval.string("target").clampedTrimmed(to: 2_000),
      reason: approval.string("reason").clampedTrimmed(to: 2_000),
      requestedAtMillis: requestedAt,
      expiresAtMillis: expiresAt,
      parametersJson: String(parameters.prefix(16_384))
    )
  }
}

struct AgentRemoteApprovalDecision: Codable, Equatable {
  var taskId: String
  var clientRouteId: String
  var conversationId: String
  var turnId: String
  var contactId: String
  var sourceMessageId: Int64
  var approvalId: String
  var actionHash: String
  var approved: Bool

  enum CodingKeys: String, CodingKey {
    case taskId = "task_id"
    case clientRouteId = "client_route_id"
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case contactId = "contact_id"
    case sourceMessageId = "source_message_id"
    case approvalId = "approval_id"
    case actionHash = "action_hash"
    case approved
  }

  func encode() -> String {
    AgentMcpJSONCodec.stringify([
      "task_id": .string(taskId),
      "client_route_id": .string(clientRouteId),
      "conversation_id": .string(conversationId),
      "turn_id": .string(turnId),
      "contact_id": .string(contactId),
      "source_message_id": .int(Int(sourceMessageId)),
      "approval_id": .string(approvalId),
      "action_hash": .string(actionHash),
      "approved": .bool(approved)
    ])
  }

  static func decode(_ raw: String) -> AgentRemoteApprovalDecision? {
    guard let data = raw.data(using: .utf8),
      let object = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data) else {
      return nil
    }
    let taskId = object.string("task_id").clampedTrimmed(to: 160)
    let clientRouteId = object.string("client_route_id").clampedTrimmed(to: 200)
    let conversationId = object.string("conversation_id").clampedTrimmed(to: 200)
    let turnId = object.string("turn_id").clampedTrimmed(to: 200)
    let contactId = object.string("contact_id").clampedTrimmed(to: 160)
    let sourceMessageId = object.int64("source_message_id")
    let approvalId = object.string("approval_id").trimmingCharacters(in: .whitespacesAndNewlines)
    let actionHash = object.string("action_hash")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    guard !taskId.isEmpty,
      !clientRouteId.isEmpty,
      !conversationId.isEmpty,
      !turnId.isEmpty,
      !contactId.isEmpty,
      sourceMessageId > 0,
      approvalId.range(of: AgentRemoteApprovalValidation.idPattern, options: .regularExpression) != nil,
      actionHash.range(of: AgentRemoteApprovalValidation.hashPattern, options: .regularExpression) != nil else {
      return nil
    }
    return AgentRemoteApprovalDecision(
      taskId: taskId,
      clientRouteId: clientRouteId,
      conversationId: conversationId,
      turnId: turnId,
      contactId: contactId,
      sourceMessageId: sourceMessageId,
      approvalId: approvalId,
      actionHash: actionHash,
      approved: object.bool("approved")
    )
  }
}

private enum AgentRemoteApprovalValidation {
  static let idPattern = #"^[A-Za-z0-9._:-]{8,128}$"#
  static let hashPattern = #"^[0-9a-f]{64}$"#
  static let maximumLifetimeMillis: Int64 = 24 * 60 * 60 * 1_000
}

enum AgentRemoteApprovalClock {
  static func nowMillis() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }
}

private extension String {
  func clampedTrimmed(to limit: Int) -> String {
    String(trimmingCharacters(in: .whitespacesAndNewlines).prefix(max(limit, 0)))
  }
}

enum AgentClarificationMode: String, Codable, CaseIterable, Identifiable {
  case execute = "EXECUTE"
  case askLocally = "ASK_LOCALLY"
  case askWithModel = "ASK_WITH_MODEL"

  var id: String { rawValue }
}

enum AgentClarificationQuestion: String, Codable, CaseIterable, Identifiable {
  case none = "NONE"
  case taskGoal = "TASK_GOAL"
  case codeOutcome = "CODE_OUTCOME"
  case controlAction = "CONTROL_ACTION"
  case researchTopic = "RESEARCH_TOPIC"
  case fileAction = "FILE_ACTION"
  case memoryContent = "MEMORY_CONTENT"
  case automationDetails = "AUTOMATION_DETAILS"

  var id: String { rawValue }
}

struct AgentClarificationDecision: Codable, Equatable {
  var mode: AgentClarificationMode
  var question: AgentClarificationQuestion

  init(
    mode: AgentClarificationMode,
    question: AgentClarificationQuestion = .none
  ) {
    self.mode = mode
    self.question = question
  }

  var shouldAsk: Bool {
    mode != .execute
  }
}

enum AgentClarificationPolicy {
  static func decide(
    goal: String,
    hasAttachments: Bool = false,
    hasConversationContext: Bool = false
  ) -> AgentClarificationDecision {
    let normalized = normalize(goal)
    if normalized.isEmpty {
      if hasAttachments {
        return AgentClarificationDecision(mode: .askWithModel, question: .fileAction)
      }
      return ask(.taskGoal)
    }
    if hasConversationContext && isContextualFollowUp(normalized) {
      return execute
    }
    if hasAttachments && vagueRequests.contains(normalized) {
      return AgentClarificationDecision(mode: .askWithModel, question: .fileAction)
    }
    if vagueRequests.contains(normalized) {
      return hasConversationContext ? execute : ask(.taskGoal)
    }
    if isQuestion(normalized) || greetings.contains(normalized) {
      return execute
    }

    let missingQuestion: AgentClarificationQuestion?
    if codeRequestsWithoutOutcome.contains(normalized) {
      missingQuestion = .codeOutcome
    } else if controlRequestsWithoutAction.contains(normalized) {
      missingQuestion = .controlAction
    } else if researchRequestsWithoutTopic.contains(normalized) {
      missingQuestion = .researchTopic
    } else if fileRequestsWithoutAction.contains(normalized) {
      missingQuestion = .fileAction
    } else if memoryRequestsWithoutContent.contains(normalized) {
      missingQuestion = .memoryContent
    } else if automationRequestsWithoutDetails.contains(normalized) {
      missingQuestion = .automationDetails
    } else {
      missingQuestion = nil
    }
    if let missingQuestion = missingQuestion, !hasConversationContext {
      return ask(missingQuestion)
    }
    return execute
  }

  private static func ask(_ question: AgentClarificationQuestion) -> AgentClarificationDecision {
    AgentClarificationDecision(mode: .askLocally, question: question)
  }

  private static func normalize(_ value: String) -> String {
    let punctuationScalars: Set<UnicodeScalar> = [
      "\u{3002}", "\u{ff0c}", "\u{ff01}", "\u{ff1f}", "\u{ff1a}",
      "\u{ff1b}", "\u{201c}", "\u{201d}", "\u{2018}", "\u{2019}"
    ]
    let mapped = value.lowercased().unicodeScalars.map { scalar -> String in
      if CharacterSet.punctuationCharacters.contains(scalar) || punctuationScalars.contains(scalar) {
        return " "
      }
      return String(scalar)
    }.joined()
    return mapped
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isQuestion(_ value: String) -> Bool {
    questionPrefixes.contains(where: value.hasPrefix) ||
      questionSuffixes.contains(where: value.hasSuffix)
  }

  private static func isContextualFollowUp(_ value: String) -> Bool {
    contextualFollowUps.contains(value) ||
      contextualReferences.contains(where: value.contains)
  }

  private static let execute = AgentClarificationDecision(mode: .execute)
  private static let greetings: Set<String> = [
    "hello", "hi", "hey", "good morning", "good afternoon", "good evening",
    "\u{4f60}\u{597d}", "\u{55e8}", "\u{65e9}\u{4e0a}\u{597d}",
    "\u{4e0b}\u{5348}\u{597d}", "\u{665a}\u{4e0a}\u{597d}"
  ]
  private static let questionPrefixes: Set<String> = [
    "what ", "why ", "how ", "when ", "where ", "which ", "who ",
    "can ", "could ", "would ", "is ", "are ", "do ", "does ",
    "\u{4ec0}\u{4e48}", "\u{4e3a}\u{4ec0}\u{4e48}", "\u{600e}\u{4e48}",
    "\u{5982}\u{4f55}", "\u{54ea}\u{4e2a}", "\u{54ea}\u{4e9b}",
    "\u{8c01}", "\u{80fd}\u{4e0d}\u{80fd}", "\u{53ef}\u{4ee5}"
  ]
  private static let questionSuffixes: Set<String> = [
    "\u{5417}", "\u{5462}", "\u{4e48}", "\u{600e}\u{4e48}\u{6837}",
    "\u{5982}\u{4f55}"
  ]
  private static let contextualFollowUps: Set<String> = [
    "continue", "go ahead", "do it", "try again", "retry", "keep going",
    "use this", "use that", "same as before", "make it better",
    "\u{7ee7}\u{7eed}", "\u{6267}\u{884c}", "\u{5c31}\u{8fd9}\u{6837}",
    "\u{6309}\u{8fd9}\u{4e2a}", "\u{518d}\u{8bd5}\u{8bd5}",
    "\u{91cd}\u{8bd5}", "\u{4fdd}\u{8bc1}\u{6b63}\u{786e}",
    "\u{7528}\u{8fd9}\u{4e2a}", "\u{548c}\u{4e4b}\u{524d}\u{4e00}\u{6837}",
    "\u{6309}\u{4e0a}\u{9762}\u{7684}\u{505a}"
  ]
  private static let contextualReferences: Set<String> = [
    " this", " that", " it", " above", " previous",
    "\u{8fd9}\u{4e2a}", "\u{90a3}\u{4e2a}", "\u{5b83}",
    "\u{4e0a}\u{9762}", "\u{4e4b}\u{524d}", "\u{521a}\u{624d}",
    "\u{524d}\u{9762}", "\u{8be5}\u{6587}\u{4ef6}", "\u{8fd9}\u{5f20}\u{56fe}"
  ]
  private static let vagueRequests: Set<String> = [
    "help me", "handle this", "do something", "take a look", "fix it",
    "improve it", "optimize it", "work on this", "please help",
    "\u{5e2e}\u{6211}", "\u{5e2e}\u{6211}\u{5f04}\u{4e00}\u{4e0b}",
    "\u{5904}\u{7406}\u{4e00}\u{4e0b}", "\u{5f04}\u{4e00}\u{4e0b}",
    "\u{770b}\u{770b}", "\u{5e2e}\u{6211}\u{770b}\u{770b}",
    "\u{4fee}\u{4e00}\u{4e0b}", "\u{4f18}\u{5316}\u{4e00}\u{4e0b}",
    "\u{6539}\u{8fdb}\u{4e00}\u{4e0b}", "\u{4f60}\u{770b}\u{7740}\u{529e}",
    "\u{7ed9}\u{6211}\u{7ed3}\u{679c}", "\u{5feb}\u{70b9}",
    "\u{4e0d}\u{884c}"
  ]
  private static let codeRequestsWithoutOutcome: Set<String> = [
    "write code", "write a program", "build an app", "create an app", "fix the code",
    "\u{5199}\u{4ee3}\u{7801}", "\u{5199}\u{4e2a}\u{7a0b}\u{5e8f}",
    "\u{5f00}\u{53d1}\u{4e00}\u{4e2a} app", "\u{505a}\u{4e00}\u{4e2a} app",
    "\u{4fee}\u{4ee3}\u{7801}"
  ]
  private static let controlRequestsWithoutAction: Set<String> = [
    "control my phone", "control the phone", "control my computer",
    "control the computer", "remote desktop",
    "\u{63a7}\u{5236}\u{624b}\u{673a}", "\u{64cd}\u{4f5c}\u{624b}\u{673a}",
    "\u{63a7}\u{5236}\u{7535}\u{8111}", "\u{64cd}\u{4f5c}\u{7535}\u{8111}",
    "\u{8fdc}\u{7a0b}\u{684c}\u{9762}"
  ]
  private static let researchRequestsWithoutTopic: Set<String> = [
    "research", "research this", "search", "search the web", "look it up",
    "\u{7814}\u{7a76}\u{4e00}\u{4e0b}", "\u{641c}\u{7d22}",
    "\u{641c}\u{4e00}\u{4e0b}", "\u{67e5}\u{4e00}\u{4e0b}",
    "\u{67e5}\u{8d44}\u{6599}"
  ]
  private static let fileRequestsWithoutAction: Set<String> = [
    "process the file", "handle the file", "work on the document",
    "\u{5904}\u{7406}\u{6587}\u{4ef6}", "\u{5904}\u{7406}\u{8fd9}\u{4e2a}\u{6587}\u{4ef6}",
    "\u{770b}\u{4e0b}\u{6587}\u{4ef6}"
  ]
  private static let memoryRequestsWithoutContent: Set<String> = [
    "remember this", "remember that", "save this to memory",
    "\u{8bb0}\u{4f4f}\u{8fd9}\u{4e2a}", "\u{8bb0}\u{4f4f}\u{8fd9}\u{4ef6}\u{4e8b}",
    "\u{5b58}\u{5230}\u{8bb0}\u{5fc6}"
  ]
  private static let automationRequestsWithoutDetails: Set<String> = [
    "create an automation", "make a workflow", "schedule a task", "remind me",
    "\u{521b}\u{5efa}\u{81ea}\u{52a8}\u{5316}", "\u{5efa}\u{4e00}\u{4e2a}\u{5de5}\u{4f5c}\u{6d41}",
    "\u{8bbe}\u{7f6e}\u{5b9a}\u{65f6}\u{4efb}\u{52a1}", "\u{63d0}\u{9192}\u{6211}"
  ]
}

enum AgentSkillCommandParser {
  static func isSaveCommand(_ value: String) -> Bool {
    let text = normalize(value)
    if text.hasPrefix("\u{4e0d}\u{8981}") || text.hasPrefix("do not ") || text.hasPrefix("don't ") {
      return false
    }
    return savePrefixes.contains(where: text.hasPrefix) ||
      savePhrases.contains(where: text.contains)
  }

  static func isUpgradeCommand(_ value: String) -> Bool {
    let text = normalize(value)
    return upgradePrefixes.contains(where: text.hasPrefix)
  }

  private static func normalize(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  }

  private static let savePrefixes: Set<String> = [
    "save as skill",
    "save this as a skill",
    "save this method",
    "remember this method",
    "\u{4fdd}\u{5b58}\u{6210}skill",
    "\u{4fdd}\u{5b58}\u{6210} skill",
    "\u{4fdd}\u{5b58}\u{4e3a}skill",
    "\u{4fdd}\u{5b58}\u{4e3a} skill",
    "\u{628a}\u{8fd9}\u{4e2a}\u{4fdd}\u{5b58}\u{4e3a}skill",
    "\u{628a}\u{8fd9}\u{4e2a}\u{4fdd}\u{5b58}\u{4e3a} skill",
    "\u{628a}\u{521a}\u{624d}\u{7684}\u{65b9}\u{6cd5}\u{4fdd}\u{5b58}\u{4e0b}\u{6765}",
    "\u{4ee5}\u{540e}\u{6309}\u{8fd9}\u{4e2a}\u{65b9}\u{5f0f}\u{6267}\u{884c}"
  ]

  private static let savePhrases: Set<String> = [
    "\u{628a}\u{8fd9}\u{4e2a}\u{4fdd}\u{5b58}\u{6210}skill",
    "\u{628a}\u{8fd9}\u{4e2a}\u{4fdd}\u{5b58}\u{6210} skill"
  ]

  private static let upgradePrefixes: Set<String> = [
    "upgrade skill",
    "upgrade this skill",
    "improve this skill",
    "\u{5347}\u{7ea7}skill",
    "\u{5347}\u{7ea7} skill",
    "\u{5347}\u{7ea7}\u{8fd9}\u{4e2a}skill",
    "\u{5347}\u{7ea7}\u{8fd9}\u{4e2a} skill",
    "\u{6539}\u{8fdb}\u{8fd9}\u{4e2a}skill",
    "\u{6539}\u{8fdb}\u{8fd9}\u{4e2a} skill"
  ]
}

struct GlobalAgentSettings: Codable, Equatable {
  var enabled: Bool
  var proactiveInsightsEnabled: Bool
  var proactiveDiscoveryEnabled: Bool
  var modelUnderstandingEnabled: Bool
  var autonomousPreparationEnabled: Bool
  var autonomousToolExecutionEnabled: Bool
  var dynamicAutonomousReplanningEnabled: Bool
  var longHorizonPlanningEnabled: Bool
  var maxAutonomousReplans: Int
  var allowCloudCognition: Bool
  var autonomousResearchEnabled: Bool
  var autoCreateConversationsEnabled: Bool
  var notificationsEnabled: Bool
  var adaptiveLearningEnabled: Bool
  var protectBatteryForBackgroundWork: Bool
  var allowMeteredBackgroundResearch: Bool
  var dailyBackgroundModelCallBudget: Int
  var maxConcurrentBackgroundModelCalls: Int
  var dailyBackgroundTokenBudget: Int64
  var dailyBackgroundReportedCostBudgetMicros: Int64
  var dailyMessageBudget: Int
  var dailyDiscoveryTaskBudget: Int
  var topicCooldownMillis: Int64
  var discoveryIntervalMillis: Int64
  var monitorIntervalMillis: Int64

  static let `default` = GlobalAgentSettings()

  init(
    enabled: Bool = true,
    proactiveInsightsEnabled: Bool = true,
    proactiveDiscoveryEnabled: Bool = true,
    modelUnderstandingEnabled: Bool = true,
    autonomousPreparationEnabled: Bool = true,
    autonomousToolExecutionEnabled: Bool = true,
    dynamicAutonomousReplanningEnabled: Bool = true,
    longHorizonPlanningEnabled: Bool = true,
    maxAutonomousReplans: Int = 3,
    allowCloudCognition: Bool = false,
    autonomousResearchEnabled: Bool = true,
    autoCreateConversationsEnabled: Bool = true,
    notificationsEnabled: Bool = true,
    adaptiveLearningEnabled: Bool = true,
    protectBatteryForBackgroundWork: Bool = true,
    allowMeteredBackgroundResearch: Bool = false,
    dailyBackgroundModelCallBudget: Int = 48,
    maxConcurrentBackgroundModelCalls: Int = 3,
    dailyBackgroundTokenBudget: Int64 = 250_000,
    dailyBackgroundReportedCostBudgetMicros: Int64 = 1_000_000,
    dailyMessageBudget: Int = 4,
    dailyDiscoveryTaskBudget: Int = 3,
    topicCooldownMillis: Int64 = 6 * 60 * 60 * 1_000,
    discoveryIntervalMillis: Int64 = 6 * 60 * 60 * 1_000,
    monitorIntervalMillis: Int64 = 24 * 60 * 60 * 1_000
  ) {
    self.enabled = enabled
    self.proactiveInsightsEnabled = proactiveInsightsEnabled
    self.proactiveDiscoveryEnabled = proactiveDiscoveryEnabled
    self.modelUnderstandingEnabled = modelUnderstandingEnabled
    self.autonomousPreparationEnabled = autonomousPreparationEnabled
    self.autonomousToolExecutionEnabled = autonomousToolExecutionEnabled
    self.dynamicAutonomousReplanningEnabled = dynamicAutonomousReplanningEnabled
    self.longHorizonPlanningEnabled = longHorizonPlanningEnabled
    self.maxAutonomousReplans = max(0, min(maxAutonomousReplans, 24))
    self.allowCloudCognition = allowCloudCognition
    self.autonomousResearchEnabled = autonomousResearchEnabled
    self.autoCreateConversationsEnabled = autoCreateConversationsEnabled
    self.notificationsEnabled = notificationsEnabled
    self.adaptiveLearningEnabled = adaptiveLearningEnabled
    self.protectBatteryForBackgroundWork = protectBatteryForBackgroundWork
    self.allowMeteredBackgroundResearch = allowMeteredBackgroundResearch
    self.dailyBackgroundModelCallBudget = max(0, min(dailyBackgroundModelCallBudget, 1_000))
    self.maxConcurrentBackgroundModelCalls = max(1, min(maxConcurrentBackgroundModelCalls, 24))
    self.dailyBackgroundTokenBudget = max(0, min(dailyBackgroundTokenBudget, 100_000_000))
    self.dailyBackgroundReportedCostBudgetMicros = max(0, min(dailyBackgroundReportedCostBudgetMicros, 1_000_000_000))
    self.dailyMessageBudget = max(0, min(dailyMessageBudget, 200))
    self.dailyDiscoveryTaskBudget = max(0, min(dailyDiscoveryTaskBudget, 200))
    self.topicCooldownMillis = max(0, min(topicCooldownMillis, 30 * 24 * 60 * 60 * 1_000))
    self.discoveryIntervalMillis = max(60_000, min(discoveryIntervalMillis, 30 * 24 * 60 * 60 * 1_000))
    self.monitorIntervalMillis = max(60_000, min(monitorIntervalMillis, 30 * 24 * 60 * 60 * 1_000))
  }

  enum CodingKeys: String, CodingKey {
    case enabled
    case proactiveInsightsEnabled = "proactive_insights_enabled"
    case proactiveDiscoveryEnabled = "proactive_discovery_enabled"
    case modelUnderstandingEnabled = "model_understanding_enabled"
    case autonomousPreparationEnabled = "autonomous_preparation_enabled"
    case autonomousToolExecutionEnabled = "autonomous_tool_execution_enabled"
    case dynamicAutonomousReplanningEnabled = "dynamic_autonomous_replanning_enabled"
    case longHorizonPlanningEnabled = "long_horizon_planning_enabled"
    case maxAutonomousReplans = "max_autonomous_replans"
    case allowCloudCognition = "allow_cloud_cognition"
    case autonomousResearchEnabled = "autonomous_research_enabled"
    case autoCreateConversationsEnabled = "auto_create_conversations_enabled"
    case notificationsEnabled = "notifications_enabled"
    case adaptiveLearningEnabled = "adaptive_learning_enabled"
    case protectBatteryForBackgroundWork = "protect_battery_for_background_work"
    case allowMeteredBackgroundResearch = "allow_metered_background_research"
    case dailyBackgroundModelCallBudget = "daily_background_model_call_budget"
    case maxConcurrentBackgroundModelCalls = "max_concurrent_background_model_calls"
    case dailyBackgroundTokenBudget = "daily_background_token_budget"
    case dailyBackgroundReportedCostBudgetMicros = "daily_background_reported_cost_budget_micros"
    case dailyMessageBudget = "daily_message_budget"
    case dailyDiscoveryTaskBudget = "daily_discovery_task_budget"
    case topicCooldownMillis = "topic_cooldown_millis"
    case discoveryIntervalMillis = "discovery_interval_millis"
    case monitorIntervalMillis = "monitor_interval_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let fallback = Self.default
    self.init(
      enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? fallback.enabled,
      proactiveInsightsEnabled: try container.decodeIfPresent(Bool.self, forKey: .proactiveInsightsEnabled) ?? fallback.proactiveInsightsEnabled,
      proactiveDiscoveryEnabled: try container.decodeIfPresent(Bool.self, forKey: .proactiveDiscoveryEnabled) ?? fallback.proactiveDiscoveryEnabled,
      modelUnderstandingEnabled: try container.decodeIfPresent(Bool.self, forKey: .modelUnderstandingEnabled) ?? fallback.modelUnderstandingEnabled,
      autonomousPreparationEnabled: try container.decodeIfPresent(Bool.self, forKey: .autonomousPreparationEnabled) ?? fallback.autonomousPreparationEnabled,
      autonomousToolExecutionEnabled: try container.decodeIfPresent(Bool.self, forKey: .autonomousToolExecutionEnabled) ?? fallback.autonomousToolExecutionEnabled,
      dynamicAutonomousReplanningEnabled: try container.decodeIfPresent(Bool.self, forKey: .dynamicAutonomousReplanningEnabled) ?? fallback.dynamicAutonomousReplanningEnabled,
      longHorizonPlanningEnabled: try container.decodeIfPresent(Bool.self, forKey: .longHorizonPlanningEnabled) ?? fallback.longHorizonPlanningEnabled,
      maxAutonomousReplans: try container.decodeIfPresent(Int.self, forKey: .maxAutonomousReplans) ?? fallback.maxAutonomousReplans,
      allowCloudCognition: try container.decodeIfPresent(Bool.self, forKey: .allowCloudCognition) ?? fallback.allowCloudCognition,
      autonomousResearchEnabled: try container.decodeIfPresent(Bool.self, forKey: .autonomousResearchEnabled) ?? fallback.autonomousResearchEnabled,
      autoCreateConversationsEnabled: try container.decodeIfPresent(Bool.self, forKey: .autoCreateConversationsEnabled) ?? fallback.autoCreateConversationsEnabled,
      notificationsEnabled: try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? fallback.notificationsEnabled,
      adaptiveLearningEnabled: try container.decodeIfPresent(Bool.self, forKey: .adaptiveLearningEnabled) ?? fallback.adaptiveLearningEnabled,
      protectBatteryForBackgroundWork: try container.decodeIfPresent(Bool.self, forKey: .protectBatteryForBackgroundWork) ?? fallback.protectBatteryForBackgroundWork,
      allowMeteredBackgroundResearch: try container.decodeIfPresent(Bool.self, forKey: .allowMeteredBackgroundResearch) ?? fallback.allowMeteredBackgroundResearch,
      dailyBackgroundModelCallBudget: try container.decodeIfPresent(Int.self, forKey: .dailyBackgroundModelCallBudget) ?? fallback.dailyBackgroundModelCallBudget,
      maxConcurrentBackgroundModelCalls: try container.decodeIfPresent(Int.self, forKey: .maxConcurrentBackgroundModelCalls) ?? fallback.maxConcurrentBackgroundModelCalls,
      dailyBackgroundTokenBudget: try container.decodeIfPresent(Int64.self, forKey: .dailyBackgroundTokenBudget) ?? fallback.dailyBackgroundTokenBudget,
      dailyBackgroundReportedCostBudgetMicros: try container.decodeIfPresent(Int64.self, forKey: .dailyBackgroundReportedCostBudgetMicros) ?? fallback.dailyBackgroundReportedCostBudgetMicros,
      dailyMessageBudget: try container.decodeIfPresent(Int.self, forKey: .dailyMessageBudget) ?? fallback.dailyMessageBudget,
      dailyDiscoveryTaskBudget: try container.decodeIfPresent(Int.self, forKey: .dailyDiscoveryTaskBudget) ?? fallback.dailyDiscoveryTaskBudget,
      topicCooldownMillis: try container.decodeIfPresent(Int64.self, forKey: .topicCooldownMillis) ?? fallback.topicCooldownMillis,
      discoveryIntervalMillis: try container.decodeIfPresent(Int64.self, forKey: .discoveryIntervalMillis) ?? fallback.discoveryIntervalMillis,
      monitorIntervalMillis: try container.decodeIfPresent(Int64.self, forKey: .monitorIntervalMillis) ?? fallback.monitorIntervalMillis
    )
  }
}
