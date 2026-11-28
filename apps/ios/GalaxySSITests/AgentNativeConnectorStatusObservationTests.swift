import XCTest
@testable import GalaxySSI

final class AgentNativeConnectorStatusObservationTests: XCTestCase {
  private func fixture() throws -> (pending: AgentActionResult, managed: AgentManagedResponseRecord,
                                    observation: AgentDesktopReplyRecoveryRecord) {
    let managed = AgentManagedResponseRecord(ownerRunId: "owner", supervisorRunId: "parent", agentId: "registered-agent",
      deliveryMode: .respond, sourceMessageId: 123, contactId: "desktop-a:codex", conversationId: "conversation",
      turnId: "turn", taskId: "remote-task", executionGeneration: 2, createdAtMillis: 1_000)
    let identity = AgentTaskIdentity(clientRouteId: "route", conversationId: "conversation", taskId: "remote-task", turnId: "turn")
    let binding = try XCTUnwrap(AgentDesktopReplyBinding.managed(record: managed,
      desktopId: "desktop-a", agentId: "codex", identity: identity))
    var observation = AgentDesktopReplyRecoveryRecord(binding: binding, createdAt: 1_000)
    observation.generation = 2
    observation.sequence = 3
    observation.status = "running"
    observation.lastResponseAt = 4_000
    let pending = AgentActionResult(actionId: "action", success: true, message: "Queued",
      metadata: ["awaiting_response": "true", "completion_verified": "false", "source_message_id": "123",
        "contact_id": managed.contactId, "conversation_id": "conversation", "turn_id": "turn", "task_id": "remote-task",
        "remote_task_id": "remote-task", "remote_task_status": "queued", "remote_task_status_seq": "1",
        "remote_task_status_updated_at": "2000", "execution_generation": "2",
        "control_plane_run_id": "owner", "control_plane_agent_id": "registered-agent", "auto_reroute_on_failure": "true"])
    return (pending, managed, observation)
  }

  func testFirstAuthenticatedStatusAnchorsAcceptanceWithoutResettingLaterProgress() throws {
    let f = try fixture()
    for status in ["queued", "running"] {
      var pending = f.pending
      for key in ["remote_task_status", "remote_task_status_seq", "remote_task_status_updated_at"] {
        pending.metadata.removeValue(forKey: key)
      }
      pending.metadata["resource_started_at"] = "1000"
      pending.metadata["routing_requires_live_data"] = "true"
      var observation = f.observation
      observation.status = status
      let first = try XCTUnwrap(AgentNativeConnectorStatusObservation.apply(pending: pending,
        managed: f.managed, observation: observation))
      XCTAssertEqual(first.metadata["transport_accepted_at"], "4000")
      observation.sequence += 1
      observation.lastResponseAt = 5_000
      let later = try XCTUnwrap(AgentNativeConnectorStatusObservation.apply(pending: first,
        managed: f.managed, observation: observation))
      XCTAssertEqual(later.metadata["transport_accepted_at"], "4000")
      XCTAssertEqual(later.metadata["remote_task_status_updated_at"], "5000")
      let now: Int64 = status == "queued" ? 49_000 : 65_000
      let stage: AgentConnectorTimeoutStage = status == "queued" ? .notRunning : .readOnlyStale
      XCTAssertEqual(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: later.metadata,
        nowMillis: now)["native_connector_observation_timeout_stage"], stage.rawValue)
      XCTAssertEqual(later.metadata["awaiting_response"], "true")
      XCTAssertEqual(later.metadata["completion_verified"], "false")
    }
  }

  func testRemoteStatusPreservesAnExistingAcceptanceAnchor() throws {
    let f = try fixture()
    var pending = f.pending
    pending.metadata["transport_accepted_at"] = "1500"
    let result = try XCTUnwrap(AgentNativeConnectorStatusObservation.apply(pending: pending,
      managed: f.managed, observation: f.observation))
    XCTAssertEqual(result.metadata["transport_accepted_at"], "1500")
    XCTAssertEqual(result.metadata["remote_task_status_updated_at"], "4000")
    XCTAssertEqual(try JSONDecoder().decode(AgentActionResult.self, from: JSONEncoder().encode(result)), result)
  }

  func testOwnedProgressPersistsStatusWithoutChangingExecutionResultOrIdentity() throws {
    let f = try fixture()
    let result = try XCTUnwrap(AgentNativeConnectorStatusObservation.apply(pending: f.pending, managed: f.managed,
      observation: f.observation))
    XCTAssertEqual(result.metadata["remote_task_status"], "running")
    XCTAssertEqual(result.metadata["remote_task_status_seq"], "3")
    XCTAssertEqual(result.metadata["remote_task_status_updated_at"], "4000")
    XCTAssertEqual(result.actionId, f.pending.actionId)
    XCTAssertEqual(result.success, f.pending.success)
    XCTAssertEqual(result.message, f.pending.message)
    for key in ["awaiting_response", "completion_verified", "contact_id", "conversation_id", "turn_id", "task_id",
      "source_message_id", "control_plane_run_id", "control_plane_agent_id", "auto_reroute_on_failure"] {
      XCTAssertEqual(result.metadata[key], f.pending.metadata[key], key)
    }
    XCTAssertEqual(try JSONDecoder().decode(AgentActionResult.self, from: JSONEncoder().encode(result)), result)
  }

  func testDuplicateAndOlderSequenceDoNotRefreshStaleClock() throws {
    let f = try fixture()
    let applied = try XCTUnwrap(AgentNativeConnectorStatusObservation.apply(pending: f.pending, managed: f.managed,
      observation: f.observation))
    for sequence in [Int64(0), 1, 2, 3] {
      var duplicate = f.observation
      duplicate.sequence = sequence
      duplicate.lastResponseAt = 100_000
      XCTAssertNil(AgentNativeConnectorStatusObservation.apply(pending: applied, managed: f.managed, observation: duplicate))
    }
    var progress = f.observation
    progress.sequence = 4
    progress.lastResponseAt = 5_000
    XCTAssertEqual(AgentNativeConnectorStatusObservation.apply(pending: applied, managed: f.managed,
      observation: progress)?.metadata["remote_task_status_updated_at"], "5000")
  }

  func testPendingScopeMustMatchEveryExactManagedIdentityField() throws {
    let f = try fixture()
    for key in ["control_plane_run_id", "control_plane_agent_id", "source_message_id", "contact_id",
      "conversation_id", "turn_id", "task_id", "execution_generation"] {
      for value in ["", "foreign"] {
        var other = f.pending
        other.metadata[key] = value
        XCTAssertNil(AgentNativeConnectorStatusObservation.apply(pending: other, managed: f.managed,
          observation: f.observation), key)
      }
    }
    var noWait = f.pending
    noWait.metadata["awaiting_response"] = "false"
    XCTAssertNil(AgentNativeConnectorStatusObservation.apply(pending: noWait, managed: f.managed, observation: f.observation))
  }

  func testForeignBindingAndGenerationCannotUpdateOriginalWait() throws {
    let f = try fixture()
    let changes: [(inout AgentDesktopReplyRecoveryRecord) -> Void] = [
      { $0.binding.managedSource?.ownerRunId = "foreign" }, { $0.binding.managedSource?.sourceMessageId = 456 },
      { $0.binding.managedSource?.executionGeneration = 3 }, { $0.binding.contactId = "desktop-b:codex" },
      { $0.binding.identity.conversationId = "other" }, { $0.binding.identity.turnId = "other" },
      { $0.binding.identity.taskId = "other" }, { $0.generation = 1 }, { $0.generation = 3 },
      { $0.binding.managedSource = nil }, { $0.binding.goalWork = true }
    ]
    for change in changes {
      var other = f.observation
      change(&other)
      XCTAssertNil(AgentNativeConnectorStatusObservation.apply(pending: f.pending, managed: f.managed, observation: other))
    }
  }

  func testTerminalStatusAloneNeitherSettlesNorErasesUnknownEffectEvidence() throws {
    let f = try fixture()
    var pending = f.pending
    for key in ["native_connector_dispatch_uncertain", "effect_outcome_unknown", "non_retriable"] { pending.metadata[key] = "true" }
    pending.metadata["error_code"] = "effect_outcome_unknown"
    pending.metadata["evidence"] = "original unknown effect"
    for status in ["completed", "failed", "timed_out", "cancelled"] {
      var observation = f.observation
      observation.status = status
      let result = try XCTUnwrap(AgentNativeConnectorStatusObservation.apply(pending: pending, managed: f.managed, observation: observation))
      XCTAssertEqual(result.metadata["remote_task_status"], status)
      XCTAssertEqual(result.metadata["awaiting_response"], "true")
      XCTAssertEqual(result.metadata["completion_verified"], "false")
      for key in ["native_connector_dispatch_uncertain", "effect_outcome_unknown", "non_retriable", "error_code", "evidence"] {
        XCTAssertEqual(result.metadata[key], pending.metadata[key], key)
      }
      XCTAssertNil(AgentNativeConnectorContinuation.settle(result, record: f.managed))
    }
  }

  func testCommittedManagedResponseAndKnownTerminalStatusCannotRegress() throws {
    let f = try fixture()
    for state in [AgentManagedResponseState.completed, .applied] {
      var managed = f.managed
      managed.state = state
      XCTAssertNil(AgentNativeConnectorStatusObservation.apply(pending: f.pending, managed: managed, observation: f.observation))
    }
    for status in ["completed", "failed", "timed_out", "cancelled"] {
      var pending = f.pending
      pending.metadata["remote_task_status"] = status
      XCTAssertNil(AgentNativeConnectorStatusObservation.apply(pending: pending, managed: f.managed, observation: f.observation))
    }
  }

  func testOnlyObservationWarningsAreClearedOnRealStatusAdvance() throws {
    let f = try fixture()
    var pending = f.pending
    let warnings = ["native_connector_observation_overdue", "native_connector_observation_timeout_stage",
      "native_connector_observation_started_at", "native_connector_observation_elapsed_ms", "native_connector_observation_deadline_ms",
      "native_connector_observation_deadline_clock", "native_connector_observation_deadline_observed_at"]
    for key in warnings { pending.metadata[key] = "original" }
    pending.metadata["manual_target_locked"] = "true"
    let result = try XCTUnwrap(AgentNativeConnectorStatusObservation.apply(pending: pending, managed: f.managed, observation: f.observation))
    XCTAssertTrue(warnings.allSatisfy { result.metadata[$0] == nil })
    XCTAssertEqual(result.metadata["manual_target_locked"], "true")
    XCTAssertEqual(result.metadata["auto_reroute_on_failure"], "true")
  }

  func testObservedStatusRoundTripsInTheOriginalWaitingReceipt() throws {
    let f = try fixture()
    let action = AgentAction(id: "action", kind: .callConnector, target: "Codex", risk: .low,
      status: .proposed, description: "Inspect project", parameters: ["connector_id": f.managed.contactId,
        "_galaxyssi_task_id": "turn", "_galaxyssi_session_id": "conversation",
        "_galaxyssi_conversation_id": "conversation", "_galaxyssi_turn_id": "turn"], requiresConfirmation: false)
    let owner = AgentControlPlaneActionExecutor.connectorRunId(action: action, agentId: f.managed.agentId)
    var managed = f.managed
    managed.ownerRunId = owner
    var observation = f.observation
    observation.binding.managedSource?.ownerRunId = owner
    var pending = f.pending
    pending.metadata["control_plane_run_id"] = owner
    let observed = try XCTUnwrap(AgentNativeConnectorStatusObservation.apply(pending: pending, managed: managed, observation: observation))
    let task = AgentTaskRecord(taskId: "turn", sessionId: "conversation", goal: "Inspect project",
      phase: .waitingResponse, routeKind: .localSystem, targetTitle: "Codex", risk: .low, blocked: false)
    let outgoing = ChatMessage(contactId: "hermes", content: task.goal, isMine: true, conversationId: "conversation", turnId: "turn")
    let waiting = try XCTUnwrap(AgentNativeConnectorContinuation.waitingAction(action, result: observed, task: task, outgoing: outgoing))
    let reopened = try JSONDecoder().decode(AgentAction.self, from: JSONEncoder().encode(waiting))
    XCTAssertEqual(AgentNativeConnectorContinuation.pendingResult(reopened), observed)
    XCTAssertEqual(reopened.status, .waitingResponse)
    XCTAssertEqual(reopened.parameters[AgentNativeConnectorContinuation.sourceKey], outgoing.id.uuidString)
  }

  private func deadlinePending(_ values: [String: String] = [:]) -> AgentActionResult {
    AgentActionResult(actionId: "deadline-action", success: true, message: "Waiting for original reply",
      metadata: ["awaiting_response": "true", "resource_started_at": "1000", "completion_verified": "false",
        "manual_target_locked": "true", "auto_reroute_on_failure": "false"].merging(values) { _, latest in latest })
  }

  func testDeadlineObservationStartsAtActualUnacceptedBoundary() throws {
    let pending = deadlinePending()
    XCTAssertNil(AgentNativeConnectorDeadlineObservation.apply(pending: pending, nowMillis: 15_999))
    let result = try XCTUnwrap(AgentNativeConnectorDeadlineObservation.apply(pending: pending, nowMillis: 16_000))
    XCTAssertEqual(result.metadata["native_connector_observation_timeout_stage"], AgentConnectorTimeoutStage.notAccepted.rawValue)
    XCTAssertEqual(result.metadata["native_connector_observation_elapsed_ms"], "15000")
    XCTAssertEqual(result.metadata["native_connector_observation_deadline_observed_at"], "16000")
    XCTAssertEqual(result.message, pending.message)
    XCTAssertEqual(result.success, pending.success)
  }

  func testDeadlineObservationRetainsAcceptanceAndAttachmentWindows() throws {
    for (attachments, window) in [(false, Int64(45_000)), (true, 90_000)] {
      let pending = deadlinePending(["transport_accepted_at": "2000", "remote_task_status": "queued",
        "has_attachments": String(attachments)])
      XCTAssertNil(AgentNativeConnectorDeadlineObservation.apply(pending: pending, nowMillis: 2_000 + window - 1))
      let result = try XCTUnwrap(AgentNativeConnectorDeadlineObservation.apply(pending: pending, nowMillis: 2_000 + window))
      XCTAssertEqual(result.metadata["transport_accepted_at"], "2000")
      XCTAssertEqual(result.metadata["native_connector_observation_timeout_stage"], AgentConnectorTimeoutStage.notRunning.rawValue)
      XCTAssertEqual(result.metadata["native_connector_observation_deadline_ms"], String(window))
    }
  }

  func testDeadlineObservationForLiveRunningUsesLastRemoteProgress() throws {
    let pending = deadlinePending(["transport_accepted_at": "2000", "remote_task_status": "running",
      "remote_task_status_seq": "2", "remote_task_status_updated_at": "10000", "routing_requires_live_data": "true"])
    XCTAssertNil(AgentNativeConnectorDeadlineObservation.apply(pending: pending, nowMillis: 69_999))
    let result = try XCTUnwrap(AgentNativeConnectorDeadlineObservation.apply(pending: pending, nowMillis: 70_000))
    XCTAssertEqual(result.metadata["native_connector_observation_started_at"], "10000")
    XCTAssertEqual(result.metadata["native_connector_observation_timeout_stage"], AgentConnectorTimeoutStage.readOnlyStale.rawValue)
    var ordinary = pending; ordinary.metadata["routing_requires_live_data"] = "false"
    XCTAssertNil(AgentNativeConnectorDeadlineObservation.apply(pending: ordinary, nowMillis: 70_000))
  }

  func testDeadlineObservationDoesNotReclassifyRemoteWaitOrTerminalStates() {
    for status in ["completed", "failed", "timed_out", "cancelled", "waiting_input", "waiting_approval", "paused", "recovering"] {
      let pending = deadlinePending(["transport_accepted_at": "2000", "remote_task_status": status])
      XCTAssertNil(AgentNativeConnectorDeadlineObservation.apply(pending: pending, nowMillis: 1_000_000), status)
    }
    XCTAssertNil(AgentNativeConnectorDeadlineObservation.apply(pending: deadlinePending(["awaiting_response": "false"]), nowMillis: 16_000))
  }

  func testDeadlineObservationIsOneCheckpointNotRepeatedFreshEvidence() throws {
    let observed = try XCTUnwrap(AgentNativeConnectorDeadlineObservation.apply(pending: deadlinePending(), nowMillis: 16_000))
    XCTAssertNil(AgentNativeConnectorDeadlineObservation.apply(pending: observed, nowMillis: 46_000))
    var accepted = observed
    accepted.metadata["transport_accepted_at"] = "20000"; accepted.metadata["remote_task_status"] = "queued"
    XCTAssertNil(AgentNativeConnectorDeadlineObservation.apply(pending: accepted, nowMillis: 64_999))
    XCTAssertEqual(AgentNativeConnectorDeadlineObservation.apply(pending: accepted, nowMillis: 65_000)?
      .metadata["native_connector_observation_deadline_observed_at"], "65000")
  }

  func testDeadlineObservationLegacyClocksMatchWakePolicyWithoutInventedAcceptance() throws {
    let pending = deadlinePending(["remote_task_status": "queued"])
    let observed = try XCTUnwrap(AgentNativeConnectorDeadlineObservation.apply(pending: pending, nowMillis: 16_000))
    XCTAssertEqual(observed.metadata["native_connector_observation_timeout_stage"], AgentConnectorTimeoutStage.notAccepted.rawValue)
    XCTAssertEqual(observed.metadata["remote_task_status"], "queued")
    XCTAssertNil(observed.metadata["transport_accepted_at"])
    for value in ["invalid", "0", "-1", "9223372036854775807"] {
      XCTAssertNil(AgentNativeConnectorDeadlineObservation.apply(pending: deadlinePending(["resource_started_at": value]), nowMillis: 16_000))
    }
  }

  func testAdvancingAuthenticatedStatusClearsDeadlineCheckpoint() throws {
    let f = try fixture()
    var pending = f.pending
    pending.metadata["transport_accepted_at"] = "1500"
    let observed = try XCTUnwrap(AgentNativeConnectorDeadlineObservation.apply(pending: pending, nowMillis: 46_500))
    var progress = f.observation; progress.lastResponseAt = 47_000
    let refreshed = try XCTUnwrap(AgentNativeConnectorStatusObservation.apply(pending: observed, managed: f.managed, observation: progress))
    XCTAssertNil(refreshed.metadata["native_connector_observation_deadline_clock"])
    XCTAssertNil(refreshed.metadata["native_connector_observation_deadline_observed_at"])
    XCTAssertNil(refreshed.metadata["native_connector_observation_timeout_stage"])
    XCTAssertEqual(refreshed.metadata["awaiting_response"], "true")
    XCTAssertEqual(refreshed.metadata["transport_accepted_at"], "1500")
  }

  func testDeadlineObservationRoundTripsWithoutFailureReplayOrRouteMetadataChanges() throws {
    let pending = deadlinePending(["source_message_id": "123", "control_plane_run_id": "owner",
      "execution_generation": "2", "remaining_fallback_ids": "other", "evidence": "original"])
    let observed = try XCTUnwrap(AgentNativeConnectorDeadlineObservation.apply(pending: pending, nowMillis: 16_000))
    XCTAssertEqual(try JSONDecoder().decode(AgentActionResult.self, from: JSONEncoder().encode(observed)), observed)
    XCTAssertEqual(observed.actionId, pending.actionId)
    for (key, value) in pending.metadata { XCTAssertEqual(observed.metadata[key], value, key) }
    for key in ["timeout_stage", "error_code", "native_connector_dispatch_uncertain", "native_connector_observation_overdue",
      "effect_outcome_unknown", "non_retriable", "execution_started"] { XCTAssertNil(observed.metadata[key], key) }
  }

  func testMalformedSequenceAndBackwardClockAreRejectedWithoutDefaulting() throws {
    let f = try fixture()
    for value in ["invalid", "-1", "9223372036854775808"] {
      var pending = f.pending
      pending.metadata["remote_task_status_seq"] = value
      XCTAssertNil(AgentNativeConnectorStatusObservation.apply(pending: pending, managed: f.managed, observation: f.observation))
    }
    for time in [Int64(-1), 0, 1_999] {
      var observation = f.observation
      observation.lastResponseAt = time
      XCTAssertNil(AgentNativeConnectorStatusObservation.apply(pending: f.pending, managed: f.managed, observation: observation))
    }
    for sequence in [Int64(-1), 9_007_199_254_740_992] {
      var observation = f.observation
      observation.sequence = sequence
      XCTAssertNil(AgentNativeConnectorStatusObservation.apply(pending: f.pending, managed: f.managed, observation: observation))
    }
    var legacy = f.pending
    legacy.metadata.removeValue(forKey: "remote_task_status_seq")
    XCTAssertNotNil(AgentNativeConnectorStatusObservation.apply(pending: legacy, managed: f.managed, observation: f.observation))
  }
}
