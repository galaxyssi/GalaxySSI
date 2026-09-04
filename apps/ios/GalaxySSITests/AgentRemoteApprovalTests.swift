import XCTest
@testable import GalaxySSI

final class AgentRemoteApprovalTests: XCTestCase {
  func testAgentRemoteApprovalValidTaskApprovalRoundTripsExactDecision() throws {
    let request = try XCTUnwrap(
      AgentRemoteApprovalRequest.fromTaskEvent(
        remoteApprovalTaskEvent(expiresAtMillis: 2_000_000),
        nowMillis: 1_700_000
      )
    )

    XCTAssertEqual(request.approvalId, "approval-12345678")
    XCTAssertEqual(request.detail, "python verify.py")
    XCTAssertEqual(request.parametersJson, #"{"command":"python verify.py","cwd":"C:/workspace"}"#)
    XCTAssertEqual(request.compactActionHash, "aaaaaaaa...aaaaaaaa")
    XCTAssertEqual(request.dedupeKey, "remote-approval:task-approval:approval-12345678")

    let approved = try XCTUnwrap(AgentRemoteApprovalDecision.decode(request.decision(approved: true).encode()))

    XCTAssertTrue(approved.approved)
    XCTAssertEqual(approved.taskId, request.taskId)
    XCTAssertEqual(approved.clientRouteId, request.clientRouteId)
    XCTAssertEqual(approved.conversationId, request.conversationId)
    XCTAssertEqual(approved.turnId, request.turnId)
    XCTAssertEqual(approved.actionHash, request.actionHash)
  }

  func testAgentRemoteApprovalRejectsExpiredOrMalformedApprovals() {
    XCTAssertNil(
      AgentRemoteApprovalRequest.fromTaskEvent(
        remoteApprovalTaskEvent(expiresAtMillis: 1_500),
        nowMillis: 2_000
      )
    )
    XCTAssertNil(
      AgentRemoteApprovalRequest.fromTaskEvent(
        remoteApprovalTaskEvent(actionHash: "changed"),
        nowMillis: 1_000
      )
    )
    XCTAssertNil(
      AgentRemoteApprovalRequest.fromTaskEvent(
        remoteApprovalTaskEvent(sourceMessageId: 0),
        nowMillis: 1_000
      )
    )
    XCTAssertNil(
      AgentRemoteApprovalRequest.fromTaskEvent(
        remoteApprovalTaskEvent(taskStatus: "running"),
        nowMillis: 1_000
      )
    )
  }

  func testAgentRemoteApprovalDecisionDecoderRejectsChangedIdentityFields() throws {
    let request = try XCTUnwrap(
      AgentRemoteApprovalRequest.fromTaskEvent(
        remoteApprovalTaskEvent(expiresAtMillis: 2_000_000),
        nowMillis: 1_700_000
      )
    )
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(request.decision(approved: false).encode().utf8)) as? [String: Any]
    )
    object["approval_id"] = "short"
    let mutated = String(
      decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      as: UTF8.self
    )

    XCTAssertNil(AgentRemoteApprovalDecision.decode(mutated))
    XCTAssertFalse(request.decision(approved: false).approved)
  }

  func testAgentRemoteApprovalModelsUseAndroidWireNames() throws {
    let request = try XCTUnwrap(
      AgentRemoteApprovalRequest.fromTaskEvent(
        remoteApprovalTaskEvent(sourceMessageId: 42, expiresAtMillis: 2_000_000),
        nowMillis: 1_700_000
      )
    )
    let decision = request.decision(approved: true)
    let decisionObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(decision.encode().utf8)) as? [String: Any]
    )
    let requestObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
    )

    XCTAssertEqual(decisionObject["task_id"] as? String, "task-approval")
    XCTAssertEqual(decisionObject["client_route_id"] as? String, "client-route")
    XCTAssertEqual(decisionObject["conversation_id"] as? String, "conversation-approval")
    XCTAssertEqual(decisionObject["turn_id"] as? String, "turn-approval")
    XCTAssertEqual(decisionObject["contact_id"] as? String, "codex-contact")
    XCTAssertEqual(decisionObject["source_message_id"] as? Int, 42)
    XCTAssertEqual(decisionObject["approval_id"] as? String, "approval-12345678")
    XCTAssertEqual(decisionObject["action_hash"] as? String, String(repeating: "a", count: 64))
    XCTAssertEqual(decisionObject["approved"] as? Bool, true)
    XCTAssertNil(decisionObject["sourceMessageId"])
    XCTAssertEqual(requestObject["requested_at_millis"] as? Int, 1_700_000)
    XCTAssertEqual(requestObject["expires_at_millis"] as? Int, 2_000_000)
    XCTAssertEqual(requestObject["parameters_json"] as? String, #"{"command":"python verify.py","cwd":"C:/workspace"}"#)
  }

  private func remoteApprovalTaskEvent(
    sourceMessageId: Int64 = 42,
    actionHash: String = String(repeating: "a", count: 64),
    taskStatus: String = "waiting_approval",
    expiresAtMillis: Int64 = 2_000_000
  ) -> String {
    let payload: [String: Any] = [
      "type": "agent_task_event",
      "task_status": taskStatus,
      "task_id": "task-approval",
      "client_route_id": "client-route",
      "conversation_id": "conversation-approval",
      "turn_id": "turn-approval",
      "contact_id": "codex-contact",
      "source_message_id": sourceMessageId,
      "approval_request": [
        "approval_id": "approval-12345678",
        "action_hash": actionHash,
        "kind": "command",
        "title": "Run a command",
        "detail": "python verify.py",
        "target": "python verify.py",
        "reason": "Verify the result",
        "requested_at_ms": expiresAtMillis - 300_000,
        "expires_at_ms": expiresAtMillis,
        "parameters": [
          "command": "python verify.py",
          "cwd": "C:/workspace"
        ]
      ]
    ]
    let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
  }
}
