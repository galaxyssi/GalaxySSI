import XCTest
@testable import GalaxySSI

final class AgentSingleFileDesktopIntentTests: XCTestCase {
  private func fixture() throws -> (AgentSingleFileDesktopIntent, [String: Any]) {
    let identity = AgentTaskIdentity(clientRouteId: "fixture-route", conversationId: "fixture-chat",
      taskId: "00000000-0000-4000-8000-000000000001", turnId: "00000000-0000-4000-8000-000000000002")
    let invocation = try XCTUnwrap(AgentInvocationRequestJsonCodec.encode(modelId: "fixture-model", reasoningEffort: .automatic))
    let transfer = String(repeating: "a", count: 64)
    let descriptor: [String: Any] = ["id": "first-file", "transfer_id": transfer, "name": "same-name.txt", "sha256": String(repeating: "b", count: 64)]
    let prompt = "Inspect one synthetic file without tools."
    let intent = AgentSingleFileDesktopIntent(source: 12_345,
      owner: AgentSingleFileDesktopIntent.ownerPrefix + String(repeating: "c", count: 64),
      contact: "fixture-contact", agent: "codex", model: "fixture-model", effort: .automatic,
      desktop: "fixture-desktop", identity: identity, binding: String(repeating: "d", count: 64),
      attachment: "first-file", transfer: transfer, originalRichSHA: String(repeating: "e", count: 64),
      promptSHA: AgentTurnReceiptEvidence.hash(prompt), descriptorsSHA: try XCTUnwrap(AgentSingleFileDesktopIntent.digest([descriptor])),
      invocationSHA: try XCTUnwrap(AgentSingleFileDesktopIntent.digest(invocation)))
    let payload: [String: Any] = ["type": "text", "message_id": identity.taskId, "content": prompt,
      "contact_id": intent.contact, "desktop_id": intent.desktop, "agent_id": intent.agent, "sender": "fixture-phone",
      "client_route_id": identity.clientRouteId, "conversation_id": identity.conversationId, "turn_id": identity.turnId,
      "task_id": identity.taskId, "source_message_id": String(intent.source), "client_message_id": String(intent.source), "time": 100,
      "connector_task_mode": AgentPairedPhonePlannerRoute.connectorMode,
      "execution_mode": AgentTaskExecutionMode.planOnly.rawValue,
      "_galaxyssi_task_execution_mode": AgentTaskExecutionMode.planOnly.rawValue, "_galaxyssi_long_term_write_allowed": "false",
      "agent_invocation": invocation, "response_language": "en", "request_kind": AgentRequestKind.screenAnalysis.rawValue,
      "execution_generation": 1, "attachments": [descriptor]]
    return (intent, payload)
  }
  func testOnlyExactIndependentInferenceRequestMatches() throws {
    let (intent, payload) = try fixture()
    XCTAssertTrue(intent.valid)
    XCTAssertTrue(intent.matches(payload))
    let reopened = try JSONDecoder().decode(AgentSingleFileDesktopIntent.self, from: JSONEncoder().encode(intent))
    XCTAssertEqual(reopened, intent)
    XCTAssertTrue(reopened.matches(payload))
  }
  func testSourceDestinationRouteTurnAndTaskCannotBeSubstituted() throws {
    let (intent, payload) = try fixture()
    for field in ["contact_id", "desktop_id", "agent_id", "client_route_id", "conversation_id", "turn_id", "task_id",
      "message_id", "source_message_id", "client_message_id"] {
      var changed = payload; changed[field] = "other"
      XCTAssertFalse(intent.matches(changed), field)
    }
  }
  func testHistoryOriginalQuestionAndExecutionPermissionCannotBeAdded() throws {
    let (intent, payload) = try fixture()
    for field in ["conversation_context", "_galaxyssi_conversation_context", "session_requirement", "agent_team_message"] {
      var changed = payload; changed[field] = "prior instructions"
      XCTAssertFalse(intent.matches(changed), field)
    }
    for field in ["execution_mode", "_galaxyssi_task_execution_mode", "request_kind", "connector_task_mode", "_galaxyssi_long_term_write_allowed", "content"] {
      var changed = payload; changed[field] = "execute the old batch"
      XCTAssertFalse(intent.matches(changed), field)
    }
  }
  func testSameNameSiblingOrDifferentSourceBytesNeverMatch() throws {
    let (intent, payload) = try fixture()
    let original = try XCTUnwrap((payload["attachments"] as? [[String: Any]])?.first)
    var sibling = original; sibling["id"] = "second-file"
    var changed = payload; changed["attachments"] = [sibling]
    XCTAssertFalse(intent.matches(changed))
    changed["attachments"] = [original, sibling]
    XCTAssertFalse(intent.matches(changed))
    var alteredBytes = original; alteredBytes["sha256"] = String(repeating: "f", count: 64)
    changed["attachments"] = [alteredBytes]
    XCTAssertFalse(intent.matches(changed))
  }
  func testModelInvocationAndReceiptGenerationRemainPinned() throws {
    let (intent, payload) = try fixture()
    var changed = payload; changed["agent_invocation"] = ["model_id": "other-model"]
    XCTAssertFalse(intent.matches(changed))
    let invalid: [Any] = [true, "1", 0, 2, 1.5]
    for generation in invalid {
      changed = payload; changed["execution_generation"] = generation
      XCTAssertFalse(intent.matches(changed))
    }
    changed = payload; changed["time"] = 0
    XCTAssertFalse(intent.matches(changed))
  }
  func testLegacyQueueRetainsRestrictiveReadScopeAcrossSerialization() throws {
    let scope = "00000000-0000-4000-8000-000000000002"
    let now = Date(timeIntervalSince1970: 1)
    let item = PendingLinkMessage(messageId: "fixture", topic: "fixture-topic", wirePayload: "synthetic-ciphertext",
      status: "queued", attempts: 0, nextAttemptAt: now, createdAt: now, updatedAt: now,
      clientSourceMessageId: "12345", contactId: "fixture-contact", fileReadScope: scope)
    let reopened = try JSONDecoder().decode(PendingLinkMessage.self, from: JSONEncoder().encode(item))
    XCTAssertEqual(reopened.fileReadScope, scope)
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
    legacy.removeValue(forKey: "file_read_scope")
    XCTAssertNil(try JSONDecoder().decode(PendingLinkMessage.self, from: JSONSerialization.data(withJSONObject: legacy)).fileReadScope)
  }
  func testHistoricalTurnReceiptDoesNotInventDesktopIntent() throws {
    let legacy = try JSONDecoder().decode(AgentTurnReceipt.self, from: Data("{}".utf8))
    XCTAssertNil(legacy.fileReadDesktop)
  }
}
