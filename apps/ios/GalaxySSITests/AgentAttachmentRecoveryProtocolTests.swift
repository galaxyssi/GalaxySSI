import XCTest
@testable import GalaxySSI

final class AgentAttachmentRecoveryProtocolTests: XCTestCase {
  func testRecoveryManifestAndReceiptCarryTheExactRequestNonce() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let scope = try AgentAttachmentTransferScope(contactId: "codex", desktopId: "desktop",
      clientRouteId: String(repeating: "a", count: 32), conversationId: "conversation", taskId: "task",
      turnId: "turn", clientMessageId: "source", attachmentRequestId: String(repeating: "b", count: 32))
    let store = AgentOutboundAttachmentTransferStore(rootURL: root,
      cipher: GalaxySSIAttachmentAtRestCipher(secrets: InMemorySecretStore()))
    let prepared = try XCTUnwrap(try store.prepare(scope: scope,
      attachments: [GalaxySSIDraftAttachment(id: "file", displayName: "report-v03.docx",
        mimeType: "application/octet-stream", data: Data("original".utf8))],
      mediaProfile: AgentMediaNetworkPolicy.profile(for: .normal), preserveOriginalBytes: true).first)
    XCTAssertEqual(prepared.manifestPayload(resume: false)["attachment_request_id"] as? String, scope.attachmentRequestId)
    XCTAssertEqual(try prepared.chunkPayload(index: 0)["attachment_request_id"] as? String, scope.attachmentRequestId)
    var receipt: [String: Any] = ["status": "stored", "transfer_id": prepared.transferId,
      "sha256": prepared.sha256, "client_route_id": scope.clientRouteId,
      "conversation_id": scope.conversationId, "task_id": scope.taskId, "turn_id": scope.turnId,
      "contact_id": scope.contactId, "source_message_id": "source", "attachment_request_id": scope.attachmentRequestId!]
    XCTAssertTrue(prepared.matchesStoredReceipt(receipt))
    receipt["attachment_request_id"] = String(repeating: "c", count: 32)
    XCTAssertFalse(prepared.matchesStoredReceipt(receipt))
    receipt.removeValue(forKey: "attachment_request_id")
    XCTAssertFalse(prepared.matchesStoredReceipt(receipt))
  }

  func testUUIDSourceIdentityIsPreservedForIOSRequests() throws {
    var payload = basePayload()
    let source = "1e7b9761-52de-46dc-93cf-431b0f083c65"
    payload["source_message_id"] = .string(source)
    payload["attachment_ids"] = .array([.string("artifact-one")])
    let request = try XCTUnwrap(AgentAttachmentRecoveryRequest.decode(payload))
    XCTAssertEqual(request.sourceIdentity, source)
    XCTAssertEqual(request.result(status: "missing")["source_message_id"], .string(source))
    for invalid in [Double.infinity, Double.nan, 1e30, -1, 1.5] {
      payload["source_message_id"] = .double(invalid)
      XCTAssertNil(AgentAttachmentRecoveryRequest.decode(payload))
    }
  }

  func testRecoveryNonceScopesTransferIdentityAndSurvivesEncoding() throws {
    let first = try AgentAttachmentTransferScope(contactId: "codex", desktopId: "desktop",
      clientRouteId: String(repeating: "a", count: 32), conversationId: "conversation", taskId: "task",
      turnId: "turn", clientMessageId: "source", attachmentRequestId: String(repeating: "b", count: 32))
    var second = first
    second.attachmentRequestId = String(repeating: "c", count: 32)
    let digest = String(repeating: "d", count: 64)
    XCTAssertNotEqual(try AgentAttachmentTransferProtocol.transferId(scope: first, attachmentId: "file", sha256: digest),
      try AgentAttachmentTransferProtocol.transferId(scope: second, attachmentId: "file", sha256: digest))
    XCTAssertEqual(try JSONDecoder().decode(AgentAttachmentTransferScope.self,
      from: JSONEncoder().encode(first)), first)
    XCTAssertThrowsError(try AgentAttachmentTransferScope(contactId: "codex", desktopId: "desktop",
      clientRouteId: String(repeating: "a", count: 32), conversationId: "conversation", taskId: "task",
      turnId: "turn", attachmentRequestId: "invalid"))
  }

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
