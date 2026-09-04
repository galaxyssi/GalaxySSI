import XCTest
@testable import GalaxySSI

final class AgentConnectorTransportReceiptRecorderTests: XCTestCase {
  func testRecorderStoresTransportAcceptedMetadata() {
    let pending = AgentActionResult(
      actionId: "action",
      success: true,
      message: "Waiting",
      metadata: [
        "awaiting_response": "true",
        "source_message_id": "91",
        "contact_id": "codex"
      ]
    )

    let updated = AgentConnectorTransportReceiptRecorder.recordAccepted(
      pending: pending,
      sourceMessageId: 91,
      contactId: "codex",
      nowMillis: 6000
    )

    XCTAssertEqual(updated?.success, true)
    XCTAssertEqual(updated?.metadata["awaiting_response"], "true")
    XCTAssertEqual(updated?.metadata["remote_task_status"], "accepted")
    XCTAssertEqual(updated?.metadata["remote_task_status_updated_at"], "6000")
    XCTAssertEqual(updated?.metadata["transport_accepted_at"], "6000")
  }

  func testRecorderPreservesExistingRemoteTaskStatusAndRejectsWrongContact() {
    let pending = AgentActionResult(
      actionId: "action",
      success: true,
      message: "Waiting",
      metadata: [
        "awaiting_response": "true",
        "source_message_id": "91",
        "contact_id": "codex",
        "remote_task_status": "running"
      ]
    )

    let wrongContact = AgentConnectorTransportReceiptRecorder.recordAccepted(
      pending: pending,
      sourceMessageId: 91,
      contactId: "other",
      nowMillis: 6000
    )
    let accepted = AgentConnectorTransportReceiptRecorder.recordAccepted(
      pending: pending,
      sourceMessageId: 91,
      contactId: "codex",
      nowMillis: 7000
    )

    XCTAssertNil(wrongContact)
    XCTAssertEqual(accepted?.metadata["remote_task_status"], "running")
    XCTAssertEqual(accepted?.metadata["remote_task_status_updated_at"], "7000")
    XCTAssertEqual(accepted?.metadata["transport_accepted_at"], "7000")
  }
}

extension GalaxySSIStoreTests {
  func testActionExecutorAgentProviderRecordsConnectorTransportAccepted() async throws {
    let registration = actionExecutorRegistration()
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Waiting",
        metadata: [
          "awaiting_response": "true",
          "source_message_id": "91",
          "contact_id": "codex"
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
      runId: "run-transport-accepted",
      goal: "Inspect project",
      context: ["managed_team": .bool(true)],
      idempotencyKey: "run-transport-accepted"
    )
    provider.prepare(
      agentId: "codex",
      request: request,
      action: actionExecutorConnectorAction(),
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")
    )

    _ = try await adapter.startRun(request)
    let accepted = provider.recordConnectorTransportAccepted(
      sourceMessageId: 91,
      contactId: "codex",
      nowMillis: 6000
    )
    let running = provider.recordConnectorTaskStatus(
      sourceMessageId: 91,
      contactId: "codex",
      taskId: "task-91",
      taskStatus: "running",
      statusSeq: 2,
      nowMillis: 7000
    )

    XCTAssertEqual(accepted?.metadata["remote_task_status"], "accepted")
    XCTAssertEqual(accepted?.metadata["transport_accepted_at"], "6000")
    XCTAssertEqual(running?.metadata["remote_task_status"], "running")
    XCTAssertEqual(running?.metadata["transport_accepted_at"], "6000")
  }
}
