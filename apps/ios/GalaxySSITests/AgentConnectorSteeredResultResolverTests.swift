import XCTest
@testable import GalaxySSI

final class AgentConnectorSteeredResultResolverTests: XCTestCase {
  func testResolverCompletesSteeredConnectorAndClearsTimeoutMetadata() {
    let pending = AgentActionResult(
      actionId: "action",
      success: true,
      message: "Waiting",
      metadata: [
        "awaiting_response": "true",
        "source_message_id": "61",
        "contact_id": "codex",
        "timeout_stage": "NOT_RUNNING",
        "timeout_elapsed_ms": "2500"
      ]
    )

    let steered = AgentConnectorSteeredResultResolver.resolve(
      pending: pending,
      sourceMessageId: 61,
      contactId: "codex",
      mergedIntoTaskId: "merged-task",
      nowMillis: 8000
    )

    XCTAssertEqual(steered?.result.success, true)
    XCTAssertEqual(steered?.result.message, "")
    XCTAssertEqual(steered?.result.metadata["awaiting_response"], "false")
    XCTAssertEqual(steered?.result.metadata["response_received_at"], "8000")
    XCTAssertEqual(steered?.result.metadata["connector_disposition"], "steered")
    XCTAssertEqual(steered?.result.metadata["merged_into_task_id"], "merged-task")
    XCTAssertNil(steered?.result.metadata["timeout_stage"])
    XCTAssertNil(steered?.result.metadata["timeout_elapsed_ms"])
    XCTAssertEqual(steered?.eventPayload["merged_into_task_id"]?.stringValue, "merged-task")
  }

  func testResolverRejectsBlankMergedTaskAndMismatchedDesktopIdentity() {
    let pending = AgentActionResult(
      actionId: "action",
      success: true,
      message: "Waiting",
      metadata: [
        "awaiting_response": "true",
        "source_message_id": "61",
        "resource_location": "desktop",
        "conversation_id": "conversation-a",
        "remote_task_id": "task-a",
        "turn_id": "turn-a"
      ]
    )

    XCTAssertNil(AgentConnectorSteeredResultResolver.resolve(
      pending: pending,
      sourceMessageId: 61,
      contactId: "",
      mergedIntoTaskId: " ",
      conversationId: "conversation-a",
      turnId: "turn-a",
      taskId: "task-a"
    ))
    XCTAssertFalse(AgentConnectorSteeredResultResolver.canAccept(
      pending: pending,
      sourceMessageId: 61,
      contactId: "",
      conversationId: "conversation-a",
      turnId: "turn-a",
      taskId: "task-b"
    ))
  }
}

extension GalaxySSIStoreTests {
  func testActionExecutorAgentProviderAcceptsConnectorSteeredResult() async throws {
    let registration = actionExecutorRegistration()
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Waiting",
        metadata: [
          "awaiting_response": "true",
          "source_message_id": "61",
          "contact_id": "codex",
          "resource_location": "desktop",
          "conversation_id": "conversation",
          "remote_task_id": "task-61",
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
      runId: "run-steered",
      goal: "Inspect project",
      context: ["managed_team": .bool(true)],
      idempotencyKey: "run-steered"
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
    let steered = provider.acceptConnectorSteered(
      sourceMessageId: 61,
      contactId: "codex",
      mergedIntoTaskId: "merged-task",
      conversationId: "conversation",
      turnId: "turn",
      taskId: "task-61",
      nowMillis: 8000
    )
    let completed = await iterator.next()

    XCTAssertEqual(steered?.success, true)
    XCTAssertEqual(steered?.metadata["awaiting_response"], "false")
    XCTAssertEqual(steered?.metadata["connector_disposition"], "steered")
    XCTAssertEqual(steered?.metadata["merged_into_task_id"], "merged-task")
    XCTAssertEqual(completed?.type, .runCompleted)
    XCTAssertEqual(completed?.payload["connector_disposition"]?.stringValue, "steered")
    XCTAssertNil(provider.recordConnectorTaskStatus(
      sourceMessageId: 61,
      contactId: "codex",
      taskId: "task-61",
      taskStatus: "running",
      statusSeq: 2,
      nowMillis: 9000
    ))
  }
}
