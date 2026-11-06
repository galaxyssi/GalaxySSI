import XCTest
@testable import GalaxySSI

final class AgentActionNotificationTests: XCTestCase {
  func testPhoneTimerCheckpointKeepsGeneratedIdentityAndCountdownAcrossRelaunch() throws {
    let name = "timer-checkpoint-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let secrets = InMemorySecretStore()
    let store = AgentIOSTimerCheckpointStore(defaults: defaults, secrets: secrets)
    guard case .new(let timer) = store.reserve(conversationId: "one", turnId: "turn", duration: 60, now: 1_000) else {
      return XCTFail("Expected a new timer checkpoint")
    }
    XCTAssertTrue(store.update(conversationId: "one", id: timer.id, to: .scheduled))
    let reopened = AgentIOSTimerCheckpointStore(defaults: defaults, secrets: secrets)
    guard case .existing(let same) = reopened.reserve(conversationId: "one", turnId: "turn", duration: 60, now: 2_000) else {
      return XCTFail("Retry must observe the existing timer")
    }
    XCTAssertEqual(same.id, timer.id)
    XCTAssertEqual(same.evidence(now: 2_000)["remaining_seconds"], "59")
    XCTAssertEqual(same.evidence(now: 61_000)["timer_state"], "elapsed")
    XCTAssertNil(reopened.current(conversationId: "other"))

    let notifications = TimerNotificationFixture()
    notifications.pending.insert(timer.notificationId)
    let executor = AgentIOSTimerExecutor(store: reopened, io: notifications.io, now: { 2_000 })
    let scope = ["_galaxyssi_conversation_id": "one", "_galaxyssi_turn_id": "turn"]
    let guessed = executor.execute(action(kind: .setAlarm, parameters: scope.merging([
      "timer_seconds": "60", "operation_id": UUID().uuidString
    ]) { _, new in new }))
    XCTAssertFalse(guessed.success)
    XCTAssertEqual(guessed.metadata["error_code"], "timer_operation_id_mismatch")
    XCTAssertEqual(guessed.metadata["dispatch_accepted"], "false")
    XCTAssertEqual(guessed.metadata["operation_id"], timer.id.uuidString)
    XCTAssertEqual(reopened.current(conversationId: "one")?.id, timer.id)
    let inspect = executor.execute(action(kind: .setAlarm, parameters: scope.merging([
      "timer_operation": "inspect", "operation_id": timer.id.uuidString
    ]) { _, new in new }))
    XCTAssertTrue(inspect.success)
    XCTAssertEqual(inspect.metadata["remaining_seconds"], "59")
    notifications.pending.removeAll()
    let missing = executor.execute(action(kind: .setAlarm, parameters: scope.merging([
      "timer_operation": "inspect", "operation_id": timer.id.uuidString
    ]) { _, new in new }))
    XCTAssertFalse(missing.success)
    XCTAssertEqual(missing.metadata["completion_verified"], "false")
  }

  func testPhoneTimerPauseResumeReplaceAndCancelRequireSystemReadback() throws {
    let suite = "timer-lifecycle-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let secrets = InMemorySecretStore()
    let notifications = TimerNotificationFixture()
    var now: Int64 = 1_000
    func execute(_ command: String, _ turn: String, id: String? = nil, seconds: Int? = nil,
                 conversation: String = "one") -> AgentActionResult {
      var params = ["_galaxyssi_conversation_id": conversation, "_galaxyssi_turn_id": turn, "timer_operation": command]
      params["operation_id"] = id
      params["timer_seconds"] = seconds.map(String.init)
      return AgentIOSTimerExecutor(store: .init(defaults: defaults, secrets: secrets),
        io: notifications.io, now: { now }).execute(action(kind: .setAlarm, parameters: params))
    }

    let started = execute("start", "start", seconds: 60)
    XCTAssertTrue(started.success)
    let id = try XCTUnwrap(started.metadata["operation_id"])
    let originalNotification = try XCTUnwrap(started.metadata["notification_id"])
    XCTAssertEqual(execute("start", "start", seconds: 60).metadata["operation_id"], id)
    XCTAssertFalse(execute("pause", "foreign", id: id, conversation: "other").success)
    now += 10_000
    notifications.removalWorks = false
    XCTAssertFalse(execute("pause", "pause", id: id).success)
    XCTAssertFalse(execute("inspect", "inspect", id: id).success)
    XCTAssertFalse(execute("resume", "resume", id: id).success)
    XCTAssertEqual(notifications.adds.count, 1)
    notifications.removalWorks = true
    XCTAssertEqual(execute("pause", "pause", id: id).metadata["timer_state"], "paused")
    XCTAssertFalse(execute("start", "start", seconds: 60).success)
    now += 20_000
    XCTAssertEqual(execute("inspect", "inspect", id: id).metadata["remaining_seconds"], "50")

    let resumed = execute("resume", "resume", id: id)
    XCTAssertTrue(resumed.success)
    XCTAssertEqual(resumed.metadata["operation_id"], id)
    XCTAssertNotEqual(resumed.metadata["notification_id"], originalNotification)
    XCTAssertEqual(notifications.adds.last?.seconds, 50)
    XCTAssertEqual(execute("resume", "resume", id: id).metadata["timer_state"], "running")
    XCTAssertEqual(notifications.adds.count, 2)

    notifications.allowed = false
    XCTAssertEqual(execute("replace", "replace", id: id, seconds: 90).metadata["error_code"],
                   "timer_notification_permission_required")
    XCTAssertEqual(notifications.pending, Set([try XCTUnwrap(resumed.metadata["notification_id"])]))
    notifications.allowed = true
    let replacement = execute("replace", "replace", id: id, seconds: 90)
    XCTAssertTrue(replacement.success)
    let newId = try XCTUnwrap(replacement.metadata["operation_id"])
    XCTAssertNotEqual(newId, id)
    XCTAssertEqual(execute("replace", "replace", id: id, seconds: 90).metadata["operation_id"], newId)
    XCTAssertEqual(notifications.adds.count, 3)
    XCTAssertFalse(execute("cancel", "stale", id: id).success)
    XCTAssertEqual(execute("cancel", "cancel", id: newId).metadata["timer_state"], "cancelled")
    XCTAssertTrue(notifications.pending.isEmpty)
  }

  func testUnknownTimerDispatchIsNotReplayedAndRequiresAnExactNotification() throws {
    let suite = "timer-dispatch-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let notifications = TimerNotificationFixture()
    notifications.addResult = .unknown
    let executor = AgentIOSTimerExecutor(store: .init(defaults: defaults, secrets: InMemorySecretStore()),
      io: notifications.io, now: { 1_000 })
    let params = ["_galaxyssi_conversation_id": "one", "_galaxyssi_turn_id": "start", "timer_seconds": "60"]
    let start = action(kind: .setAlarm, parameters: params)
    let result = executor.execute(start)
    XCTAssertFalse(result.success)
    let notification = try XCTUnwrap(result.metadata["notification_id"])
    notifications.pending.insert("other-timer")
    XCTAssertFalse(executor.execute(start).success)
    XCTAssertEqual(notifications.adds.count, 1)
    notifications.pending.insert(notification)
    XCTAssertTrue(executor.execute(start).success)
    XCTAssertEqual(notifications.adds.count, 1)
  }

  func testPhoneToolCatalogAdvertisesTimerAndAppLaunchInputs() throws {
    let descriptors = AgentPhoneNativeToolCatalog.descriptors()
    let timer = try XCTUnwrap(descriptors.first {
      $0.id == AgentNativeToolAgentActionAdapter.defaultToolId(.setAlarm)
    })
    let input = try XCTUnwrap(timer.inputSchema["properties"]?.objectValue)
    for key in ["timer_seconds", "timer_operation", "operation_id", "hour", "minute", "label"] {
      XCTAssertNotNil(input[key])
    }
    XCTAssertEqual(input["timer_operation"]?.objectValue?["enum"]?.arrayValue?.compactMap(\.stringValue),
                   ["start", "inspect", "pause", "resume", "cancel", "replace"])
    let app = try XCTUnwrap(descriptors.first {
      $0.id == AgentNativeToolAgentActionAdapter.defaultToolId(.openApp)
    })
    XCTAssertNotNil(app.inputSchema["properties"]?.objectValue?["package"])
  }

  func testIOSPresentationSuppressesProgressDismissesSuccessAndKeepsFailure() {
    XCTAssertEqual(AgentIOSUserNotificationPublisher.presentation(for: .running), .ignore)
    XCTAssertEqual(AgentIOSUserNotificationPublisher.presentation(for: .succeeded), .dismiss)
    XCTAssertEqual(AgentIOSUserNotificationPublisher.presentation(for: .failed), .show)
  }

  func testNotifyingExecutorPublishesRunningAndResultNotifications() {
    let publisher = InMemoryAgentActionNotificationPublisher()
    let center = AgentActionNotificationCenter(publisher: publisher, nowMillis: { 1_000 })
    let delegate = RecordingActionExecutor(result: AgentActionResult(actionId: "open", success: true, message: "ok"))
    let executor = NotifyingAgentActionExecutor(delegate: delegate, notifications: center)

    let result = executor.execute(
      action: action(
        id: "open",
        kind: .openApp,
        target: "Calendar",
        description: "Open calendar",
        parameters: ["_galaxyssi_task_id": "turn-42"]
      ),
      screen: screen()
    )
    let notifications = publisher.notifications()

    XCTAssertEqual(result.success, true)
    XCTAssertEqual(delegate.executed.map(\.id), ["open"])
    XCTAssertEqual(notifications.map(\.phase), [.running, .succeeded])
    XCTAssertEqual(notifications.map(\.category), [.progress, .status])
    XCTAssertEqual(notifications.map(\.title), ["Open Calendar", "Open Calendar"])
    XCTAssertEqual(notifications.map(\.taskId), ["turn-42", "turn-42"])
    XCTAssertEqual(notifications.first?.ongoing, true)
    XCTAssertEqual(notifications.last?.ongoing, false)
    XCTAssertEqual(notifications.first?.notificationId, notifications.last?.notificationId)
    XCTAssertEqual(notifications.first?.privateText, AgentActionNotificationPolicy.defaultPrivateText)
  }

  func testExecutorSkipsDraftConnectorAndCreateNotificationActions() {
    let publisher = InMemoryAgentActionNotificationPublisher()
    let center = AgentActionNotificationCenter(publisher: publisher)
    let delegate = RecordingActionExecutor(result: AgentActionResult(actionId: "ignored", success: true, message: "ok"))
    let executor = NotifyingAgentActionExecutor(delegate: delegate, notifications: center)

    [.draftPlan, .callConnector, .createNotification].enumerated().forEach { index, kind in
      _ = executor.execute(
        action: action(id: "ignored-\(index)", kind: kind),
        screen: screen()
      )
    }

    XCTAssertEqual(delegate.executed.count, 3)
    XCTAssertTrue(publisher.notifications().isEmpty)
  }

  func testPolicyBuildsAndroidStyleOperationTitlesAndDestinations() {
    let timer = action(kind: .setAlarm, parameters: ["timer_seconds": "120"])
    let alarm = action(kind: .setAlarm, parameters: ["hour": "7", "minute": "5"])
    let camera = action(kind: .controlDevice, description: "Take camera photo")
    let flashlight = action(kind: .controlDevice, parameters: ["enabled": "false", "device": "flashlight"])
    let volume = action(kind: .controlDevice, description: "Set audio mute")

    XCTAssertEqual(AgentActionNotificationPolicy.operationTitle(for: timer), "Timer 2m")
    XCTAssertEqual(AgentActionNotificationPolicy.destination(for: timer), .timers)
    XCTAssertEqual(AgentActionNotificationPolicy.operationTitle(for: alarm), "Alarm 07:05")
    XCTAssertEqual(AgentActionNotificationPolicy.destination(for: alarm), .mainApp)
    XCTAssertEqual(AgentActionNotificationPolicy.operationTitle(for: camera), "Camera")
    XCTAssertEqual(AgentActionNotificationPolicy.operationTitle(for: flashlight), "Flashlight off")
    XCTAssertEqual(AgentActionNotificationPolicy.operationTitle(for: volume), "Volume")
  }

  func testResultNotificationBoundsFailureDetailAndUsesStableTaskNotificationId() throws {
    let longFailure = String(repeating: "x", count: AgentActionNotification.maximumDetailCharacters + 20)
    let first = action(
      id: "a",
      kind: .openURL,
      description: "Open URL",
      parameters: ["_galaxyssi_task_id": "stable-task"]
    )
    let second = action(
      id: "b",
      kind: .tap,
      description: "Tap",
      parameters: ["_galaxyssi_task_id": "stable-task"]
    )
    let failed = AgentActionNotificationPolicy.resultNotification(
      for: first,
      result: AgentActionResult(actionId: first.id, success: false, message: longFailure),
      nowMillis: 2_000
    )
    let encoded = String(decoding: try JSONEncoder().encode(failed), as: UTF8.self)

    XCTAssertEqual(failed.phase, .failed)
    XCTAssertEqual(failed.category, .error)
    XCTAssertEqual(failed.successful, false)
    XCTAssertEqual(failed.detail.count, AgentActionNotification.maximumDetailCharacters)
    XCTAssertEqual(AgentActionNotificationPolicy.notificationId(for: first), AgentActionNotificationPolicy.notificationId(for: second))
    XCTAssertTrue(encoded.contains(#""notification_id":"#))
    XCTAssertTrue(encoded.contains(#""private_text":"#))
    XCTAssertTrue(encoded.contains(#""created_at_millis":2000"#))
  }

  private func action(
    id: String = "action",
    kind: AgentActionKind = .openApp,
    target: String = "",
    description: String = "",
    parameters: [String: String] = [:]
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: kind,
      target: target,
      risk: .low,
      status: .pendingConfirmation,
      description: description,
      parameters: parameters
    )
  }

  private func screen() -> AgentScreenContext {
    AgentScreenContext(foregroundApp: "GalaxySSI")
  }
}

private final class TimerNotificationFixture {
  var allowed: Bool? = true
  var addResult = AgentIOSTimerNotificationIO.AddResult.accepted
  var pending = Set<String>()
  var delivered = Set<String>()
  var removalWorks = true
  var adds: [(id: String, seconds: TimeInterval)] = []

  var io: AgentIOSTimerNotificationIO {
    .init(authorization: { self.allowed }, add: { id, _, seconds in
      self.adds.append((id, seconds))
      if self.addResult == .accepted { self.pending.insert(id) }
      return self.addResult
    }, pending: {
      .init(ids: self.pending, timers: self.pending)
    }, delivered: {
      self.delivered
    }, remove: { id in
      guard self.removalWorks else { return }
      self.pending.remove(id)
      self.delivered.remove(id)
    })
  }
}

private final class RecordingActionExecutor: AgentActionExecutor {
  private let result: AgentActionResult
  private(set) var executed: [AgentAction] = []

  init(result: AgentActionResult) {
    self.result = result
  }

  func execute(action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
    executed.append(action)
    var next = result
    next.actionId = action.id
    return next
  }
}
