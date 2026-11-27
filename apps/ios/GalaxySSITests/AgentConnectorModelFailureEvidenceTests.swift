import Foundation
import XCTest
@testable import GalaxySSI

final class AgentConnectorModelFailureEvidenceTests: XCTestCase {
  private let failure = NSError(domain: "synthetic-model", code: 1)

  func testPurePhoneInferenceFailureRequiresTheExactStartedOwner() {
    let evidence = AgentConnectorModelFailureEvidence(owner: "owner")
    XCTAssertFalse(evidence.permitsKnownFailure(requestId: "owner", error: failure, taskCancelled: false))
    evidence.beginPhoneInference()
    XCTAssertTrue(evidence.permitsKnownFailure(requestId: "owner", error: failure, taskCancelled: false))
    XCTAssertFalse(evidence.permitsKnownFailure(requestId: "other", error: failure, taskCancelled: false))
  }

  func testCloudFailureNeedsAnInstalledExactRequestObserver() {
    let evidence = AgentConnectorModelFailureEvidence(owner: "owner")
    evidence.beginCloudInference()
    XCTAssertFalse(evidence.permitsKnownFailure(requestId: "owner", error: failure, taskCancelled: false))
    evidence.installCloudObserver(requestId: "owner")
    XCTAssertTrue(evidence.permitsKnownFailure(requestId: "owner", error: failure, taskCancelled: false))
    evidence.recordStreamFailure(code: "RATE_LIMIT", requestId: "owner")
    XCTAssertTrue(evidence.permitsKnownFailure(requestId: "owner", error: failure, taskCancelled: false))
  }

  func testToolOrOpaqueBackendBoundaryIsMonotonic() {
    let evidence = AgentConnectorModelFailureEvidence(owner: "owner")
    evidence.beginCloudInference()
    evidence.installCloudObserver(requestId: "owner")
    evidence.markPossibleEffects()
    evidence.installCloudObserver(requestId: "owner")
    XCTAssertFalse(evidence.permitsKnownFailure(requestId: "owner", error: failure, taskCancelled: false))
    evidence.beginPhoneInference()
    XCTAssertFalse(evidence.permitsKnownFailure(requestId: "owner", error: failure, taskCancelled: false))
  }

  func testMismatchedObserverFailureOrRepeatedStartCannotGrantKnownFailure() {
    for malformed in ["", " owner", String(repeating: "x", count: 201)] {
      let evidence = AgentConnectorModelFailureEvidence(owner: malformed)
      evidence.beginPhoneInference()
      XCTAssertFalse(evidence.permitsKnownFailure(requestId: malformed, error: failure, taskCancelled: false))
    }
    let wrongObserver = AgentConnectorModelFailureEvidence(owner: "owner")
    wrongObserver.beginCloudInference()
    wrongObserver.installCloudObserver(requestId: "other")
    wrongObserver.installCloudObserver(requestId: "owner")
    XCTAssertFalse(wrongObserver.permitsKnownFailure(requestId: "owner", error: failure, taskCancelled: false))
    let wrongFailure = AgentConnectorModelFailureEvidence(owner: "owner")
    wrongFailure.beginCloudInference()
    wrongFailure.installCloudObserver(requestId: "owner")
    wrongFailure.recordStreamFailure(code: "FAILED", requestId: "other")
    XCTAssertFalse(wrongFailure.permitsKnownFailure(requestId: "owner", error: failure, taskCancelled: false))
  }

  func testTaskAndURLCancellationAreNotProviderFailures() {
    let evidence = AgentConnectorModelFailureEvidence(owner: "owner")
    evidence.beginPhoneInference()
    XCTAssertFalse(evidence.permitsKnownFailure(requestId: "owner", error: CancellationError(), taskCancelled: false))
    XCTAssertFalse(evidence.permitsKnownFailure(requestId: "owner", error: URLError(.cancelled), taskCancelled: false))
    XCTAssertFalse(evidence.permitsKnownFailure(requestId: "owner", error: failure, taskCancelled: true))
  }

  func testCancelledStreamCodeSurvivesErrorMessageWrapping() {
    let evidence = AgentConnectorModelFailureEvidence(owner: "owner")
    evidence.beginCloudInference()
    evidence.installCloudObserver(requestId: "owner")
    evidence.recordStreamFailure(code: "cancelled", requestId: "owner")
    XCTAssertFalse(evidence.permitsKnownFailure(requestId: "owner", error: failure, taskCancelled: false))
  }

  private func committedFailure() -> (AgentActionResult, AgentManagedResponseRecord) {
    let pending = AgentActionResult(actionId: "action", success: true, message: "Queued",
      metadata: ["awaiting_response": "true", "source_message_id": "42", "contact_id": "local-llm",
        "conversation_id": "conversation", "turn_id": "turn", "task_id": "task", "execution_generation": "2",
        "control_plane_run_id": "owner", "control_plane_agent_id": "registered-model"])
    let response = AgentConnectorResponse(sourceMessageId: 42, contactId: "local-llm", content: "Synthetic failure",
      conversationId: "conversation", turnId: "turn", taskId: "task", success: false, receivedAtMillis: 2_000,
      taskStatus: "failed", executionGeneration: 2)
    let record = AgentManagedResponseRecord(ownerRunId: "owner", supervisorRunId: "", agentId: "registered-model",
      deliveryMode: .respond, sourceMessageId: 42, contactId: "local-llm", conversationId: "conversation",
      turnId: "turn", taskId: "task", executionGeneration: 2, state: .completed, response: response,
      createdAtMillis: 1_000, completedAtMillis: 2_000)
    return (pending, record)
  }

  func testExistingSettlementRetainsExactOwnerActionAndGeneration() throws {
    let (pending, record) = committedFailure()
    let settled = try XCTUnwrap(AgentNativeConnectorContinuation.settle(pending, record: record))
    XCTAssertFalse(settled.success)
    XCTAssertEqual(settled.actionId, "action")
    XCTAssertEqual(settled.metadata["connector_disposition"], "response")
    XCTAssertEqual(settled.metadata["remote_task_status"], "failed")
    XCTAssertEqual(settled.metadata["awaiting_response"], "false")
    var stale = record
    stale.executionGeneration = 3
    XCTAssertNil(AgentNativeConnectorContinuation.settle(pending, record: stale))
  }

  func testKnownFailureSettlementDoesNotGrantFallbackOrEraseUncertainty() throws {
    let fixture = committedFailure()
    var pending = fixture.0
    let record = fixture.1
    pending.metadata["manual_target_locked"] = "true"
    pending.metadata["auto_reroute_on_failure"] = "false"
    pending.metadata["effect_outcome_unknown"] = "true"
    pending.metadata["non_retriable"] = "true"
    let settled = try XCTUnwrap(AgentNativeConnectorContinuation.settle(pending, record: record))
    for key in ["manual_target_locked", "auto_reroute_on_failure", "effect_outcome_unknown", "non_retriable"] {
      XCTAssertEqual(settled.metadata[key], pending.metadata[key])
    }
  }
}
