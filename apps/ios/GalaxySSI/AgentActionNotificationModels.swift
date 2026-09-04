import Foundation

enum AgentActionNotificationPhase: String, Codable, CaseIterable, Identifiable {
  case running = "RUNNING"
  case succeeded = "SUCCEEDED"
  case failed = "FAILED"

  var id: String { rawValue }
}

enum AgentActionNotificationCategory: String, Codable, CaseIterable, Identifiable {
  case progress = "PROGRESS"
  case status = "STATUS"
  case error = "ERROR"

  var id: String { rawValue }
}

enum AgentActionNotificationDestination: String, Codable, CaseIterable, Identifiable {
  case mainApp = "MAIN_APP"
  case timers = "TIMERS"

  var id: String { rawValue }
}

struct AgentActionNotification: Codable, Equatable, Identifiable {
  var notificationId: Int
  var actionId: String
  var taskId: String
  var phase: AgentActionNotificationPhase
  var title: String
  var detail: String
  var category: AgentActionNotificationCategory
  var destination: AgentActionNotificationDestination
  var privateText: String
  var ongoing: Bool
  var successful: Bool?
  var createdAtMillis: Int64

  var id: Int { notificationId }

  init(
    notificationId: Int,
    actionId: String,
    taskId: String,
    phase: AgentActionNotificationPhase,
    title: String,
    detail: String,
    category: AgentActionNotificationCategory,
    destination: AgentActionNotificationDestination,
    privateText: String = AgentActionNotificationPolicy.defaultPrivateText,
    ongoing: Bool,
    successful: Bool? = nil,
    createdAtMillis: Int64 = 0
  ) {
    self.notificationId = notificationId
    self.actionId = Self.clean(actionId)
    self.taskId = Self.clean(taskId)
    self.phase = phase
    self.title = String(Self.clean(title).prefix(Self.maximumTitleCharacters))
    self.detail = String(Self.clean(detail).prefix(Self.maximumDetailCharacters))
    self.category = category
    self.destination = destination
    self.privateText = String(Self.clean(privateText).prefix(Self.maximumDetailCharacters))
    self.ongoing = ongoing
    self.successful = successful
    self.createdAtMillis = max(createdAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case notificationId = "notification_id"
    case actionId = "action_id"
    case taskId = "task_id"
    case phase
    case title
    case detail
    case category
    case destination
    case privateText = "private_text"
    case ongoing
    case successful = "successful"
    case createdAtMillis = "created_at_millis"
  }

  static let maximumTitleCharacters = 160
  static let maximumDetailCharacters = 160

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

protocol AgentActionNotificationPublishing: AnyObject {
  func publish(_ notification: AgentActionNotification)
}

final class InMemoryAgentActionNotificationPublisher: AgentActionNotificationPublishing {
  private let lock = NSRecursiveLock()
  private var values: [AgentActionNotification] = []

  func publish(_ notification: AgentActionNotification) {
    lock.lock()
    values.append(notification)
    lock.unlock()
  }

  func notifications() -> [AgentActionNotification] {
    lock.lock()
    defer { lock.unlock() }
    return values
  }

  func clear() {
    lock.lock()
    values.removeAll()
    lock.unlock()
  }
}

final class AgentActionNotificationCenter {
  private let publisher: AgentActionNotificationPublishing
  private let nowMillis: () -> Int64

  init(
    publisher: AgentActionNotificationPublishing,
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.publisher = publisher
    self.nowMillis = nowMillis
  }

  func showRunning(action: AgentAction) {
    publisher.publish(AgentActionNotificationPolicy.runningNotification(
      for: action,
      nowMillis: nowMillis()
    ))
  }

  func showResult(action: AgentAction, result: AgentActionResult) {
    publisher.publish(AgentActionNotificationPolicy.resultNotification(
      for: action,
      result: result,
      nowMillis: nowMillis()
    ))
  }
}

final class NotifyingAgentActionExecutor: AgentActionExecutor {
  private let delegate: AgentActionExecutor
  private let notifications: AgentActionNotificationCenter

  init(
    delegate: AgentActionExecutor,
    notifications: AgentActionNotificationCenter
  ) {
    self.delegate = delegate
    self.notifications = notifications
  }

  func execute(action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
    guard AgentActionNotificationPolicy.shouldPublish(for: action) else {
      return delegate.execute(action: action, screen: screen)
    }
    notifications.showRunning(action: action)
    let result = delegate.execute(action: action, screen: screen)
    notifications.showResult(action: action, result: result)
    return result
  }
}

enum AgentActionNotificationPolicy {
  static let channelId = "galaxyssi_phone_operations"
  static let defaultPrivateText = "GalaxySSI is performing a private Agent operation."
  static let runningText = "Running"
  static let successText = "Succeeded"
  static let failureText = "Failed"
  static let notificationIdBase = 52_000
  static let notificationIdRange = 10_000

  static func shouldPublish(for action: AgentAction) -> Bool {
    !excludedKinds.contains(action.kind)
  }

  static func runningNotification(
    for action: AgentAction,
    nowMillis: Int64
  ) -> AgentActionNotification {
    AgentActionNotification(
      notificationId: notificationId(for: action),
      actionId: action.id,
      taskId: taskId(for: action),
      phase: .running,
      title: operationTitle(for: action),
      detail: runningText,
      category: .progress,
      destination: destination(for: action),
      ongoing: true,
      createdAtMillis: nowMillis
    )
  }

  static func resultNotification(
    for action: AgentAction,
    result: AgentActionResult,
    nowMillis: Int64
  ) -> AgentActionNotification {
    let successful = result.success
    return AgentActionNotification(
      notificationId: notificationId(for: action),
      actionId: action.id,
      taskId: taskId(for: action),
      phase: successful ? .succeeded : .failed,
      title: operationTitle(for: action),
      detail: resultDetail(result),
      category: successful ? .status : .error,
      destination: destination(for: action),
      ongoing: false,
      successful: successful,
      createdAtMillis: nowMillis
    )
  }

  static func notificationId(for action: AgentAction) -> Int {
    notificationIdBase + stablePositiveModulo(javaStringHash(taskId(for: action)), notificationIdRange)
  }

  static func taskId(for action: AgentAction) -> String {
    let taskId = clean(action.parameters["_galaxyssi_task_id"] ?? "")
    return taskId.isEmpty ? clean(action.id) : taskId
  }

  static func destination(for action: AgentAction) -> AgentActionNotificationDestination {
    if action.kind == .setAlarm,
      Int(clean(action.parameters["timer_seconds"] ?? "")) != nil {
      return .timers
    }
    return .mainApp
  }

  static func operationTitle(for action: AgentAction) -> String {
    let timerSeconds = Int(clean(action.parameters["timer_seconds"] ?? ""))
    let hour = Int(clean(action.parameters["hour"] ?? ""))
    let minute = Int(clean(action.parameters["minute"] ?? ""))
    let value = searchValue(action)
    if let timerSeconds, timerSeconds % 60 == 0 {
      return "Timer \(timerSeconds / 60)m"
    }
    if let timerSeconds {
      return "Timer \(timerSeconds)s"
    }
    if action.kind == .setAlarm, let hour, let minute {
      return String(format: "Alarm %02d:%02d", hour, minute)
    }
    if action.kind == .setAlarm {
      return "Alarm"
    }
    if value.contains("camera") || value.contains("photo") {
      return "Camera"
    }
    if value.contains("flashlight") || value.contains("torch") {
      return flashlightDisabled(in: value) ? "Flashlight off" : "Flashlight"
    }
    if value.contains("volume") || value.contains("audio mute") {
      return "Volume"
    }
    if value.contains("battery") {
      return "Battery"
    }
    if value.contains("device status") {
      return "Device status"
    }
    if action.kind == .openApp {
      let target = clean(action.target).ifBlank(clean(action.description))
      return target.isEmpty ? "Open app" : "Open \(target)"
    }
    return clean(action.description)
      .ifBlank(clean(action.target))
      .ifBlank(action.kind.rawValue)
  }

  private static func resultDetail(_ result: AgentActionResult) -> String {
    if result.success {
      return successText
    }
    return clean(result.message).ifBlank(failureText)
  }

  private static func searchValue(_ action: AgentAction) -> String {
    var parts = [
      action.id,
      action.target,
      action.description
    ]
    for key in action.parameters.keys.sorted() {
      parts.append(key)
      parts.append(action.parameters[key] ?? "")
    }
    return parts.joined(separator: " ").lowercased()
  }

  private static func flashlightDisabled(in value: String) -> Bool {
    value.contains(#""enabled":false"#) ||
      value.contains("enabled false") ||
      value.contains("enabled=false")
  }

  private static func javaStringHash(_ value: String) -> Int32 {
    var hash: Int32 = 0
    for unit in value.utf16 {
      hash = hash &* 31 &+ Int32(unit)
    }
    return hash
  }

  private static func stablePositiveModulo(_ value: Int32, _ divisor: Int) -> Int {
    let remainder = Int(value % Int32(divisor))
    return abs(remainder)
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static let excludedKinds: Set<AgentActionKind> = [
    .draftPlan,
    .callConnector,
    .createNotification
  ]
}
