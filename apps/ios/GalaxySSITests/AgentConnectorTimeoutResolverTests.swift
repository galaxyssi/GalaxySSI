import XCTest
@testable import GalaxySSI

final class AgentConnectorTimeoutResolverTests: XCTestCase {
  func testResolverFailsAcceptedStatusOnNotRunningWhenFallbackExists() {
    let pending = AgentActionResult(
      actionId: "action",
      success: true,
      message: "Waiting",
      metadata: [
        "awaiting_response": "true",
        "source_message_id": "33",
        "remote_task_status": "accepted",
        "remaining_fallback_ids": "cloud,codex-2",
        "resource_started_at": "1000",
        "target": "Codex Desktop"
      ]
    )

    let timeout = AgentConnectorTimeoutResolver.resolve(
      pending: pending,
      sourceMessageId: 33,
      stage: .notRunning,
      nowMillis: 4500
    )

    XCTAssertEqual(timeout?.result.success, false)
    XCTAssertEqual(timeout?.result.message, "Codex Desktop timed out")
    XCTAssertEqual(timeout?.result.metadata["awaiting_response"], "false")
    XCTAssertEqual(timeout?.result.metadata["timeout_stage"], "NOT_RUNNING")
    XCTAssertEqual(timeout?.result.metadata["timeout_elapsed_ms"], "3500")
    XCTAssertEqual(timeout?.eventPayload["timeout_stage"]?.stringValue, "NOT_RUNNING")
  }

  func testResolverKeepsOnlyWaitingResourceAliveWithoutFallback() {
    let pending = AgentActionResult(
      actionId: "action",
      success: true,
      message: "Waiting",
      metadata: [
        "awaiting_response": "true",
        "source_message_id": "33",
        "remote_task_status": "queued",
        "resource_started_at": "1000"
      ]
    )

    XCTAssertNil(AgentConnectorTimeoutResolver.resolve(
      pending: pending,
      sourceMessageId: 33,
      stage: .notRunning,
      nowMillis: 4500
    ))
  }

  func testResolverRequiresLiveFallbackForReadOnlyStale() {
    let pending = AgentActionResult(
      actionId: "action",
      success: true,
      message: "Waiting",
      metadata: [
        "awaiting_response": "true",
        "source_message_id": "33",
        "remote_task_status": "running",
        "routing_requires_live_data": "true",
        "resource_started_at": "1000"
      ]
    )
    var withFallback = pending
    withFallback.metadata["remaining_fallback_ids"] = "cloud"

    XCTAssertNil(AgentConnectorTimeoutResolver.resolve(
      pending: pending,
      sourceMessageId: 33,
      stage: .readOnlyStale,
      nowMillis: 4500
    ))
    XCTAssertEqual(
      AgentConnectorTimeoutResolver.resolve(
        pending: withFallback,
        sourceMessageId: 33,
        stage: .readOnlyStale,
        nowMillis: 4500
      )?.result.metadata["timeout_stage"],
      "READ_ONLY_STALE"
    )
  }
}

extension GalaxySSIStoreTests {
  func testActionExecutorAgentProviderHandlesConnectorTimeout() async throws {
    let registration = actionExecutorRegistration()
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Waiting",
        metadata: [
          "awaiting_response": "true",
          "source_message_id": "33",
          "remote_task_status": "accepted",
          "remaining_fallback_ids": "cloud",
          "resource_started_at": "1000",
          "target": "Codex Desktop"
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
      runId: "run-timeout",
      goal: "Inspect project",
      context: ["managed_team": .bool(true)],
      idempotencyKey: "run-timeout"
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
    let timeout = provider.handleConnectorTimeout(
      sourceMessageId: 33,
      stage: .notRunning,
      nowMillis: 4500
    )
    let failed = await iterator.next()

    XCTAssertEqual(timeout?.success, false)
    XCTAssertEqual(timeout?.message, "Codex Desktop timed out")
    XCTAssertEqual(timeout?.metadata["awaiting_response"], "false")
    XCTAssertEqual(timeout?.metadata["timeout_stage"], "NOT_RUNNING")
    XCTAssertEqual(timeout?.metadata["timeout_elapsed_ms"], "3500")
    XCTAssertEqual(failed?.type, .runFailed)
    XCTAssertEqual(failed?.payload["timeout_stage"]?.stringValue, "NOT_RUNNING")
    XCTAssertNil(provider.recordConnectorTaskStatus(
      sourceMessageId: 33,
      contactId: "",
      taskId: "task-33",
      taskStatus: "running",
      statusSeq: 2,
      nowMillis: 5000
    ))
  }
}
