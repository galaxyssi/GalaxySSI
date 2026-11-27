import XCTest
@testable import GalaxySSI

final class AgentNativeConnectorObservationExpiryTests: XCTestCase {
  private func fixture() throws -> (AgentActionResult, AgentManagedResponseRecord, AgentDesktopReplyRecoveryRecord) {
    let managed = AgentManagedResponseRecord(ownerRunId: "owner", supervisorRunId: "parent", agentId: "registered-agent",
      deliveryMode: .respond, sourceMessageId: 123, contactId: "desktop:codex", conversationId: "conversation",
      turnId: "turn", taskId: "task", executionGeneration: 2, createdAtMillis: 1_000)
    let identity = AgentTaskIdentity(clientRouteId: "route", conversationId: "conversation", taskId: "task", turnId: "turn")
    let binding = try XCTUnwrap(AgentDesktopReplyBinding.managed(record: managed, desktopId: "desktop",
      agentId: "codex", identity: identity))
    var observation = AgentDesktopReplyRecoveryRecord(binding: binding, createdAt: 1_000)
    observation.generation = 2
    observation.sequence = 3
    observation.status = "running"
    observation.lastResponseAt = 2_000
    observation.lastProbeAt = 302_000
    observation.probeWindowStartedAt = 240_000
    observation.misses = 3
    let pending = AgentActionResult(actionId: "action", success: true, message: "Queued", metadata: [
      "awaiting_response": "true", "completion_verified": "false", "source_message_id": "123",
      "control_plane_run_id": "owner", "control_plane_agent_id": "registered-agent", "contact_id": "desktop:codex",
      "conversation_id": "conversation", "turn_id": "turn", "task_id": "task", "execution_generation": "2",
      "resource_started_at": "1000", "transport_accepted_at": "2000", "remote_task_status": "running",
      "remote_task_status_updated_at": "2000", "routing_requires_live_data": "true"])
    return (pending, managed, observation)
  }

  private func terminal(_ original: AgentDesktopReplyRecoveryRecord) -> AgentDesktopReplyRecoveryRecord {
    var result = original
    result.status = "completed"
    result.terminalObservedAt = 2_000
    return result
  }

  func testOrdinaryStatusExpiryDoesNotDeclareFailureOrReplay() throws {
    let (pending, managed, observation) = try fixture()
    let projected = try XCTUnwrap(AgentNativeConnectorObservationExpiry.project(pending: pending, managed: managed,
      observation: observation, nowMillis: 302_000))
    XCTAssertFalse(projected.missingResult)
    XCTAssertEqual(projected.reason, "desktop_status_unavailable")
    XCTAssertEqual(projected.pending.metadata["awaiting_response"], "true")
    XCTAssertNil(projected.pending.metadata["effect_outcome_unknown"])
    XCTAssertEqual(projected.pending.success, pending.success)
    XCTAssertEqual(projected.pending.actionId, pending.actionId)
  }

  func testMissingTerminalResultRetainsPendingOwnerAndBlocksAutomaticReplay() throws {
    let (pending, managed, observation) = try fixture()
    let projected = try XCTUnwrap(AgentNativeConnectorObservationExpiry.project(pending: pending, managed: managed,
      observation: terminal(observation), nowMillis: 902_000))
    XCTAssertTrue(projected.missingResult)
    for key in ["effect_outcome_unknown", "non_retriable", "native_connector_dispatch_uncertain"] {
      XCTAssertEqual(projected.pending.metadata[key], "true")
    }
    for key in ["awaiting_response", "control_plane_run_id", "control_plane_agent_id", "source_message_id",
      "contact_id", "conversation_id", "turn_id", "task_id", "execution_generation", "completion_verified"] {
      XCTAssertEqual(projected.pending.metadata[key], pending.metadata[key])
    }
    XCTAssertEqual(try JSONDecoder().decode(AgentActionResult.self, from: JSONEncoder().encode(projected.pending)), projected.pending)
  }

  func testPriorStatusWarningCanEscalateAfterTerminalDeliveryExpiry() throws {
    let (pending, managed, observation) = try fixture()
    let warning = try XCTUnwrap(AgentNativeConnectorObservationExpiry.project(pending: pending, managed: managed,
      observation: observation, nowMillis: 302_000))
    let escalated = try XCTUnwrap(AgentNativeConnectorObservationExpiry.project(pending: warning.pending,
      managed: managed, observation: terminal(observation), nowMillis: 902_000))
    XCTAssertTrue(escalated.missingResult)
    XCTAssertNotEqual(escalated.pending.metadata["native_connector_observation_expiry_clock"],
      warning.pending.metadata["native_connector_observation_expiry_clock"])
    XCTAssertNil(AgentNativeConnectorObservationExpiry.project(pending: escalated.pending, managed: managed,
      observation: terminal(observation), nowMillis: 903_000))
  }

  func testPrematureOrUnprovedTerminalExpiryIsRejected() throws {
    let (pending, managed, observation) = try fixture()
    XCTAssertNil(AgentNativeConnectorObservationExpiry.project(pending: pending, managed: managed,
      observation: terminal(observation), nowMillis: 901_999))
    var variants = [AgentDesktopReplyRecoveryRecord]()
    var changed = terminal(observation); changed.generation = 3; variants.append(changed)
    changed = terminal(observation); changed.sequence = -1; variants.append(changed)
    changed = terminal(observation); changed.status = "running"; variants.append(changed)
    changed = terminal(observation); changed.lastResponseAt = 903_000; variants.append(changed)
    for variant in variants {
      XCTAssertNil(AgentNativeConnectorObservationExpiry.project(pending: pending, managed: managed,
        observation: variant, nowMillis: 902_000))
    }
  }

  func testEveryPendingManagedIdentityMustMatch() throws {
    let (pending, managed, observation) = try fixture()
    for key in ["control_plane_run_id", "control_plane_agent_id", "source_message_id", "contact_id",
      "conversation_id", "turn_id", "task_id", "execution_generation"] {
      var changed = pending
      changed.metadata[key] = "foreign"
      XCTAssertNil(AgentNativeConnectorObservationExpiry.project(pending: changed, managed: managed,
        observation: terminal(observation), nowMillis: 902_000), key)
    }
  }

  func testForeignRecoveryOwnerAndAlreadySettledRecordAreRejected() throws {
    let (pending, managed, observation) = try fixture()
    var foreign = terminal(observation)
    foreign.binding.managedSource?.ownerRunId = "foreign"
    XCTAssertNil(AgentNativeConnectorObservationExpiry.project(pending: pending, managed: managed,
      observation: foreign, nowMillis: 902_000))
    var settled = managed
    settled.state = .completed
    XCTAssertNil(AgentNativeConnectorObservationExpiry.project(pending: pending, managed: settled,
      observation: terminal(observation), nowMillis: 902_000))
  }

  func testLateCommittedSuccessUsesExistingUncertaintySettlement() throws {
    let (pending, managed, observation) = try fixture()
    let unknown = try XCTUnwrap(AgentNativeConnectorObservationExpiry.project(pending: pending, managed: managed,
      observation: terminal(observation), nowMillis: 902_000))
    let response = AgentConnectorResponse(sourceMessageId: 123, contactId: managed.contactId,
      content: "Recovered original result", conversationId: managed.conversationId, turnId: managed.turnId,
      taskId: managed.taskId, success: true, receivedAtMillis: 903_000, taskStatus: "completed", executionGeneration: 2)
    var completed = managed
    completed.state = .completed
    completed.response = response
    let result = try XCTUnwrap(AgentNativeConnectorContinuation.settle(unknown.pending, record: completed))
    XCTAssertTrue(result.success)
    XCTAssertEqual(result.metadata["awaiting_response"], "false")
    for key in ["effect_outcome_unknown", "non_retriable", "error_code", "evidence", "native_connector_dispatch_uncertain"] {
      XCTAssertNil(result.metadata[key])
    }
  }

  func testManualAndRoutingLocksRemainUnchanged() throws {
    let (original, managed, observation) = try fixture()
    var pending = original
    pending.metadata["manual_target_locked"] = "true"
    pending.metadata["auto_reroute_on_failure"] = "false"
    pending.metadata["remaining_fallback_ids"] = "cloud,phone"
    let projected = try XCTUnwrap(AgentNativeConnectorObservationExpiry.project(pending: pending, managed: managed,
      observation: terminal(observation), nowMillis: 902_000))
    for key in ["manual_target_locked", "auto_reroute_on_failure", "remaining_fallback_ids"] {
      XCTAssertEqual(projected.pending.metadata[key], pending.metadata[key])
    }
  }
}
