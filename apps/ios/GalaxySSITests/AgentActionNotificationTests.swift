import XCTest
@testable import GalaxySSI

final class AgentActionNotificationTests: XCTestCase {
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
