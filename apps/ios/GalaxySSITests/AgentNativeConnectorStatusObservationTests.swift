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
      "native_connector_observation_started_at", "native_connector_observation_elapsed_ms", "native_connector_observation_deadline_ms"]
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
