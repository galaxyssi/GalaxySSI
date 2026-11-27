import XCTest
@testable import GalaxySSI

final class AgentConnectorTimeoutResolverTests: XCTestCase {
  func testActiveObservationWakeUsesUnacceptedAndAcceptedStageClocks() throws {
    var metadata = ["awaiting_response": "true", "resource_started_at": "1000"]
    let first = try XCTUnwrap(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 2_000))
    XCTAssertEqual(first.stage, .notAccepted)
    XCTAssertEqual(first.delayMillis, 14_000)
    XCTAssertEqual(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 16_000)?.delayMillis, 0)
    metadata["transport_accepted_at"] = "20000"
    metadata["remote_task_status"] = "accepted"
    let accepted = try XCTUnwrap(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 21_000))
    XCTAssertEqual(accepted.stage, .notRunning)
    XCTAssertEqual(accepted.startedAt, 20_000)
    XCTAssertEqual(accepted.delayMillis, 44_000)
    XCTAssertNotEqual(first.clock, accepted.clock)
  }

  func testActiveObservationWakeDoesNotRefreshAClockOnTransportMetadataAlone() throws {
    var metadata = ["awaiting_response": "true", "resource_started_at": "1000", "transport_accepted_at": "2000",
      "remote_task_status": "queued", "remote_task_status_updated_at": "40000"]
    let wake = try XCTUnwrap(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 46_000))
    XCTAssertEqual(wake.delayMillis, 1_000)
    metadata["remote_task_status_updated_at"] = "45000"
    XCTAssertEqual(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 46_000), wake)
  }

  func testActiveObservationWakeUsesLiveProgressOnlyForReadOnlyWork() throws {
    var metadata = ["awaiting_response": "true", "resource_started_at": "1000", "transport_accepted_at": "2000",
      "remote_task_status": "running", "remote_task_status_updated_at": "30000"]
    XCTAssertNil(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 40_000))
    metadata["routing_requires_live_data"] = "true"
    let wake = try XCTUnwrap(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 40_000))
    XCTAssertEqual(wake.stage, .readOnlyStale)
    XCTAssertEqual(wake.delayMillis, 50_000)
    metadata["remote_task_status_updated_at"] = "40000"
    XCTAssertNotEqual(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 40_000)?.clock, wake.clock)
  }

  func testActiveObservationWakeRetainsAttachmentAndProbeIntervals() throws {
    var metadata = ["awaiting_response": "true", "resource_started_at": "1000", "has_attachments": "true"]
    XCTAssertEqual(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 2_000)?.delayMillis, 59_000)
    metadata["transport_accepted_at"] = "2000"
    metadata["remote_task_status"] = "queued"
    XCTAssertEqual(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 3_000)?.delayMillis, 89_000)
    metadata["remote_task_status"] = "running"
    metadata["routing_requires_live_data"] = "true"
    XCTAssertEqual(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 3_000)?.delayMillis, 179_000)
    XCTAssertEqual(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 200_000,
      lastWakeMillis: 190_000)?.delayMillis, AgentDesktopReplyRecoveryRecord.probeInterval - 10_000)
  }

  func testActiveObservationWakeLegacyQueueIsNotPersistedAsRemoteAcceptance() throws {
    let metadata = ["awaiting_response": "true", "resource_started_at": "1000", "remote_task_status": "queued"]
    XCTAssertEqual(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 16_000)?.stage, .notAccepted)
    XCTAssertEqual(metadata["remote_task_status"], "queued")
    XCTAssertNil(metadata["transport_accepted_at"])
    var observed = metadata
    observed["remote_task_status_seq"] = "1"
    observed["remote_task_status_updated_at"] = "2000"
    let wake = try XCTUnwrap(AgentNativeConnectorObservationWakePolicy.next(metadata: observed, nowMillis: 3_000))
    XCTAssertEqual(wake.stage, .notRunning)
    XCTAssertEqual(wake.startedAt, 2_000)
    XCTAssertNil(observed["transport_accepted_at"])
  }

  func testActiveObservationWakeIgnoresTerminalUserWaitAndUnownedMetadata() {
    let base = ["awaiting_response": "true", "resource_started_at": "1000", "transport_accepted_at": "2000"]
    for status in ["completed", "failed", "timed_out", "cancelled", "waiting_input", "waiting_approval", "recovering"] {
      var metadata = base
      metadata["remote_task_status"] = status
      XCTAssertNil(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 100_000), status)
    }
    var metadata = base
    metadata["awaiting_response"] = "false"
    XCTAssertNil(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 100_000))
    XCTAssertNil(AgentNativeConnectorObservationWakePolicy.next(metadata: [:], nowMillis: 100_000))
  }

  func testActiveObservationWakeRejectsMalformedAndFutureAnchors() {
    for invalid in ["0", "-1", "invalid", String(Int64.max)] {
      let metadata = ["awaiting_response": "true", "resource_started_at": invalid]
      XCTAssertNil(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 100_000))
    }
    var metadata = ["awaiting_response": "true", "resource_started_at": "1000", "remote_task_status_seq": "invalid"]
    XCTAssertNil(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 100_000))
    metadata.removeValue(forKey: "remote_task_status_seq")
    metadata["transport_accepted_at"] = "invalid"
    XCTAssertNil(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 100_000))
  }

  func testActiveObservationWakeDoesNotAuthorizeFailureOrChangeRoutingMetadata() {
    let metadata = ["awaiting_response": "true", "resource_started_at": "1000", "manual_target_locked": "true",
      "effect_outcome_unknown": "true", "non_retriable": "true", "auto_reroute_on_failure": "false"]
    let copy = metadata
    XCTAssertEqual(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 50_000)?.delayMillis, 0)
    XCTAssertEqual(metadata, copy)
    XCTAssertEqual(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata, nowMillis: 50_000,
      lastWakeMillis: 60_000)?.delayMillis, 0)
  }

  func testObservationDeadlineUsesStageSpecificAnchors() {
    let metadata = ["resource_started_at": "1000", "transport_accepted_at": "12000",
      "remote_task_status_updated_at": "23000"]
    XCTAssertEqual(AgentConnectorTimingPolicy.deadlineStartMillis(stage: .notAccepted, metadata: metadata), 1000)
    XCTAssertEqual(AgentConnectorTimingPolicy.deadlineStartMillis(stage: .notRunning, metadata: metadata), 12000)
    XCTAssertEqual(AgentConnectorTimingPolicy.deadlineStartMillis(stage: .readOnlyStale, metadata: metadata), 23000)
    var malformed = metadata
    malformed["remote_task_status_updated_at"] = "invalid"
    XCTAssertEqual(AgentConnectorTimingPolicy.deadlineStartMillis(stage: .readOnlyStale, metadata: malformed), 12000)
    XCTAssertEqual(AgentConnectorTimingPolicy.deadlineStartMillis(stage: .notRunning, metadata: [:]), 0)
  }

  func testObservationAcceptanceBoundaryIsInformationalOnly() {
    let metadata = ["awaiting_response": "true", "resource_started_at": "1000",
      "manual_target_locked": "true", "remaining_fallback_ids": "cloud"]
    XCTAssertTrue(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: metadata, nowMillis: 15_999).isEmpty)
    let observed = AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: metadata, nowMillis: 16_000)
    XCTAssertEqual(observed["native_connector_observation_timeout_stage"], "NOT_ACCEPTED")
    XCTAssertEqual(observed["native_connector_observation_elapsed_ms"], "15000")
    XCTAssertEqual(observed["native_connector_observation_deadline_ms"], "15000")
    XCTAssertEqual(observed.count, 4)
    XCTAssertTrue(observed.keys.allSatisfy { $0.hasPrefix("native_connector_observation_") })
    XCTAssertEqual(metadata["awaiting_response"], "true")
    XCTAssertEqual(metadata["manual_target_locked"], "true")
    XCTAssertNil(observed["timeout_stage"])
    XCTAssertNil(observed["non_retriable"])
  }

  func testObservationRunningWindowStartsAtTransportAcceptance() {
    let metadata = ["awaiting_response": "true", "resource_started_at": "1000",
      "transport_accepted_at": "50000", "remote_task_status": "queued"]
    XCTAssertTrue(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: metadata, nowMillis: 94_999).isEmpty)
    let observed = AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: metadata, nowMillis: 95_000)
    XCTAssertEqual(observed["native_connector_observation_timeout_stage"], "NOT_RUNNING")
    XCTAssertEqual(observed["native_connector_observation_started_at"], "50000")
    XCTAssertEqual(observed["native_connector_observation_elapsed_ms"], "45000")
  }

  func testObservationLiveWindowUsesHeartbeatWithoutFailingOrdinaryRuns() {
    var metadata = ["awaiting_response": "true", "transport_accepted_at": "1000",
      "remote_task_status_updated_at": "90000", "remote_task_status": "running",
      "routing_requires_live_data": "true"]
    XCTAssertTrue(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: metadata, nowMillis: 149_999).isEmpty)
    XCTAssertEqual(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: metadata,
      nowMillis: 150_000)["native_connector_observation_timeout_stage"], "READ_ONLY_STALE")
    metadata["routing_requires_live_data"] = "false"
    XCTAssertTrue(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: metadata, nowMillis: 900_000).isEmpty)
    metadata["routing_requires_live_data"] = "true"
    for status in ["completed", "failed", "cancelled", "waiting_input", "waiting_approval", "unknown"] {
      metadata["remote_task_status"] = status
      XCTAssertTrue(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: metadata, nowMillis: 900_000).isEmpty)
    }
  }

  func testObservationRejectsMissingFutureAndInvalidClocks() {
    for start in ["", "invalid", "0", "-1", "9223372036854775807"] {
      let metadata = ["awaiting_response": "true", "resource_started_at": start]
      XCTAssertTrue(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: metadata, nowMillis: 50_000).isEmpty)
    }
    let metadata = ["awaiting_response": "false", "resource_started_at": "1000"]
    XCTAssertTrue(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: metadata, nowMillis: 50_000).isEmpty)
    XCTAssertTrue(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: ["awaiting_response": "true",
      "resource_started_at": "1000"], nowMillis: -1).isEmpty)
  }

  func testObservationAttachmentWindowsRemainLongerThanInteractive() {
    var metadata = ["awaiting_response": "true", "resource_started_at": "1000", "has_attachments": "true"]
    XCTAssertTrue(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: metadata, nowMillis: 60_999).isEmpty)
    XCTAssertEqual(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: metadata,
      nowMillis: 61_000)["native_connector_observation_deadline_ms"], "60000")
    metadata["transport_accepted_at"] = "1000"
    metadata["remote_task_status"] = "accepted"
    XCTAssertTrue(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: metadata, nowMillis: 90_999).isEmpty)
    XCTAssertEqual(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: metadata,
      nowMillis: 91_000)["native_connector_observation_deadline_ms"], "90000")
    metadata["remote_task_status"] = "running"
    metadata["routing_requires_live_data"] = "true"
    XCTAssertTrue(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: metadata, nowMillis: 180_999).isEmpty)
    XCTAssertEqual(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: metadata,
      nowMillis: 181_000)["native_connector_observation_deadline_ms"], "180000")
  }

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
