import XCTest
@testable import GalaxySSI

final class AgentConnectorTerminalStatusResolverTests: XCTestCase {
  func testResolverSettlesTimedOutRemoteTaskWithAndroidMetadata() {
    let pending = AgentActionResult(
      actionId: "action",
      success: true,
      message: "Waiting",
      metadata: [
        "awaiting_response": "true",
        "source_message_id": "73",
        "contact_id": "codex",
        "resource_started_at": "1000",
        "remote_task_status_seq": "2"
      ]
    )
    let envelope = AgentConnectorTerminalStatusEnvelope(
      sourceMessageId: 73,
      contactId: "codex",
      taskId: "task-73",
      taskStatus: " TIMED_OUT ",
      statusSeq: 5,
      nowMillis: 4500
    )

    XCTAssertTrue(AgentConnectorTerminalStatusResolver.canAccept(pending: pending, envelope: envelope))
    let settlement = AgentConnectorTerminalStatusResolver.settle(pending: pending, envelope: envelope)

    XCTAssertEqual(settlement?.eventType, .runFailed)
    XCTAssertEqual(settlement?.result.success, false)
    XCTAssertEqual(settlement?.result.message, "The remote task timed out.")
    XCTAssertEqual(settlement?.result.metadata["awaiting_response"], "false")
    XCTAssertEqual(settlement?.result.metadata["remote_task_id"], "task-73")
    XCTAssertEqual(settlement?.result.metadata["remote_task_status"], "timed_out")
    XCTAssertEqual(settlement?.result.metadata["remote_task_status_seq"], "5")
    XCTAssertEqual(settlement?.result.metadata["remote_task_status_updated_at"], "4500")
    XCTAssertEqual(settlement?.result.metadata["remote_task_terminal_at"], "4500")
    XCTAssertEqual(settlement?.result.metadata["timeout_stage"], "REMOTE_TASK")
    XCTAssertEqual(settlement?.result.metadata["timeout_elapsed_ms"], "3500")
    XCTAssertEqual(settlement?.eventPayload["remote_task_status"]?.stringValue, "timed_out")
  }

  func testResolverIgnoresNonTerminalAndStaleTerminalStatus() {
    let pending = AgentActionResult(
      actionId: "action",
      success: true,
      message: "Waiting",
      metadata: [
        "awaiting_response": "true",
        "source_message_id": "42",
        "remote_task_status_seq": "9"
      ]
    )
    let running = AgentConnectorTerminalStatusEnvelope(
      sourceMessageId: 42,
      contactId: "",
      taskId: "task-42",
      taskStatus: "running",
      statusSeq: 10
    )
    let staleFailure = AgentConnectorTerminalStatusEnvelope(
      sourceMessageId: 42,
      contactId: "",
      taskId: "task-42",
      taskStatus: "failed",
      statusSeq: 8
    )

    XCTAssertNil(AgentConnectorTerminalStatusResolver.settle(pending: pending, envelope: running))
    let stale = AgentConnectorTerminalStatusResolver.settle(pending: pending, envelope: staleFailure)

    XCTAssertNil(stale?.eventType)
    XCTAssertEqual(stale?.shouldDeactivateRun, false)
    XCTAssertEqual(stale?.result.metadata["awaiting_response"], "true")
    XCTAssertEqual(stale?.result.metadata["remote_task_status_seq"], "9")
  }

  func testResolverRejectsMismatchedDesktopIdentity() {
    let pending = AgentActionResult(
      actionId: "action",
      success: true,
      message: "Waiting",
      metadata: [
        "awaiting_response": "true",
        "source_message_id": "88",
        "contact_id": "codex",
        "resource_location": "desktop",
        "conversation_id": "conversation-a",
        "remote_task_id": "task-a",
        "turn_id": "turn-a"
      ]
    )
    let envelope = AgentConnectorTerminalStatusEnvelope(
      sourceMessageId: 88,
      contactId: "codex",
      taskId: "task-b",
      taskStatus: "failed",
      statusSeq: 2,
      conversationId: "conversation-a",
      turnId: "turn-a"
    )

    XCTAssertFalse(AgentConnectorTerminalStatusResolver.canAccept(pending: pending, envelope: envelope))
  }
}

extension GalaxySSIStoreTests {
  func testActionExecutorAgentProviderSettlesRemoteTerminalStatusWithoutResponse() async throws {
    let registration = actionExecutorRegistration()
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Ready for user response",
        metadata: [
          "awaiting_response": "true",
          "source_message_id": "73",
          "contact_id": "codex",
          "resource_started_at": "1000",
          "resource_location": "desktop",
          "conversation_id": "conversation",
          "remote_task_id": "task-73",
          "turn_id": "turn"
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
      runId: "run-terminal",
      goal: "Inspect project",
      context: ["managed_team": .bool(true)],
      idempotencyKey: "run-terminal"
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
    let settled = provider.acceptConnectorTerminalStatus(
      sourceMessageId: 73,
      contactId: "codex",
      taskId: "task-73",
      taskStatus: "timed_out",
      statusSeq: 5,
      message: "",
      conversationId: "conversation",
      turnId: "turn",
      nowMillis: 4500
    )
    let terminal = await iterator.next()

    XCTAssertEqual(settled?.success, false)
    XCTAssertEqual(settled?.metadata["awaiting_response"], "false")
    XCTAssertEqual(settled?.metadata["timeout_stage"], "REMOTE_TASK")
    XCTAssertEqual(settled?.metadata["timeout_elapsed_ms"], "3500")
    XCTAssertEqual(provider.result(agentId: "codex", runId: request.runId), settled)
    XCTAssertEqual(terminal?.type, .runFailed)
    XCTAssertEqual(terminal?.sequence, Int64(5))
    XCTAssertEqual(terminal?.payload["remote_task_status"]?.stringValue, "timed_out")
  }

  func testActionExecutorAgentProviderKeepsRunActiveAfterStaleTerminalStatus() async throws {
    let registration = actionExecutorRegistration()
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Waiting",
        metadata: [
          "awaiting_response": "true",
          "source_message_id": "42",
          "remote_task_status_seq": "9"
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
      runId: "run-stale",
      goal: "Inspect project",
      context: ["managed_team": .bool(true)],
      idempotencyKey: "run-stale"
    )
    provider.prepare(
      agentId: "codex",
      request: request,
      action: actionExecutorConnectorAction(),
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")
    )

    _ = try await adapter.startRun(request)
    let stale = provider.acceptConnectorTerminalStatus(
      sourceMessageId: 42,
      contactId: "",
      taskId: "task-42",
      taskStatus: "failed",
      statusSeq: 8,
      message: "old failure",
      nowMillis: 2000
    )
    let cancelled = provider.acceptConnectorTerminalStatus(
      sourceMessageId: 42,
      contactId: "",
      taskId: "task-42",
      taskStatus: "cancelled",
      statusSeq: 10,
      message: "",
      nowMillis: 3000
    )

    XCTAssertEqual(stale?.metadata["awaiting_response"], "true")
    XCTAssertEqual(stale?.metadata["remote_task_status_seq"], "9")
    XCTAssertEqual(cancelled?.message, "The remote task was cancelled.")
    XCTAssertEqual(cancelled?.metadata["awaiting_response"], "false")
    XCTAssertEqual(cancelled?.metadata["remote_task_status"], "cancelled")
    XCTAssertNil(provider.acceptConnectorTerminalStatus(
      sourceMessageId: 42,
      contactId: "",
      taskId: "task-42",
      taskStatus: "failed",
      statusSeq: 11,
      message: "late duplicate",
      nowMillis: 4000
    ))
  }
}
