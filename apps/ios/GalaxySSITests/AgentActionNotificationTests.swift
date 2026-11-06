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

    let executor = AgentIOSNativeActionExecutor(nowMillis: { 2_000 }, timerStore: reopened)
    let scope = ["_galaxyssi_conversation_id": "one", "_galaxyssi_turn_id": "turn"]
    let guessed = executor.execute(action: action(kind: .setAlarm, parameters: scope.merging([
      "timer_seconds": "60", "operation_id": UUID().uuidString
    ]) { _, new in new }), screen: screen())
    XCTAssertFalse(guessed.success)
    XCTAssertEqual(guessed.metadata["error_code"], "timer_operation_id_mismatch")
    XCTAssertEqual(guessed.metadata["dispatch_accepted"], "false")
    XCTAssertEqual(guessed.metadata["operation_id"], timer.id.uuidString)
    XCTAssertEqual(reopened.current(conversationId: "one")?.id, timer.id)
    let inspect = executor.execute(action: action(kind: .setAlarm, parameters: scope.merging([
      "timer_operation": "inspect", "operation_id": timer.id.uuidString
    ]) { _, new in new }), screen: screen())
    XCTAssertTrue(inspect.success)
    XCTAssertEqual(inspect.metadata["remaining_seconds"], "59")
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
