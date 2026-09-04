import XCTest
@testable import GalaxySSI

final class AgentTaskWatchdogTimeoutResolverTests: XCTestCase {
  func testResolverMatchesAndroidTaskWatchdogMetadata() {
    let pending = AgentActionResult(
      actionId: "action",
      success: true,
      message: "Waiting",
      metadata: [
        "awaiting_response": "true",
        "source_message_id": "71",
        "remote_task_status": "running"
      ]
    )

    let timeout = AgentTaskWatchdogTimeoutResolver.resolve(
      pending: pending,
      message: "  ",
      nowMillis: 9000
    )

    XCTAssertEqual(timeout.result.actionId, "action")
    XCTAssertEqual(timeout.result.success, false)
    XCTAssertEqual(timeout.result.message, "The task timed out.")
    XCTAssertEqual(timeout.result.metadata["awaiting_response"], "false")
    XCTAssertEqual(timeout.result.metadata["timeout_stage"], "TASK_WATCHDOG")
    XCTAssertEqual(timeout.result.metadata["remote_task_status"], "timed_out")
    XCTAssertEqual(timeout.result.metadata["remote_task_terminal_at"], "9000")
    XCTAssertNil(timeout.result.metadata["timeout_elapsed_ms"])
    XCTAssertEqual(timeout.eventPayload["timeout_stage"]?.stringValue, "TASK_WATCHDOG")
  }

  func testResolverUsesGenericActionIdForBlankPendingAction() {
    let pending = AgentActionResult(
      actionId: "",
      success: true,
      message: "Waiting",
      metadata: [:]
    )

    let timeout = AgentTaskWatchdogTimeoutResolver.resolve(
      pending: pending,
      message: "Stopped by watchdog",
      nowMillis: 5000
    )

    XCTAssertEqual(timeout.result.actionId, "agent-task-timeout")
    XCTAssertEqual(timeout.result.message, "Stopped by watchdog")
    XCTAssertEqual(timeout.result.metadata["remote_task_terminal_at"], "5000")
  }
}

extension GalaxySSIStoreTests {
  func testActionExecutorAgentProviderForcesTaskWatchdogTimeout() async throws {
    let registration = actionExecutorRegistration()
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Waiting",
        metadata: [
          "awaiting_response": "true",
          "source_message_id": "71",
          "remote_task_status": "running"
        ]
      )
    }
    let provider = ActionExecutorAgentProvider(
      registrationSource: { [registration] },
      delegate: delegate
    )
    let adapter = try XCTUnwrap(try await provider.adapter(agentId: "codex"))
    let request = AgentRunRequest(
      conversationId: "conversation",
      messageId: "turn",
      taskId: "turn",
      runId: "run-watchdog",
      goal: "Inspect project",
      context: ["managed_team": .bool(true)],
      idempotencyKey: "run-watchdog"
    )
    provider.prepare(
      agentId: "codex",
      request: request,
      action: actionExecutorConnectorAction(),
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")
    )

    _ = try await adapter.startRun(request)
    var iterator = adapter.observeEvents(runId: request.runId).makeAsyncIterator()
    _ = await iterator.next()
    _ = await iterator.next()
    _ = await iterator.next()
    _ = await iterator.next()
    let timeout = provider.forceTaskTimeout(
      runId: request.runId,
      message: "Task watchdog timed out",
      nowMillis: 9000
    )
    let failed = await iterator.next()

    XCTAssertEqual(timeout?.success, false)
    XCTAssertEqual(timeout?.message, "Task watchdog timed out")
    XCTAssertEqual(timeout?.metadata["awaiting_response"], "false")
    XCTAssertEqual(timeout?.metadata["timeout_stage"], "TASK_WATCHDOG")
    XCTAssertEqual(timeout?.metadata["remote_task_status"], "timed_out")
    XCTAssertEqual(timeout?.metadata["remote_task_terminal_at"], "9000")
    XCTAssertEqual(failed?.type, .runFailed)
    XCTAssertEqual(failed?.payload["timeout_stage"]?.stringValue, "TASK_WATCHDOG")
    XCTAssertNil(provider.recordConnectorTaskStatus(
      sourceMessageId: 71,
      contactId: "",
      taskId: "task-71",
      taskStatus: "running",
      statusSeq: 2,
      nowMillis: 9500
    ))
    XCTAssertNil(provider.forceTaskTimeout(runId: request.runId, message: "duplicate", nowMillis: 10_000))
  }
}
