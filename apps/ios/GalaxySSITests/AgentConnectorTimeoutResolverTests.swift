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
  func testManualTimeoutStopsWithoutGrantingUnavailableTargetFallback() throws {
    let pending = AgentActionResult(actionId: "manual", success: true, message: "Waiting", metadata: [
      "awaiting_response": "true", "source_message_id": "33", "remaining_fallback_ids": "other",
      "manual_target_locked": "true", "allow_unavailable_target_fallback": "true", "response_language": "en",
      "resource_id": "selected-codex", "manual_model_id": "chosen-model", "resource_started_at": "1000"
    ])
    let result = try XCTUnwrap(AgentConnectorTimeoutResolver.resolve(pending: pending, sourceMessageId: 33,
      stage: .notAccepted, nowMillis: 181_000))
    XCTAssertFalse(result.result.success)
    XCTAssertEqual(result.result.message, AgentManualModelRecoveryPolicy.englishMessage)
    XCTAssertEqual(result.eventPayload["message"]?.stringValue, result.result.message)
    XCTAssertEqual(result.result.metadata["allow_unavailable_target_fallback"], "false")
    XCTAssertEqual(result.result.metadata["non_retriable"], "true")
    XCTAssertEqual(result.result.metadata["resource_id"], "selected-codex")
    XCTAssertEqual(result.result.metadata["manual_model_id"], "chosen-model")
    XCTAssertTrue(result.shouldDeactivateRun)
  }
}

extension GalaxySSIStoreTests {
  func testActionExecutorPinsManualLockBeforeTransportTimeout() async throws {
    let registration = actionExecutorRegistration()
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(actionId: action.id, success: true, message: "Waiting", metadata: [
        "awaiting_response": "true", "source_message_id": "33", "remaining_fallback_ids": "other",
        "manual_target_locked": "false", "response_language": "zh-CN", "resource_id": "selected-codex"
      ])
    }
    let provider = ActionExecutorAgentProvider(registrationSource: { [registration] }, delegate: delegate)
    let adapter = try XCTUnwrap(try await provider.adapter(agentId: "codex"))
    var action = actionExecutorConnectorAction()
    action.parameters["manual_target_locked"] = "true"; action.parameters["response_language"] = "en"
    let request = AgentRunRequest(conversationId: "conversation", messageId: "turn", taskId: "turn",
      runId: "manual-timeout", goal: "Inspect project", context: ["managed_team": .bool(true)], idempotencyKey: "manual-timeout")
    provider.prepare(agentId: "codex", request: request, action: action,
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent"))
    _ = try await adapter.startRun(request)
    let timeout = try XCTUnwrap(provider.handleConnectorTimeout(sourceMessageId: 33, stage: .notAccepted, nowMillis: 181_000))
    XCTAssertEqual(timeout.metadata["manual_target_locked"], "true")
    XCTAssertEqual(timeout.metadata["allow_unavailable_target_fallback"], "false")
    XCTAssertEqual(timeout.metadata["response_language"], "en")
    XCTAssertEqual(timeout.message, AgentManualModelRecoveryPolicy.englishMessage)
  }
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
