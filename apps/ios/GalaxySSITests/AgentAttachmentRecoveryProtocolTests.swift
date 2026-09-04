import XCTest
@testable import GalaxySSI

final class AgentAttachmentRecoveryProtocolTests: XCTestCase {
  func testDecodesBoundedTaskScopedRequest() throws {
    var payload = basePayload()
    payload["attachment_ids"] = .array([
      .string("image-one"),
      .string("image-one"),
      .string("file-two")
    ])

    let request = try XCTUnwrap(AgentAttachmentRecoveryRequest.decode(payload))

    XCTAssertEqual(request.requestId, "0123456789abcdef0123456789abcdef")
    XCTAssertEqual(request.attachmentIds, ["image-one", "file-two"])
    XCTAssertEqual(request.conversationId, "conversation-one")
    XCTAssertEqual(request.sourceMessageId, 42)
    let result = request.result(
      status: "transferring",
      availableAttachmentIds: ["image-one"],
      timeMillis: 123_456
    )
    XCTAssertEqual(result["type"], .string(AgentAttachmentRecoveryRequest.resultType))
    XCTAssertEqual(result["request_id"], .string("0123456789abcdef0123456789abcdef"))
    XCTAssertEqual(result["source_message_id"], .string("42"))
    XCTAssertEqual(result["available_attachment_ids"], .array([.string("image-one")]))
    XCTAssertEqual(result["time"], .int(123_456))
  }

  func testDecodeAcceptsNumericSourceMessageIdAndLimitsAttachmentSet() throws {
    var payload = basePayload()
    payload["source_message_id"] = .int(73)
    payload["attachment_ids"] = .array((0..<12).map { .string("attachment-\($0)") })

    let request = try XCTUnwrap(AgentAttachmentRecoveryRequest.decode(payload))

    XCTAssertEqual(request.sourceMessageId, 73)
    XCTAssertEqual(request.attachmentIds.count, 10)
    XCTAssertEqual(request.attachmentIds.last, "attachment-9")
  }

  func testRejectsInvalidRequestIdentityAndEmptyAttachmentSet() {
    var badRequestId = basePayload()
    badRequestId["request_id"] = .string("not-valid")
    badRequestId["attachment_ids"] = .array([.string("image-one")])
    XCTAssertNil(AgentAttachmentRecoveryRequest.decode(badRequestId))

    var emptyAttachments = basePayload()
    emptyAttachments["attachment_ids"] = .array([])
    XCTAssertNil(AgentAttachmentRecoveryRequest.decode(emptyAttachments))

    var unsafeIdentity = basePayload()
    unsafeIdentity["client_route_id"] = .string("route\none")
    unsafeIdentity["attachment_ids"] = .array([.string("image-one")])
    XCTAssertNil(AgentAttachmentRecoveryRequest.decode(unsafeIdentity))
  }

  func testResultTrimsAndClipsError() throws {
    var payload = basePayload()
    payload["attachment_ids"] = .array([.string("file-one")])
    let request = try XCTUnwrap(AgentAttachmentRecoveryRequest.decode(payload))

    let result = request.result(
      status: "failed",
      missingAttachmentIds: ["file-one"],
      error: "  \(String(repeating: "x", count: 320))  ",
      timeMillis: 7
    )

    XCTAssertEqual(result["missing_attachment_ids"], .array([.string("file-one")]))
    XCTAssertEqual(result["error"]?.stringValue?.count, 300)
    XCTAssertEqual(result["time"], .int(7))
  }

  private func basePayload() -> AgentMcpJSONObject {
    [
      "type": .string(AgentAttachmentRecoveryRequest.requestType),
      "request_id": .string("0123456789abcdef0123456789abcdef"),
      "client_route_id": .string("route-one"),
      "conversation_id": .string("conversation-one"),
      "task_id": .string("task-one"),
      "turn_id": .string("turn-one"),
      "contact_id": .string("codex"),
      "source_message_id": .string("42")
    ]
  }
}
