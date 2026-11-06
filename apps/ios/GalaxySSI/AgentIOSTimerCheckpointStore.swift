import Foundation
import UserNotifications

struct AgentIOSTimerCheckpoint: Codable, Equatable {
  enum State: String, Codable, Equatable {
    case scheduling, scheduled, pausing, paused, cancelling, cancelled, failed
  }

  let id: UUID
  let sourceTurnId: String
  let durationSeconds: Int
  var deadlineMillis: Int64
  var state: State
  var generation: UUID? = nil
  var frozenMillis: Int64? = nil
  var replacedOperationId: UUID? = nil
  var label: String? = nil
  var lastControlTurnId: String? = nil

  var notificationId: String { "galaxyssi.timer.\(id.uuidString)" + (generation.map { ".\($0.uuidString)" } ?? "") }

  func evidence(now: Int64) -> [String: String] {
    let remaining = state == .paused ? (frozenMillis ?? 0) : max(0, deadlineMillis - now)
    let status = state == .scheduled ? (remaining > 0 ? "running" : "elapsed") : state.rawValue
    return [
      "schedule": "timer", "operation_id": id.uuidString, "timer_state": status,
      "source_turn_id": sourceTurnId, "deadline_ms": String(deadlineMillis),
      "notification_id": notificationId,
      "remaining_seconds": String([.scheduled, .paused].contains(state) ? (remaining + 999) / 1_000 : 0),
      "completion_verified": "false"
    ]
  }
}

final class AgentIOSTimerCheckpointStore {
  enum Reservation {
    case new(AgentIOSTimerCheckpoint)
    case existing(AgentIOSTimerCheckpoint)
    case unavailable
  }

  static let shared = AgentIOSTimerCheckpointStore()
  private static let lock = NSLock()
  private static let key = "galaxyssi.ios.timer-checkpoints.v1"
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore

  init(defaults: UserDefaults = .standard, secrets: GalaxySSISecretStore = KeychainSecretStore.shared) {
    self.defaults = defaults
    self.secrets = secrets
  }

  func current(conversationId: String) -> AgentIOSTimerCheckpoint? {
    locked { load()?[key(conversationId)] }
  }

  func reserve(conversationId: String, turnId: String, duration: Int, now: Int64,
               label: String? = nil, replacing: UUID? = nil) -> Reservation {
    guard !conversationId.isBlank, !turnId.isBlank, conversationId.count <= 200, turnId.count <= 200,
          (1...604_800).contains(duration), now > 0, now < Int64.max - 604_800_000 else { return .unavailable }
    return locked {
      guard var records = load() else { return .unavailable }
      let scope = key(conversationId)
      if let replacing {
        guard let existing = records[scope], existing.id == replacing, existing.state == .cancelled
        else { return .unavailable }
      } else if let existing = records[scope] {
        if existing.sourceTurnId == turnId ||
            [.scheduling, .pausing, .paused, .cancelling].contains(existing.state) ||
            (existing.state == .scheduled && existing.deadlineMillis > now) {
          return .existing(existing)
        }
      }
      if records[scope] == nil, records.count >= 512 {
        guard let expired = records.filter({
          [.cancelled, .failed].contains($0.value.state) ||
            ($0.value.state == .scheduled && $0.value.deadlineMillis <= now)
        })
          .min(by: { $0.value.deadlineMillis < $1.value.deadlineMillis }) else { return .unavailable }
        records.removeValue(forKey: expired.key)
      }
      let record = AgentIOSTimerCheckpoint(id: UUID(), sourceTurnId: turnId, durationSeconds: duration,
        deadlineMillis: now + Int64(duration) * 1_000, state: .scheduling,
        replacedOperationId: replacing, label: label)
      records[scope] = record
      return save(records) ? .new(record) : .unavailable
    }
  }

  func transition(conversationId: String, from expected: AgentIOSTimerCheckpoint,
                  to next: AgentIOSTimerCheckpoint) -> Bool {
    locked {
      guard expected.id == next.id, var records = load(),
            records[key(conversationId)] == expected else { return false }
      records[key(conversationId)] = next
      return save(records)
    }
  }

  @discardableResult
  func update(conversationId: String, id: UUID, to state: AgentIOSTimerCheckpoint.State) -> Bool {
    locked {
      guard var records = load(), var record = records[key(conversationId)], record.id == id else { return false }
      if record.state == state { return true }
      guard record.state == .scheduling || (record.state == .scheduled && state == .cancelled) else { return false }
      record.state = state
      records[key(conversationId)] = record
      return save(records)
    }
  }

  private func key(_ conversationId: String) -> String { AgentModelLoopRecoveryIdentity.sha256(conversationId) }

  private func load() -> [String: AgentIOSTimerCheckpoint]? {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: Self.key, secrets: secrets) else {
      return GalaxySSIEncryptedUserDefaultsStore.storedKeys(defaults: defaults, prefix: Self.key).isEmpty ? [:] : nil
    }
    return try? JSONDecoder().decode([String: AgentIOSTimerCheckpoint].self, from: data)
  }

  private func save(_ records: [String: AgentIOSTimerCheckpoint]) -> Bool {
    guard let data = try? JSONEncoder().encode(records) else { return false }
    return GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: Self.key, secrets: secrets)
  }

  private func locked<T>(_ body: () -> T) -> T {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    return body()
  }
}

struct AgentIOSTimerNotificationIO {
  enum AddResult: Equatable { case accepted, rejected, unknown }
  struct Pending {
    let ids: Set<String>
    let timers: Set<String>
  }

  let authorization: () -> Bool?
  let add: (String, String, TimeInterval) -> AddResult
  let pending: () -> Pending?
  let delivered: () -> Set<String>?
  let remove: (String) -> Void

  init(authorization: @escaping () -> Bool?, add: @escaping (String, String, TimeInterval) -> AddResult,
       pending: @escaping () -> Pending?, delivered: @escaping () -> Set<String>?,
       remove: @escaping (String) -> Void) {
    self.authorization = authorization
    self.add = add
    self.pending = pending
    self.delivered = delivered
    self.remove = remove
  }

  init(center: UNUserNotificationCenter) {
    authorization = {
      Self.read { finish in
        center.getNotificationSettings { settings in
          finish([.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus))
        }
      }
    }
    add = { id, label, seconds in
      let content = UNMutableNotificationContent()
      content.title = "GalaxySSI"
      content.body = label
      content.sound = .default
      content.categoryIdentifier = "galaxyssi.schedule.timer"
      content.threadIdentifier = "galaxyssi.schedule"
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
      return Self.read { finish in
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) {
          finish($0 == nil ? .accepted : .rejected)
        }
      } ?? .unknown
    }
    pending = {
      Self.read { finish in
        center.getPendingNotificationRequests { requests in
          let timers = requests.filter {
            $0.content.categoryIdentifier == "galaxyssi.schedule.timer" &&
              ($0.trigger as? UNTimeIntervalNotificationTrigger)?.repeats == false
          }
          finish(Pending(ids: Set(requests.map(\.identifier)), timers: Set(timers.map(\.identifier))))
        }
      }
    }
    delivered = {
      Self.read { finish in
        center.getDeliveredNotifications { finish(Set($0.map { $0.request.identifier })) }
      }
    }
    remove = {
      center.removePendingNotificationRequests(withIdentifiers: [$0])
      center.removeDeliveredNotifications(withIdentifiers: [$0])
      AgentIOSOwnedNotificationStore.shared.remove(identifier: $0)
    }
  }

  private static func read<T>(_ request: (@escaping (T) -> Void) -> Void) -> T? {
    let gate = DispatchSemaphore(value: 0)
    var result: T?
    request { result = $0; gate.signal() }
    guard gate.wait(timeout: .now() + .milliseconds(500)) == .success else { return nil }
    return result
  }
}

struct AgentIOSTimerExecutor {
  private static let lock = NSLock()
  let store: AgentIOSTimerCheckpointStore
  let io: AgentIOSTimerNotificationIO
  let now: () -> Int64

  func execute(_ action: AgentAction) -> AgentActionResult {
    let result = perform(action)
    guard result.success else { return result }
    let command = (action.parameters["timer_operation"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank("start")
    let requiredState: String?
    switch command {
    case "start", "resume", "replace": requiredState = "running"
    case "pause": requiredState = "paused"
    case "cancel": requiredState = "cancelled"
    default: requiredState = nil
    }
    guard let requiredState, result.metadata["timer_state"] != requiredState else { return result }
    var evidence = result.metadata
    evidence["completion_verified"] = "false"
    evidence["error_code"] = "timer_requested_state_unverified"
    return AgentActionResult(actionId: action.id, success: false,
      message: "The observed phone timer is not in the requested state. Inspect it before changing it.",
      metadata: evidence)
  }

  private func perform(_ action: AgentAction) -> AgentActionResult {
    let params = action.parameters
    func value(_ key: String) -> String { (params[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    let conversation = value("_galaxyssi_conversation_id")
    let turn = value("_galaxyssi_turn_id")
    let command = value("timer_operation").ifBlank("start")
    let id = value("operation_id")
    let duration = Int(value("timer_seconds"))
    let label = String(value("label").ifBlank(action.description).ifBlank("Timer").prefix(160))
    guard !conversation.isBlank, !turn.isBlank, params["hour"] == nil, params["minute"] == nil,
          conversation.count <= 200, turn.count <= 200,
          ["start", "inspect", "pause", "resume", "cancel", "replace"].contains(command),
          ["start", "replace"].contains(command)
            ? (duration.map { (1...604_800).contains($0) } == true)
            : params["timer_seconds"] == nil else {
      return result(action, nil, error: "invalid_timer_request")
    }
    guard Self.lock.try() else { return result(action, nil, error: "timer_busy") }
    defer { Self.lock.unlock() }

    let current = store.current(conversationId: conversation)
    if command == "replace", let current, current.replacedOperationId?.uuidString == id,
       current.sourceTurnId == turn, current.durationSeconds == duration {
      return observe(action, current, conversation)
    }
    if !id.isEmpty, current?.id.uuidString != id {
      return result(action, current, error: "timer_operation_id_mismatch", extra: ["dispatch_accepted": "false"])
    }
    if command == "start", let duration {
      if let current, !id.isEmpty || current.sourceTurnId == turn {
        guard current.durationSeconds == duration else {
          return result(action, current, error: "timer_duration_mismatch")
        }
        return observe(action, current, conversation)
      }
      if let current, [.scheduling, .pausing, .paused, .cancelling].contains(current.state) ||
          (current.state == .scheduled && current.deadlineMillis > now()) {
        return result(action, current, error: "timer_already_running")
      }
      if let current, current.state == .scheduled, io.pending()?.ids.contains(current.notificationId) != false {
        return result(action, current, error: "timer_state_unverified")
      }
      if let denied = permissionFailure(action, current) { return denied }
      return start(action, conversation, turn, duration, label, replacing: nil)
    }
    guard let current, !id.isEmpty || (command == "inspect" && current.sourceTurnId == turn) else {
      return result(action, current, error: "timer_operation_id_required")
    }
    switch command {
    case "inspect":
      return observe(action, current, conversation)
    case "pause":
      if current.state == .paused { return observe(action, current, conversation) }
      if current.state == .pausing {
        if current.deadlineMillis > now() { io.remove(current.notificationId) }
        return observe(action, current, conversation)
      }
      guard current.state == .scheduled, io.pending()?.timers.contains(current.notificationId) == true,
            current.deadlineMillis > now() else { return result(action, current, error: "timer_running_unverified") }
      var pausing = current
      pausing.state = .pausing
      let remaining = current.deadlineMillis - now()
      guard remaining > 0 else { return result(action, current, error: "timer_running_unverified") }
      pausing.frozenMillis = remaining
      pausing.lastControlTurnId = turn
      guard store.transition(conversationId: conversation, from: current, to: pausing) else {
        return result(action, current, error: "timer_checkpoint_unavailable")
      }
      io.remove(pausing.notificationId)
      return observe(action, pausing, conversation)
    case "resume":
      if [.scheduled, .scheduling].contains(current.state) { return observe(action, current, conversation) }
      guard current.state == .paused, let remaining = current.frozenMillis,
            (1...604_800_000).contains(remaining), confirmedRemoval(current.notificationId) else {
        return result(action, current, error: "timer_pause_unverified")
      }
      if let denied = permissionFailure(action, current) { return denied }
      let time = now()
      guard time > 0, time < Int64.max - remaining else {
        return result(action, current, error: "invalid_timer_request")
      }
      var next = current
      next.state = .scheduling
      next.generation = UUID()
      next.deadlineMillis = time + remaining
      next.lastControlTurnId = turn
      guard store.transition(conversationId: conversation, from: current, to: next) else {
        return result(action, current, error: "timer_checkpoint_unavailable")
      }
      return dispatch(action, next, conversation, restoringPause: current)
    case "cancel", "replace":
      if command == "replace", let denied = permissionFailure(action, current) { return denied }
      let cancelled = cancel(action, current, conversation, turn)
      guard cancelled.success, command == "replace", let duration else { return cancelled }
      return start(action, conversation, turn, duration, label, replacing: current.id)
    default:
      return result(action, current, error: "invalid_timer_request")
    }
  }

  private func permissionFailure(_ action: AgentAction, _ record: AgentIOSTimerCheckpoint?) -> AgentActionResult? {
    guard let allowed = io.authorization() else {
      return result(action, record, error: "timer_permission_unverified")
    }
    return allowed ? nil : result(action, record, error: "timer_notification_permission_required",
      extra: ["notification_permission_required": "true", "dispatch_accepted": "false"])
  }

  private func start(_ action: AgentAction, _ conversation: String, _ turn: String, _ duration: Int,
                     _ label: String, replacing: UUID?) -> AgentActionResult {
    switch store.reserve(conversationId: conversation, turnId: turn, duration: duration, now: now(),
                         label: label, replacing: replacing) {
    case .new(let record): return dispatch(action, record, conversation)
    case .existing(let record): return result(action, record, error: "timer_already_running")
    case .unavailable: return result(action, nil, error: "timer_checkpoint_unavailable")
    }
  }

  private func dispatch(_ action: AgentAction, _ record: AgentIOSTimerCheckpoint, _ conversation: String,
                        restoringPause: AgentIOSTimerCheckpoint? = nil) -> AgentActionResult {
    let remaining = record.deadlineMillis - now()
    if remaining <= 0 || io.add(record.notificationId, record.label ?? "Timer", Double(remaining) / 1_000) == .rejected {
      var failed = restoringPause ?? record
      if restoringPause == nil { failed.state = .failed }
      let saved = store.transition(conversationId: conversation, from: record, to: failed)
      return result(action, saved ? failed : record, error: "timer_dispatch_failed", extra: ["dispatch_accepted": "false"])
    }
    // Acceptance (or a timed-out dispatch callback) is never evidence that the countdown exists.
    return observe(action, record, conversation)
  }

  private func cancel(_ action: AgentAction, _ record: AgentIOSTimerCheckpoint, _ conversation: String,
                      _ turn: String) -> AgentActionResult {
    if record.state == .scheduling {
      _ = observe(action, record, conversation)
      guard let settled = store.current(conversationId: conversation), settled.id == record.id,
            settled.state == .scheduled else { return result(action, record, error: "timer_scheduling_unsettled") }
      return cancel(action, settled, conversation, turn)
    }
    if record.state == .cancelled { return observe(action, record, conversation) }
    if record.state == .cancelling {
      io.remove(record.notificationId)
      return observe(action, record, conversation)
    }
    var next = record
    next.state = .cancelling
    next.lastControlTurnId = turn
    guard store.transition(conversationId: conversation, from: record, to: next) else {
      return result(action, record, error: "timer_checkpoint_unavailable")
    }
    io.remove(next.notificationId)
    return observe(action, next, conversation)
  }

  private func confirmedRemoval(_ id: String) -> Bool {
    guard let first = io.pending(), !first.ids.contains(id),
          let delivered = io.delivered(), !delivered.contains(id),
          let last = io.pending(), !last.ids.contains(id) else { return false }
    return true
  }

  private func observe(_ action: AgentAction, _ record: AgentIOSTimerCheckpoint, _ conversation: String) -> AgentActionResult {
    var settled = record
    switch record.state {
    case .scheduling, .scheduled:
      let pending = io.pending()
      if pending?.timers.contains(record.notificationId) == true, record.deadlineMillis > now() {
        settled.state = .scheduled
      } else if record.deadlineMillis <= now(), pending?.ids.contains(record.notificationId) == false,
                io.delivered()?.contains(record.notificationId) == true {
        settled.state = .scheduled
      } else {
        return result(action, record, error: "timer_state_unverified")
      }
    case .pausing, .paused:
      guard confirmedRemoval(record.notificationId), (record.frozenMillis ?? 0) > 0,
            record.state == .paused || record.deadlineMillis > now() else {
        return result(action, record, error: "timer_pause_unverified")
      }
      settled.state = .paused
    case .cancelling, .cancelled:
      guard confirmedRemoval(record.notificationId) else {
        return result(action, record, error: "timer_cancellation_unverified")
      }
      settled.state = .cancelled
      settled.frozenMillis = nil
    case .failed:
      return result(action, record, error: "timer_dispatch_failed")
    }
    guard settled == record || store.transition(conversationId: conversation, from: record, to: settled) else {
      return result(action, record, error: "timer_checkpoint_unavailable")
    }
    return result(action, settled)
  }

  private func result(_ action: AgentAction, _ record: AgentIOSTimerCheckpoint?, error: String? = nil,
                      extra: [String: String] = [:]) -> AgentActionResult {
    var evidence = record?.evidence(now: now()) ?? [:]
    evidence["completion_verified"] = error == nil ? "true" : "false"
    evidence["error_code"] = error
    evidence.merge(extra) { _, value in value }
    if let error {
      let message: String
      switch error {
      case "timer_notification_permission_required":
        message = "Allow GalaxySSI notifications in iOS Settings before scheduling a timer."
      case "timer_operation_id_required", "timer_operation_id_mismatch":
        message = "Use a timer operation ID observed in this conversation. Omit it only for a new timer."
      case "invalid_timer_request":
        message = "Start or replace with a duration of 1 to 604800 seconds; inspect, pause, resume, or cancel without a duration."
      default:
        message = "Timer operation not verified. Inspect the current operation before attempting another change."
      }
      return AgentActionResult(actionId: action.id, success: false, message: message, metadata: evidence)
    }
    return AgentActionResult(actionId: action.id, success: true,
      message: "Phone timer state verified: \(evidence["timer_state"] ?? "")", metadata: evidence)
  }
}
