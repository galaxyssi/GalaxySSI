import BackgroundTasks
import Foundation
import UIKit

enum AgentWorkflowTriggerKind: String, Codable, CaseIterable, Identifiable {
  case notificationPackage = "NOTIFICATION_PACKAGE"
  case notificationText = "NOTIFICATION_TEXT"
  case powerConnected = "POWER_CONNECTED"
  case batteryLow = "BATTERY_LOW"

  var id: String { rawValue }

  var supportedOnIOS: Bool {
    true
  }

  var requiresCondition: Bool {
    self == .notificationPackage || self == .notificationText
  }
}

struct AgentWorkflowTrigger: Codable, Equatable, Identifiable {
  static let maxIdentifierCharacters = 128
  static let maxWorkflowNameCharacters = 80
  static let maxConditionCharacters = 240
  static let maxAdditionalConditions = 32
  static let maxCooldownMinutes = 7 * 24 * 60

  var id: String
  var workflowId: String
  var workflowName: String
  var kind: AgentWorkflowTriggerKind
  var condition: String
  var enabled: Bool
  var cooldownMinutes: Int
  var lastTriggeredAtMillis: Int64
  var createdAtMillis: Int64
  var conditions: [AgentWorkflowCondition]

  init(
    id: String = UUID().uuidString.lowercased(),
    workflowId: String,
    workflowName: String,
    kind: AgentWorkflowTriggerKind,
    condition: String = "",
    enabled: Bool = true,
    cooldownMinutes: Int = 5,
    lastTriggeredAtMillis: Int64 = 0,
    createdAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
    conditions: [AgentWorkflowCondition] = []
  ) throws {
    let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanWorkflowId = workflowId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanWorkflowName = workflowName.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanCondition = condition.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanId.isEmpty && cleanId.count <= Self.maxIdentifierCharacters,
      !cleanWorkflowId.isEmpty && cleanWorkflowId.count <= Self.maxIdentifierCharacters,
      !cleanWorkflowName.isEmpty && cleanWorkflowName.count <= Self.maxWorkflowNameCharacters,
      cleanCondition.count <= Self.maxConditionCharacters,
      !kind.requiresCondition || !cleanCondition.isEmpty,
      (1...Self.maxCooldownMinutes).contains(cooldownMinutes),
      conditions.count <= Self.maxAdditionalConditions,
      lastTriggeredAtMillis >= 0,
      createdAtMillis >= 0 else {
      throw AgentProactiveTaskError.invalid("Workflow trigger fields are invalid")
    }
    for condition in conditions {
      try condition.validate()
    }
    self.id = cleanId
    self.workflowId = cleanWorkflowId
    self.workflowName = cleanWorkflowName
    self.kind = kind
    self.condition = cleanCondition
    self.enabled = enabled
    self.cooldownMinutes = cooldownMinutes
    self.lastTriggeredAtMillis = lastTriggeredAtMillis
    self.createdAtMillis = createdAtMillis
    self.conditions = conditions
  }

  enum CodingKeys: String, CodingKey {
    case id
    case workflowId = "workflow_id"
    case workflowName = "workflow_name"
    case kind
    case condition
    case enabled
    case cooldownMinutes = "cooldown_minutes"
    case lastTriggeredAtMillis = "last_triggered_at"
    case createdAtMillis = "created_at"
    case conditions
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: try container.decode(String.self, forKey: .id),
      workflowId: try container.decode(String.self, forKey: .workflowId),
      workflowName: try container.decode(String.self, forKey: .workflowName),
      kind: try container.decode(AgentWorkflowTriggerKind.self, forKey: .kind),
      condition: try container.decodeIfPresent(String.self, forKey: .condition) ?? "",
      enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
      cooldownMinutes: try container.decodeIfPresent(Int.self, forKey: .cooldownMinutes) ?? 5,
      lastTriggeredAtMillis: try container.decodeIfPresent(Int64.self, forKey: .lastTriggeredAtMillis) ?? 0,
      createdAtMillis: try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? 0,
      conditions: try container.decodeIfPresent([AgentWorkflowCondition].self, forKey: .conditions) ?? []
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(workflowId, forKey: .workflowId)
    try container.encode(workflowName, forKey: .workflowName)
    try container.encode(kind, forKey: .kind)
    try container.encode(condition, forKey: .condition)
    try container.encode(enabled, forKey: .enabled)
    try container.encode(cooldownMinutes, forKey: .cooldownMinutes)
    try container.encode(lastTriggeredAtMillis, forKey: .lastTriggeredAtMillis)
    try container.encode(createdAtMillis, forKey: .createdAtMillis)
    try container.encode(conditions, forKey: .conditions)
  }
}

@MainActor
final class UserDefaultsAgentWorkflowTriggerStore: ObservableObject {
  static let shared = UserDefaultsAgentWorkflowTriggerStore()
  static let maxItems = 100
  static let storageKey = "galaxyssi_agent_workflow_triggers"

  @Published private(set) var triggers: [AgentWorkflowTrigger]
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.triggers = Self.load(defaults: defaults)
  }

  func list() -> [AgentWorkflowTrigger] {
    triggers.sorted { left, right in
      if left.createdAtMillis != right.createdAtMillis {
        return left.createdAtMillis > right.createdAtMillis
      }
      return left.id > right.id
    }
  }

  func findById(_ id: String) -> AgentWorkflowTrigger? {
    let clean = id.trimmingCharacters(in: .whitespacesAndNewlines)
    return triggers.first { $0.id == clean }
  }

  @discardableResult
  func upsert(_ trigger: AgentWorkflowTrigger) throws -> AgentWorkflowTrigger {
    let normalized = try AgentWorkflowTrigger(
      id: trigger.id,
      workflowId: trigger.workflowId,
      workflowName: trigger.workflowName,
      kind: trigger.kind,
      condition: trigger.condition,
      enabled: trigger.enabled,
      cooldownMinutes: trigger.cooldownMinutes,
      lastTriggeredAtMillis: trigger.lastTriggeredAtMillis,
      createdAtMillis: trigger.createdAtMillis,
      conditions: trigger.conditions
    )
    triggers.removeAll { $0.id == normalized.id || Self.identity($0) == Self.identity(normalized) }
    triggers = Array((triggers + [normalized]).suffix(Self.maxItems))
    persist()
    return normalized
  }

  func setEnabled(id: String, enabled: Bool) -> Bool {
    guard let index = triggers.firstIndex(where: { $0.id == id }) else { return false }
    triggers[index].enabled = enabled
    persist()
    return true
  }

  func markTriggered(id: String, at timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)) {
    guard let index = triggers.firstIndex(where: { $0.id == id }) else { return }
    triggers[index].lastTriggeredAtMillis = max(timestampMillis, 0)
    persist()
  }

  @discardableResult
  func delete(id: String) -> Bool {
    let before = triggers.count
    triggers.removeAll { $0.id == id }
    guard before != triggers.count else { return false }
    persist()
    return true
  }

  @discardableResult
  func deleteForWorkflow(_ workflowId: String) -> Int {
    let before = triggers.count
    triggers.removeAll { $0.workflowId == workflowId }
    guard before != triggers.count else { return 0 }
    persist()
    return before - triggers.count
  }

  func replaceAll(_ incoming: [AgentWorkflowTrigger]) throws {
    triggers = []
    for trigger in incoming where trigger.kind.supportedOnIOS {
      _ = try upsert(trigger)
    }
  }

  func clear() {
    triggers = []
    defaults.removeObject(forKey: Self.storageKey)
  }

  func readyTriggers(kind: AgentWorkflowTriggerKind, nowMillis: Int64) -> [AgentWorkflowTrigger] {
    list().filter { trigger in
      guard trigger.enabled, trigger.kind == kind else { return false }
      guard trigger.lastTriggeredAtMillis > 0 else { return true }
      guard nowMillis >= trigger.lastTriggeredAtMillis else { return false }
      return nowMillis - trigger.lastTriggeredAtMillis >= Int64(trigger.cooldownMinutes) * 60_000
    }
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(triggers) else { return }
    defaults.set(data, forKey: Self.storageKey)
  }

  private static func load(defaults: UserDefaults) -> [AgentWorkflowTrigger] {
    guard let data = defaults.data(forKey: storageKey),
      let decoded = try? JSONDecoder().decode([AgentWorkflowTrigger].self, from: data) else {
      return []
    }
    var unique: [AgentWorkflowTrigger] = []
    for trigger in decoded.suffix(maxItems) {
      guard trigger.kind.supportedOnIOS else { continue }
      guard !unique.contains(where: { $0.id == trigger.id || identity($0) == identity(trigger) }) else {
        continue
      }
      unique.append(trigger)
    }
    return unique
  }

  private static func identity(_ trigger: AgentWorkflowTrigger) -> String {
    "\(trigger.workflowId)|\(trigger.kind.rawValue)|\(trigger.condition.lowercased())"
  }
}

@MainActor
final class AgentWorkflowTriggerCoordinator: ObservableObject {
  static let backgroundTaskIdentifier = "com.galaxyssi.chat.ios.workflow-trigger-refresh"

  private let triggerStore: UserDefaultsAgentWorkflowTriggerStore
  private let workflowStore: UserDefaultsAgentWorkflowStore
  private let coordinator: MessageCoordinator
  private let stateDefaults = UserDefaults.standard
  private var observations: [NSObjectProtocol] = []
  private var chargingState: Bool?
  private var lowBatteryState: Bool?
  private var registered = false

  init(
    triggerStore: UserDefaultsAgentWorkflowTriggerStore = .shared,
    workflowStore: UserDefaultsAgentWorkflowStore = .shared,
    coordinator: MessageCoordinator
  ) {
    self.triggerStore = triggerStore
    self.workflowStore = workflowStore
    self.coordinator = coordinator
  }

  func start() {
    guard observations.isEmpty else { return }
    let device = UIDevice.current
    device.isBatteryMonitoringEnabled = true
    registerBackgroundTaskIfNeeded()
    let currentCharging = Self.isCharging(device.batteryState)
    let currentLowBattery = Self.isLowBattery(device.batteryLevel)
    chargingState = stateDefaults.object(forKey: Self.chargingStateKey) as? Bool ?? currentCharging
    lowBatteryState = stateDefaults.object(forKey: Self.lowBatteryStateKey) as? Bool ?? currentLowBattery
    persistDeviceState(charging: currentCharging, lowBattery: currentLowBattery)
    let center = NotificationCenter.default
    for name in [
      UIDevice.batteryStateDidChangeNotification,
      UIDevice.batteryLevelDidChangeNotification
    ] {
      observations.append(center.addObserver(forName: name, object: device, queue: .main) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.refreshDeviceState()
        }
      })
    }
    observations.append(center.addObserver(
      forName: AgentIOSOwnedNotificationStore.didRecordNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let item = notification.object as? AgentIOSNotificationItem else { return }
      Task { @MainActor [weak self] in
        self?.dispatchNotification(item)
      }
    })
    scheduleBackgroundRefresh()
  }

  func stop() {
    let center = NotificationCenter.default
    observations.forEach(center.removeObserver)
    observations.removeAll()
    UIDevice.current.isBatteryMonitoringEnabled = false
  }

  private func refreshDeviceState() {
    let device = UIDevice.current
    let charging = Self.isCharging(device.batteryState)
    let lowBattery = Self.isLowBattery(device.batteryLevel)
    if charging && chargingState == false {
      dispatch(.powerConnected)
    }
    if lowBattery && lowBatteryState == false {
      dispatch(.batteryLow)
    }
    chargingState = charging
    lowBatteryState = lowBattery
    persistDeviceState(charging: charging, lowBattery: lowBattery)
    scheduleBackgroundRefresh()
  }

  private func registerBackgroundTaskIfNeeded() {
    guard !registered else { return }
    registered = true
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: Self.backgroundTaskIdentifier,
      using: nil
    ) { [weak self] task in
      Task { @MainActor [weak self] in
        guard let self else {
          task.setTaskCompleted(success: false)
          return
        }
        task.expirationHandler = { }
        self.refreshDeviceState()
        task.setTaskCompleted(success: true)
        self.scheduleBackgroundRefresh()
      }
    }
  }

  private func scheduleBackgroundRefresh() {
    guard registered else { return }
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
    let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    try? BGTaskScheduler.shared.submit(request)
  }

  private func persistDeviceState(charging: Bool, lowBattery: Bool) {
    stateDefaults.set(charging, forKey: Self.chargingStateKey)
    stateDefaults.set(lowBattery, forKey: Self.lowBatteryStateKey)
  }

  private func dispatch(_ kind: AgentWorkflowTriggerKind) {
    let now = Int64(Date().timeIntervalSince1970 * 1_000)
    let snapshot = conditionSnapshot(nowMillis: now)
    for trigger in triggerStore.readyTriggers(kind: kind, nowMillis: now)
      where AgentWorkflowConditionEvaluator.evaluateAll(trigger.conditions, snapshot: snapshot) {
      triggerStore.markTriggered(id: trigger.id, at: now)
      Task { @MainActor [weak self] in
        guard let self else { return }
        _ = await self.coordinator.executeWorkflowTrigger(trigger, workflowStore: self.workflowStore)
      }
    }
  }

  private func dispatchNotification(_ item: AgentIOSNotificationItem) {
    let now = Int64(Date().timeIntervalSince1970 * 1_000)
    let notificationText = String([item.title, item.textPreview]
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
      .prefix(4_096))
    let snapshot = conditionSnapshot(
      nowMillis: now,
      text: notificationText,
      packageName: String(item.packageName.prefix(512))
    )
    for trigger in triggerStore.readyTriggers(kind: .notificationPackage, nowMillis: now)
      where item.packageName.range(of: trigger.condition, options: [.caseInsensitive]) != nil &&
        AgentWorkflowConditionEvaluator.evaluateAll(trigger.conditions, snapshot: snapshot) {
      dispatch(trigger, now: now)
    }
    guard item.sensitiveFlags.isEmpty else { return }
    for trigger in triggerStore.readyTriggers(kind: .notificationText, nowMillis: now)
      where notificationText.range(of: trigger.condition, options: [.caseInsensitive]) != nil &&
        AgentWorkflowConditionEvaluator.evaluateAll(trigger.conditions, snapshot: snapshot) {
      dispatch(trigger, now: now)
    }
  }

  private func dispatch(_ trigger: AgentWorkflowTrigger, now: Int64) {
    triggerStore.markTriggered(id: trigger.id, at: now)
    Task { @MainActor [weak self] in
      guard let self else { return }
      _ = await self.coordinator.executeWorkflowTrigger(trigger, workflowStore: self.workflowStore)
    }
  }

  private func conditionSnapshot(
    nowMillis: Int64,
    text: String? = nil,
    packageName: String? = nil
  ) -> AgentWorkflowConditionSnapshot {
    let device = UIDevice.current
    let batteryPercent: Int? = device.batteryLevel >= 0
      ? min(max(Int(device.batteryLevel * 100), 0), 100)
      : nil
    let charging: Bool?
    switch device.batteryState {
    case .charging, .full:
      charging = true
    case .unplugged:
      charging = false
    case .unknown:
      charging = nil
    @unknown default:
      charging = nil
    }
    let probe = AgentMediaNetworkDetector.shared.currentProbe
    let networkAvailable = probe.networkPresent && probe.internetCapable && probe.validated
    let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: Double(nowMillis) / 1_000))
    let minuteOfDay = components.hour.map { $0 * 60 + (components.minute ?? 0) }
    return AgentWorkflowConditionSnapshot(
      text: text,
      packageName: packageName,
      isDeviceCharging: charging,
      batteryPercent: batteryPercent,
      isNetworkAvailable: networkAvailable,
      minuteOfDay: minuteOfDay
    )
  }

  private static func isCharging(_ state: UIDevice.BatteryState) -> Bool {
    state == .charging || state == .full
  }

  private static func isLowBattery(_ level: Float) -> Bool {
    level >= 0 && level <= 0.15
  }

  private static let chargingStateKey = "galaxyssi_agent_workflow_trigger_charging"
  private static let lowBatteryStateKey = "galaxyssi_agent_workflow_trigger_battery_low"
}
