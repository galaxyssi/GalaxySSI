import XCTest
@testable import GalaxySSI

final class AgentNativeConnectorRecoveryWakeTests: XCTestCase {
  private func fixture(status: String = "completed") throws -> (AgentActionResult, AgentManagedResponseRecord, AgentDesktopReplyRecoveryRecord) {
    let managed = AgentManagedResponseRecord(ownerRunId: "owner", supervisorRunId: "parent", agentId: "registered-agent",
      deliveryMode: .respond, sourceMessageId: 123, contactId: "desktop:codex", conversationId: "conversation",
      turnId: "turn", taskId: "remote-task", executionGeneration: 2, createdAtMillis: 1_000)
    let binding = try XCTUnwrap(AgentDesktopReplyBinding.managed(record: managed, desktopId: "desktop", agentId: "codex",
      identity: .init(clientRouteId: "route", conversationId: managed.conversationId, taskId: managed.taskId, turnId: managed.turnId)))
    var observation = AgentDesktopReplyRecoveryRecord(binding: binding, createdAt: 1_000)
    observation.generation = 2; observation.sequence = 3; observation.status = status
    observation.terminalObservedAt = 4_000; observation.lastResponseAt = 4_000
    let pending = AgentActionResult(actionId: "action", success: true, message: "Waiting for original result",
      metadata: ["awaiting_response": "true", "completion_verified": "false", "source_message_id": "123",
        "control_plane_run_id": managed.ownerRunId, "control_plane_agent_id": managed.agentId,
        "contact_id": managed.contactId, "conversation_id": managed.conversationId, "turn_id": managed.turnId,
        "task_id": managed.taskId, "execution_generation": "2", "remote_task_status": status,
        "remote_task_status_seq": "3", "remote_task_status_updated_at": "4000", "manual_target_locked": "true"])
    return (pending, managed, observation)
  }
  private func next(_ f: (AgentActionResult, AgentManagedResponseRecord, AgentDesktopReplyRecoveryRecord),
      now: Int64 = 4_000, last: Int64? = nil) -> AgentNativeConnectorRecoveryWake? {
    AgentNativeConnectorRecoveryWake.terminalResult(pending: f.0, managed: f.1, observation: f.2,
      nowMillis: now, lastWakeMillis: last)
  }

  func testOrdinaryStageRetainsTheExistingClockAndThrottle() throws {
    let metadata = ["awaiting_response": "true", "resource_started_at": "1000"]
    let original = try XCTUnwrap(AgentNativeConnectorObservationWakePolicy.next(metadata: metadata,
      nowMillis: 16_000, lastWakeMillis: 15_000))
    let wrapped = try XCTUnwrap(AgentNativeConnectorRecoveryWake.stage(metadata: metadata, nowMillis: 16_000, lastWakeMillis: 15_000))
    XCTAssertEqual(wrapped.clock, original.clock)
    XCTAssertEqual(wrapped.delayMillis, original.delayMillis)
  }
  func testEveryAuthenticatedTerminalStatusCanPollItsOriginalResult() throws {
    for status in ["completed", "failed", "timed_out", "cancelled"] {
      let f = try fixture(status: status)
      XCTAssertEqual(next(f)?.delayMillis, 0)
      XCTAssertEqual(next(f, now: 4_500, last: 4_000)?.delayMillis, 29_500)
      XCTAssertEqual(next(f, now: 34_000, last: 4_000)?.delayMillis, 0)
      XCTAssertEqual(f.0.metadata["awaiting_response"], "true")
      XCTAssertEqual(f.0.metadata["manual_target_locked"], "true")
      XCTAssertEqual(f.0.metadata["completion_verified"], "false")
    }
  }
  func testDuplicateStatusDoesNotRenewTheTerminalDeliveryAnchor() throws {
    var f = try fixture()
    let original = try XCTUnwrap(next(f))
    f.2.lastResponseAt = 100_000
    XCTAssertEqual(next(f, now: 100_000)?.clock, original.clock)
    XCTAssertEqual(f.2.terminalObservedAt, 4_000)
    XCTAssertEqual(f.2.expiryReason(now: 904_000), "desktop_result_unavailable")
    XCTAssertEqual(next(f, now: 904_000)?.delayMillis, 0)
  }
  func testApproachingExpiryAndExpiredRetryBothRemainBounded() throws {
    let f = try fixture()
    XCTAssertEqual(AgentNativeConnectorRecoveryWake.terminalDeliveryMillis, 900_000)
    XCTAssertEqual(next(f, now: 903_999, last: 903_999)?.delayMillis, 1)
    XCTAssertEqual(next(f, now: 904_000, last: 904_000)?.delayMillis, 30_000)
    XCTAssertEqual(next(f, now: 934_000, last: 904_000)?.delayMillis, 0)
    XCTAssertEqual(next(f, now: 904_000, last: 950_000)?.delayMillis, 30_000)
  }
  func testMissingFutureAndInconsistentTerminalClocksDeny() throws {
    let f = try fixture()
    for terminal in [Int64(0), -1, 5_000, Int64.max] {
      var changed = f; changed.2.terminalObservedAt = terminal
      XCTAssertNil(next(changed))
    }
    var changed = f; changed.2.lastResponseAt = 5_000
    XCTAssertNil(next(changed))
    changed = f; changed.0.metadata["remote_task_status_updated_at"] = "3999"
    XCTAssertNil(next(changed))
    changed.0.metadata["remote_task_status_updated_at"] = "invalid"
    XCTAssertNil(next(changed))
  }
  func testNonterminalAndUserWaitingStatesDoNotAcquireTerminalWake() throws {
    for status in ["", "accepted", "queued", "starting", "running", "recovering", "waiting_input", "waiting_approval", "paused"] {
      XCTAssertNil(next(try fixture(status: status)), status)
    }
  }
  func testEveryPendingIdentityFieldMustRetainTheManagedOwner() throws {
    let f = try fixture()
    for key in ["source_message_id", "control_plane_run_id", "control_plane_agent_id", "contact_id",
      "conversation_id", "turn_id", "task_id", "execution_generation", "remote_task_status_seq"] {
      var changed = f; changed.0.metadata[key] = "foreign"
      XCTAssertNil(next(changed), key)
    }
    var changed = f; changed.0.metadata["awaiting_response"] = "false"
    XCTAssertNil(next(changed))
  }
  func testForeignManagedSourceAndBindingCannotReuseWake() throws {
    let f = try fixture()
    var changed = f; changed.1.ownerRunId = "other-owner"
    XCTAssertNil(next(changed))
    changed = f; changed.2.binding.managedSource?.sourceMessageId = 124
    XCTAssertNil(next(changed))
    changed = f; changed.2.binding.identity.taskId = "other-task"
    XCTAssertNil(next(changed))
    changed = f; changed.2.generation = 3
    XCTAssertNil(next(changed))
    changed = f; changed.2.sequence = -1
    XCTAssertNil(next(changed))
    changed = f; changed.1.agentId = ""; changed.0.metadata["control_plane_agent_id"] = ""
    XCTAssertNil(next(changed))
  }
  func testCommittedManagedResultsStopTerminalPolling() throws {
    for state in [AgentManagedResponseState.completed, .applied] {
      var f = try fixture(); f.1.state = state
      XCTAssertNil(next(f))
    }
  }
  func testArchivedObservationRetainsItsOriginalClockAfterReopen() throws {
    var f = try fixture()
    let before = try XCTUnwrap(next(f))
    f.2 = try JSONDecoder().decode(AgentDesktopReplyRecoveryRecord.self, from: JSONEncoder().encode(f.2))
    XCTAssertEqual(next(f), before)
    XCTAssertEqual(f.2.terminalObservedAt, 4_000)
    XCTAssertNil(f.2.acceptedReply)
  }
}
