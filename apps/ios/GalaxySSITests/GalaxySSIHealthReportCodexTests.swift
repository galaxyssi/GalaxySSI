import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthReportCodexTests: XCTestCase {
  typealias Codex = GalaxySSIHealthReportCodex
  let jpeg = Data([0xff, 0xd8, 0xff, 0xd9])

  func testReadyVerifiedCodexMustExplicitlyAdvertisePrivateReportFeature() {
    let now = Date()
    var contact = GalaxySSIContact.hermes()
    contact.agentId = "codex"; contact.desktopId = "desktop"; contact.deliveryMode = .pcConnector
    contact.trustState = .verified; contact.setupStatus = "ready"; contact.updatedAt = now
    XCTAssertFalse(Codex.supports(contact, now: now))
    contact.private_health_report_vision_v1 = true
    XCTAssertTrue(Codex.supports(contact, now: now))
    contact.trustState = .unverified
    XCTAssertFalse(Codex.supports(contact, now: now))
    contact.trustState = .verified; contact.setupStatus = "offline"
    XCTAssertFalse(Codex.supports(contact, now: now))
    contact.setupStatus = "ready"; contact.updatedAt = now.addingTimeInterval(-86400)
    XCTAssertFalse(Codex.supports(contact, now: now))
    contact.updatedAt = now; contact.agentId = "other"
    XCTAssertFalse(Codex.supports(contact, now: now))
  }

  func testOneShotPayloadPreservesConfiguredModelAndEffort() throws {
    let request = request()
    let payload = try request.payload(jpeg: jpeg, instructions: "Transcribe only this image")
    XCTAssertEqual(payload["request_kind"] as? String, "screen_analysis")
    XCTAssertEqual(payload["execution_mode"] as? String, "auto_complete")
    XCTAssertEqual(payload["agent_invocation"] as? [String: String], ["model_id": "saved-model", "reasoning_effort": "high"])
    let images = try XCTUnwrap(payload["attachments"] as? [[String: Any]])
    XCTAssertEqual(images.count, 1)
    XCTAssertEqual(images.first?["data_b64"] as? String, jpeg.base64EncodedString())
    XCTAssertTrue(Codex.acceptsOutgoing(payload, desktop: "desktop", route: "route"))
    XCTAssertNil(payload["history"])
    XCTAssertNil(payload["connector_task_mode"])
    XCTAssertNil(payload["agent_instance_id"])
    XCTAssertNil(payload["tools"])
  }

  func testEveryReportHasAnIndependentTemporaryIdentity() {
    let first = request(); let next = request()
    XCTAssertNotEqual(first.identity, next.identity)
    XCTAssertNotEqual(first.source, next.source)
    XCTAssertTrue(first.identity.conversationId.hasPrefix(Codex.prefix))
    XCTAssertEqual(first.identity.taskId, first.identity.turnId)
    XCTAssertTrue((1...9_007_199_254_740_991).contains(first.source))
  }

  func testOutgoingRejectsRecoveredThreadToolsHistoryAndProviderFallback() throws {
    let request = request()
    let original = try request.payload(jpeg: jpeg, instructions: "Only this image")
    for key in ["_recovered_task", "history", "agent_instance_id", "tools", "provider", "connector_task_mode"] {
      var changed = original; changed[key] = "not-authorized"
      XCTAssertFalse(Codex.acceptsOutgoing(changed, desktop: "desktop", route: "route"))
    }
    for (field, value) in [("request_kind", "conversation"), ("agent_id", "other"), ("execution_mode", "plan_only"),
                           ("conversation_id", "ordinary-chat"), ("task_id", UUID().uuidString), ("turn_id", UUID().uuidString)] {
      var changed = original; changed[field] = value
      XCTAssertFalse(Codex.acceptsOutgoing(changed, desktop: "desktop", route: "route"))
    }
    XCTAssertFalse(Codex.acceptsOutgoing(original, desktop: "another", route: "route"))
    XCTAssertFalse(Codex.acceptsOutgoing(original, desktop: "desktop", route: "stale"))
  }

  func testOutgoingRejectsExtraImagesAndAttachmentTransferDescriptors() throws {
    let original = try request().payload(jpeg: jpeg, instructions: "Only this image")
    var payload = original
    var image = try XCTUnwrap((payload["attachments"] as? [[String: Any]])?.first)
    payload["attachments"] = [image, image]
    XCTAssertFalse(Codex.acceptsOutgoing(payload, desktop: "desktop", route: "route"))
    image["transfer_id"] = "offline-transfer"
    payload["attachments"] = [image]
    XCTAssertFalse(Codex.acceptsOutgoing(payload, desktop: "desktop", route: "route"))
    image.removeValue(forKey: "transfer_id"); image["size"] = 12345
    payload["attachments"] = [image]
    XCTAssertFalse(Codex.acceptsOutgoing(payload, desktop: "desktop", route: "route"))
  }

  func testOversizedOrNonJpegInputFailsRatherThanQueuingChunks() {
    XCTAssertThrowsError(try request().payload(jpeg: Data(repeating: 0, count: Codex.maximumImageBytes + 1), instructions: "Only image"))
    XCTAssertThrowsError(try request().payload(jpeg: Data("not jpeg".utf8), instructions: "Only image"))
  }

  func testRetiredModelCannotSilentlyBecomeDefault() {
    let route = GalaxySSIHealthDesktopResearch.Route(connector: .init(contactId: "desktop:codex", desktopId: "desktop",
      clientRouteId: "route", modelId: "gpt-5.3-codex-spark", reasoningEffort: .high), desktopFingerprint: "pinned")
    XCTAssertThrowsError(try Codex.Request(target: .init(route: route, authority: "Desktop")).payload(jpeg: jpeg, instructions: "Only image"))
  }

  func testAuthenticatedExactReplyIsRetainedOnlyForActiveRequest() throws {
    let request = request(); let exchange = GalaxySSIHealthReportCodexExchange()
    try exchange.begin(request)
    let payload = reply(request)
    let receipt = exchange.receive(payload, desktop: "desktop", route: "route")
    XCTAssertNotNil(receipt)
    XCTAssertEqual(exchange.outcome(request), .result("{\"rows\":[]}"))
    exchange.finish(request)
    XCTAssertNil(exchange.outcome(request))
    XCTAssertNil(exchange.receive(payload, desktop: "desktop", route: "route"))
  }

  func testForgedPeerDesktopRouteSourceAndGenerationCannotCompleteRequest() throws {
    let request = request(); let exchange = GalaxySSIHealthReportCodexExchange()
    try exchange.begin(request)
    let original = reply(request)
    XCTAssertNil(exchange.receive(original, desktop: "wrong-desktop", route: "route"))
    XCTAssertNil(exchange.receive(original, desktop: "desktop", route: "old-route"))
    for (key, value) in [("contact_id", "other"), ("source_message_id", "1"), ("task_id", "other"),
                         ("turn_id", "other"), ("agent_id", "other"), ("execution_generation", "2")] {
      var changed = original; changed[key] = value
      XCTAssertNil(exchange.receive(changed, desktop: "desktop", route: "route"))
      XCTAssertNil(exchange.outcome(request))
    }
    var peer = original; peer["peer_chat"] = true
    XCTAssertNil(exchange.receive(peer, desktop: "desktop", route: "route"))
    XCTAssertNil(exchange.outcome(request))
  }

  func testOneReportCannotConsumeAnotherReportsReply() throws {
    let first = request(); let second = request(); let exchange = GalaxySSIHealthReportCodexExchange()
    try exchange.begin(first); try exchange.begin(second)
    _ = exchange.receive(reply(first), desktop: "desktop", route: "route")
    XCTAssertNotNil(exchange.outcome(first)); XCTAssertNil(exchange.outcome(second))
  }

  func testFailureIsTerminalAndProgressCannotPretendToBeResult() throws {
    let request = request(); let exchange = GalaxySSIHealthReportCodexExchange()
    try exchange.begin(request)
    var progress = reply(request); progress["type"] = "agent_task_event"; progress["task_status"] = "running"
    XCTAssertNil(exchange.receive(progress, desktop: "desktop", route: "route"))
    XCTAssertNil(exchange.outcome(request))
    progress["task_status"] = "failed"
    _ = exchange.receive(progress, desktop: "desktop", route: "route")
    XCTAssertEqual(exchange.outcome(request), .failed)
    _ = exchange.receive(reply(request), desktop: "desktop", route: "route")
    XCTAssertEqual(exchange.outcome(request), .failed)
  }

  func testOversizedOrFileBearingReplyFailsWithoutChatProjection() throws {
    for (key, value) in [("content", String(repeating: "x", count: Codex.maximumReplyBytes + 1)),
                         ("rich_output", "{\"files\":[\"private\"]}")] {
      let request = request(); let exchange = GalaxySSIHealthReportCodexExchange()
      try exchange.begin(request)
      var payload = reply(request); payload[key] = value
      _ = exchange.receive(payload, desktop: "desktop", route: "route")
      XCTAssertEqual(exchange.outcome(request), .failed)
    }
  }

  func testCancellationAndAcknowledgementContainOnlyBoundMetadata() throws {
    let request = request()
    XCTAssertTrue(Codex.acceptsOutgoing(request.cancellation, desktop: "desktop", route: "route"))
    let receipt = try XCTUnwrap(AgentResultReceipt.fromPayload(reply(request), desktopId: "desktop"))
    var ack = receipt.payload; ack["message_id"] = UUID().uuidString
    XCTAssertTrue(Codex.acceptsOutgoing(ack, desktop: "desktop", route: "route"))
    XCTAssertNil(ack["content"]); XCTAssertNil(ack["attachments"])
    ack["sha256"] = "invalid"
    XCTAssertFalse(Codex.acceptsOutgoing(ack, desktop: "desktop", route: "route"))
  }

  func testShutdownDiscardsPendingResultsAndDuplicateActiveIdentityIsRejected() throws {
    let request = request(); let exchange = GalaxySSIHealthReportCodexExchange()
    try exchange.begin(request)
    XCTAssertThrowsError(try exchange.begin(request))
    _ = exchange.receive(reply(request), desktop: "desktop", route: "route")
    exchange.removeAll()
    XCTAssertNil(exchange.outcome(request))
    XCTAssertNil(exchange.receive(reply(request), desktop: "desktop", route: "route"))
  }

  private func request() -> Codex.Request {
    let route = GalaxySSIHealthDesktopResearch.Route(connector: .init(contactId: "desktop:codex", desktopId: "desktop",
      clientRouteId: "route", modelId: "saved-model", reasoningEffort: .high), desktopFingerprint: "pinned")
    return .init(target: .init(route: route, authority: "Fixture Desktop"))
  }
  private func reply(_ request: Codex.Request) -> [String: Any] {
    ["type": "text", "contact_id": request.target.route.connector.contactId, "agent_id": "codex",
     "client_route_id": request.identity.clientRouteId, "conversation_id": request.identity.conversationId,
     "task_id": request.identity.taskId, "turn_id": request.identity.turnId, "source_message_id": String(request.source),
     "execution_generation": 1, "task_status": "completed", "success": true, "content": "{\"rows\":[]}",
     "sha256": String(repeating: "a", count: 64)]
  }
}
