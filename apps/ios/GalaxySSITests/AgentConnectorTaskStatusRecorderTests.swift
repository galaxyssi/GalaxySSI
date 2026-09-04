import XCTest
@testable import GalaxySSI

final class AgentConnectorTaskStatusRecorderTests: XCTestCase {
  func testRecorderStoresAndroidRemoteTaskProgressMetadata() {
    let pending = AgentActionResult(
      actionId: "action",
      success: true,
      message: "Waiting",
      metadata: [
        "awaiting_response": "true",
        "source_message_id": "51"
      ]
    )
    let envelope = AgentConnectorTerminalStatusEnvelope(
      sourceMessageId: 51,
      contactId: "",
      taskId: "task-51",
      taskStatus: " RUNNING ",
      statusSeq: 7,
      nowMillis: 2500
    )

    let record = AgentConnectorTaskStatusRecorder.record(pending: pending, envelope: envelope)

    XCTAssertEqual(record?.didApplyStatus, true)
    XCTAssertEqual(record?.result.success, true)
    XCTAssertEqual(record?.result.message, "Waiting")
    XCTAssertEqual(record?.result.metadata["awaiting_response"], "true")
    XCTAssertEqual(record?.result.metadata["remote_task_id"], "task-51")
    XCTAssertEqual(record?.result.metadata["remote_task_status"], "running")
    XCTAssertEqual(record?.result.metadata["remote_task_status_seq"], "7")
    XCTAssertEqual(record?.result.metadata["remote_task_status_updated_at"], "2500")
    XCTAssertNil(record?.result.metadata["remote_task_terminal_at"])
  }

  func testRecorderDoesNotOverwriteNewerStatusSequence() {
    let pending = AgentActionResult(
      actionId: "action",
      success: true,
      message: "Waiting",
      metadata: [
        "awaiting_response": "true",
        "source_message_id": "51",
        "remote_task_id": "task-new",
        "remote_task_status": "running",
        "remote_task_status_seq": "9",
        "remote_task_status_updated_at": "3000"
      ]
    )
    let stale = AgentConnectorTerminalStatusEnvelope(
      sourceMessageId: 51,
      contactId: "",
      taskId: "task-old",
      taskStatus: "accepted",
      statusSeq: 8,
      nowMillis: 4000
    )

    let record = AgentConnectorTaskStatusRecorder.record(pending: pending, envelope: stale)

    XCTAssertEqual(record?.didApplyStatus, false)
    XCTAssertEqual(record?.result.metadata["remote_task_id"], "task-new")
    XCTAssertEqual(record?.result.metadata["remote_task_status"], "running")
    XCTAssertEqual(record?.result.metadata["remote_task_status_seq"], "9")
    XCTAssertEqual(record?.result.metadata["remote_task_status_updated_at"], "3000")
  }
}

extension GalaxySSIStoreTests {
  func testActionExecutorAgentProviderRecordsConnectorTaskStatusBeforeTerminalResult() async throws {
    let registration = actionExecutorRegistration()
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Waiting",
        metadata: [
          "awaiting_response": "true",
          "source_message_id": "51",
          "contact_id": "codex",
          "resource_started_at": "1000",
          "resource_location": "desktop",
          "conversation_id": "conversation",
          "remote_task_id": "task-51",
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
      runId: "run-status",
      goal: "Inspect project",
      context: ["managed_team": .bool(true)],
      idempotencyKey: "run-status"
    )
    provider.prepare(
      agentId: "codex",
      request: request,
      action: actionExecutorConnectorAction(),
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")
    )

    _ = try await adapter.startRun(request)
    let running = provider.recordConnectorTaskStatus(
      sourceMessageId: 51,
      contactId: "codex",
      taskId: "task-51",
      taskStatus: "running",
      statusSeq: 3,
      conversationId: "conversation",
      turnId: "turn",
      nowMillis: 2500
    )
    let failed = provider.acceptConnectorTerminalStatus(
      sourceMessageId: 51,
      contactId: "codex",
      taskId: "task-51",
      taskStatus: "failed",
      statusSeq: 4,
      message: "desktop failed",
      conversationId: "conversation",
      turnId: "turn",
      nowMillis: 4000
    )

    XCTAssertEqual(running?.metadata["awaiting_response"], "true")
    XCTAssertEqual(running?.metadata["remote_task_status"], "running")
    XCTAssertEqual(running?.metadata["remote_task_status_seq"], "3")
    XCTAssertEqual(running?.metadata["remote_task_status_updated_at"], "2500")
    XCTAssertEqual(failed?.message, "desktop failed")
    XCTAssertEqual(failed?.metadata["awaiting_response"], "false")
    XCTAssertEqual(failed?.metadata["remote_task_status"], "failed")
    XCTAssertEqual(failed?.metadata["remote_task_status_seq"], "4")
    XCTAssertNil(provider.recordConnectorTaskStatus(
      sourceMessageId: 51,
      contactId: "codex",
      taskId: "task-51",
      taskStatus: "running",
      statusSeq: 5,
      conversationId: "conversation",
      turnId: "turn",
      nowMillis: 5000
    ))
  }
}
