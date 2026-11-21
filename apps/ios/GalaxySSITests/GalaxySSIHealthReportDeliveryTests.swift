import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthReportDeliveryTests: XCTestCase {
  typealias Delivery = GalaxySSIHealthReportDelivery
  typealias Codex = GalaxySSIHealthReportCodex

  func testRejectedPublicationRetriesOnceWithoutAnAdmissionProbe() async throws {
    let h = Harness()
    h.onPublish = { [unowned h] count in
      if count == 2 { h.reply = .result("recovered") }
      return count == 2
    }
    let text = try await h.run()
    XCTAssertEqual(text, "recovered"); XCTAssertEqual(h.publications, 2); XCTAssertEqual(h.probes, 0)
  }

  func testTwoRejectedPublicationsReportNotSent() async {
    let h = Harness(); h.onPublish = { _ in false }
    await expect(h, .notSent)
    XCTAssertEqual(h.publications, 2); XCTAssertEqual(h.probes, 0)
  }

  func testAuthenticatedMissingTaskAllowsOnlyOneRetry() async throws {
    let h = Harness(); h.observed = .missing
    h.onPublish = { [unowned h] count in if count == 2 { h.reply = .result("found") }; return true }
    let text = try await h.run()
    XCTAssertEqual(text, "found"); XCTAssertEqual(h.publications, 2); XCTAssertEqual(h.probes, 1)
  }

  func testMissingTaskAfterSecondPublicationReportsNotAccepted() async {
    let h = Harness(); h.observed = .missing
    await expect(h, .notAccepted)
    XCTAssertEqual(h.publications, 2); XCTAssertEqual(h.probes, 2)
  }

  func testAcceptedThenRejectedPublicationIsNotReportedAsNeverSent() async {
    let h = Harness(); h.observed = .missing; h.onPublish = { $0 == 1 }
    await expect(h, .notAccepted)
    XCTAssertEqual(h.publications, 2); XCTAssertEqual(h.probes, 1)
  }

  func testUnknownOrActiveAdmissionNeverCausesASecondPublication() async {
    for state in [Delivery.Admission.unknown, .active] {
      let h = Harness(); h.observed = state
      await expect(h, .replyTimeout)
      XCTAssertEqual(h.publications, 1); XCTAssertEqual(h.probes, 2)
    }
  }

  func testTerminalFailureDoesNotRepublish() async {
    let h = Harness(); h.observed = .terminalFailure
    await expect(h, .remoteFailure)
    XCTAssertEqual(h.publications, 1)
  }

  func testDeadlineActiveOrCompletedGetsOneBoundedGraceWithoutResending() async {
    for status in [Delivery.Admission.active, .completed] {
      let h = Harness()
      h.onProbe = { [unowned h] in h.probes == 1 ? .unknown : status }
      await expect(h, .replyTimeout)
      XCTAssertEqual(h.publications, 1); XCTAssertEqual(h.probes, 2)
      XCTAssertEqual(h.clock, 3)
    }
  }

  func testReplyArrivingDuringDeadlineProbeWinsWithoutGraceOrResend() async throws {
    let h = Harness()
    h.onProbe = { [unowned h] in
      if h.probes == 2 { h.reply = .result("deadline reply") }
      return .unknown
    }
    let text = try await h.run()
    XCTAssertEqual(text, "deadline reply")
    XCTAssertEqual(h.publications, 1); XCTAssertEqual(h.probes, 2)
  }

  func testReplyDuringBoundedGraceIsAcceptedAndGraceDoesNotRepeat() async throws {
    let h = Harness(); h.observed = .completed
    h.onSleep = { [unowned h] in if h.probes == 2 { h.reply = .result("grace reply") } }
    let text = try await h.run()
    XCTAssertEqual(text, "grace reply"); XCTAssertEqual(h.publications, 1); XCTAssertEqual(h.probes, 2)
  }

  func testDeadlineTerminalFailureIsNotPhoneTimeout() async {
    let h = Harness()
    h.onProbe = { [unowned h] in h.probes == 1 ? .active : .terminalFailure }
    await expect(h, .remoteFailure)
    XCTAssertEqual(h.publications, 1); XCTAssertEqual(h.probes, 2)
  }

  func testMissingAtDeadlineDoesNotResubmitAnAlreadyAdmittedRequest() async {
    let h = Harness()
    h.onProbe = { [unowned h] in h.probes == 1 ? .active : .missing }
    await expect(h, .replyTimeout)
    XCTAssertEqual(h.publications, 1); XCTAssertEqual(h.probes, 2)
  }

  func testTerminalReplyWinsOverAMissingAdmissionObservation() async throws {
    let h = Harness()
    h.onProbe = { [unowned h] in h.reply = .result("late result"); return .missing }
    let text = try await h.run()
    XCTAssertEqual(text, "late result"); XCTAssertEqual(h.publications, 1)
  }

  func testAuthenticatedFailureReplyWinsOverMissingAdmission() async {
    let h = Harness()
    h.onProbe = { [unowned h] in h.reply = .failed; return .missing }
    await expect(h, .remoteFailure)
    XCTAssertEqual(h.publications, 1)
  }

  func testChangingAuthorizationDuringProbePreventsRetry() async {
    let h = Harness()
    h.onProbe = { [unowned h] in h.allowed = false; return .missing }
    do { _ = try await h.run(); XCTFail("Expected authorization failure") }
    catch {
      guard let route = error as? MqttRouteError else { return XCTFail("Expected route invalidation") }
      if case .identityChanged = route { } else { XCTFail("Expected route invalidation") }
    }
    XCTAssertEqual(h.publications, 1)
  }

  func testCancellationDoesNotProbeOrRetry() async {
    let h = Harness(); h.cancelSleep = true
    do { _ = try await h.run(); XCTFail("Expected cancellation") }
    catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(h.publications, 1); XCTAssertEqual(h.probes, 0)
  }

  func testRetryPayloadKeepsTaskTurnSourceConversationAndMessageIdentity() async throws {
    let request = request(), h = Harness()
    var identities: [[String]] = []
    h.observed = .missing
    h.onPublish = { [unowned h] count in
      let payload = try? request.payload(jpeg: Data([0xff, 0xd8, 0xff, 0xd9]), instructions: "Only this image")
      identities.append(["message_id", "conversation_id", "task_id", "turn_id", "source_message_id"].map { payload?.string($0) ?? "" })
      if count == 2 { h.reply = .result("ok") }
      return true
    }
    _ = try await h.run()
    XCTAssertEqual(identities.count, 2); XCTAssertEqual(identities[0], identities[1])
    XCTAssertEqual(identities[0][0], request.id.uuidString)
  }

  func testAdmissionQueryContainsOnlyBoundMetadataAndRejectsExtraContent() throws {
    let request = request(), nonce = UUID().uuidString
    var payload = try XCTUnwrap(request.admissionQuery(nonce: nonce))
    XCTAssertTrue(request.acceptsAdmissionQuery(payload, nonce: nonce, desktop: "desktop", route: "route"))
    XCTAssertFalse(Codex.acceptsOutgoing(payload, desktop: "desktop", route: "route"))
    XCTAssertNil(payload["include_result_page"]); XCTAssertNil(payload["attachments"]); XCTAssertNil(payload["content"])
    payload["include_result_page"] = true
    XCTAssertFalse(request.acceptsAdmissionQuery(payload, nonce: nonce, desktop: "desktop", route: "route"))
    payload.removeValue(forKey: "include_result_page"); payload["content"] = "not allowed"
    XCTAssertFalse(request.acceptsAdmissionQuery(payload, nonce: nonce, desktop: "desktop", route: "route"))
  }

  func testOnlyAuthenticatedExactAdmissionCanProveTaskAbsence() throws {
    let request = request(), exchange = GalaxySSIHealthReportCodexExchange(), nonce = UUID().uuidString
    try exchange.begin(request)
    XCTAssertEqual(exchange.beginAdmission(request, nonce: nonce, now: 10), nonce)
    let payload = admission(request, nonce: nonce)
    XCTAssertFalse(exchange.receiveAdmission(payload, desktop: "other", route: "route", now: 11))
    XCTAssertFalse(exchange.receiveAdmission(payload, desktop: "desktop", route: "other", now: 11))
    XCTAssertNil(exchange.admission(request, nonce: nonce))
    XCTAssertTrue(exchange.receiveAdmission(payload, desktop: "desktop", route: "route", now: 11))
    XCTAssertEqual(exchange.admission(request, nonce: nonce), .missing)
    XCTAssertNil(exchange.outcome(request))
  }

  func testWrongIdentityNonceBatchPeerChatAndGenerationAreRejected() throws {
    for field in ["contact_id", "agent_id", "conversation_id", "task_id", "turn_id", "source_message_id", "client_route_id",
                  "nonce", "batch", "peer", "generation"] {
      let request = request(), exchange = GalaxySSIHealthReportCodexExchange(), nonce = UUID().uuidString
      try exchange.begin(request); _ = exchange.beginAdmission(request, nonce: nonce, now: 10)
      var payload = admission(request, nonce: nonce)
      var item = try XCTUnwrap((payload["items"] as? [[String: Any]])?.first)
      switch field {
      case "nonce": payload["request_id"] = UUID().uuidString
      case "batch": payload["items"] = [item, item]
      case "peer": payload["peer_chat"] = true
      case "generation": item["execution_generation"] = 2; payload["items"] = [item]
      default: item[field] = "wrong"; payload["items"] = [item]
      }
      XCTAssertFalse(exchange.receiveAdmission(payload, desktop: "desktop", route: "route", now: 11), field)
      XCTAssertNil(exchange.admission(request, nonce: nonce), field)
    }
  }

  func testExpiredAndCancelledAdmissionCorrelationsCannotAuthorizeRetry() throws {
    let request = request(), exchange = GalaxySSIHealthReportCodexExchange(), nonce = UUID().uuidString
    try exchange.begin(request); _ = exchange.beginAdmission(request, nonce: nonce, now: 10)
    let payload = admission(request, nonce: nonce)
    XCTAssertFalse(exchange.receiveAdmission(payload, desktop: "desktop", route: "route", now: 8_000_000_011))
    exchange.finishAdmission(request, nonce: nonce)
    XCTAssertFalse(exchange.receiveAdmission(payload, desktop: "desktop", route: "route", now: 11))
    XCTAssertNil(exchange.admission(request, nonce: nonce))
    XCTAssertTrue(exchange.handlesAdmission(payload))
  }

  func testUnknownStatusAndUnsolicitedResultPageDoNotBecomeARecognitionReply() throws {
    let request = request(), exchange = GalaxySSIHealthReportCodexExchange(), nonce = UUID().uuidString
    try exchange.begin(request); _ = exchange.beginAdmission(request, nonce: nonce, now: 10)
    var payload = admission(request, nonce: nonce)
    var item = try XCTUnwrap((payload["items"] as? [[String: Any]])?.first)
    item["status"] = "not_proven_absent"; item["result_page"] = ["content": "private body"]
    payload["items"] = [item]
    XCTAssertTrue(exchange.receiveAdmission(payload, desktop: "desktop", route: "route", now: 11))
    XCTAssertEqual(exchange.admission(request, nonce: nonce), .unknown)
    XCTAssertNil(exchange.outcome(request))
  }

  func testShutdownClearsAllAdmissionState() throws {
    let request = request(), exchange = GalaxySSIHealthReportCodexExchange(), nonce = UUID().uuidString
    try exchange.begin(request); _ = exchange.beginAdmission(request, nonce: nonce, now: 10)
    exchange.removeAll()
    XCTAssertNil(exchange.admission(request, nonce: nonce))
    XCTAssertNil(exchange.beginAdmission(request, now: 11))
    XCTAssertFalse(exchange.receiveAdmission(admission(request, nonce: nonce), desktop: "desktop", route: "route", now: 11))
  }

  func testOnlyKnownRunningStatusesGetGraceAndCompletedIsDistinct() throws {
    for (status, expected) in [("completed", Delivery.Admission.completed), ("running", .active),
                              ("waiting_input", .unknown), ("waiting_approval", .unknown), ("future_status", .unknown)] {
      let request = request(), exchange = GalaxySSIHealthReportCodexExchange(), nonce = UUID().uuidString
      try exchange.begin(request); _ = exchange.beginAdmission(request, nonce: nonce, now: 10)
      var payload = admission(request, nonce: nonce)
      var item = try XCTUnwrap((payload["items"] as? [[String: Any]])?.first)
      item["status"] = status; item["execution_generation"] = 1; payload["items"] = [item]
      XCTAssertTrue(exchange.receiveAdmission(payload, desktop: "desktop", route: "route", now: 11))
      XCTAssertEqual(exchange.admission(request, nonce: nonce), expected)
    }
  }

  func testFailureCategoriesPreserveDeliveryAndResultDistinctions() {
    XCTAssertEqual(GalaxySSIHealthReportFailure.classify(Delivery.Problem.notSent), .notSent)
    XCTAssertEqual(GalaxySSIHealthReportFailure.classify(Delivery.Problem.notAccepted), .notAccepted)
    XCTAssertEqual(GalaxySSIHealthReportFailure.classify(Delivery.Problem.replyTimeout), .replyTimeout)
    XCTAssertEqual(GalaxySSIHealthReportFailure.classify(Delivery.Problem.remoteFailure), .remoteFailure)
    XCTAssertEqual(GalaxySSIHealthReportFailure.classify(GalaxySSIHealthReportVision.ReplyProblem.format), .replyFormat)
    XCTAssertEqual(GalaxySSIHealthReportFailure.classify(GalaxySSIHealthReportVision.ReplyProblem.noSupportedRows), .noSupportedRows)
    XCTAssertEqual(GalaxySSIHealthReportFailure.classify(GalaxySSIHealthReportVision.ReplyProblem.invalidRows), .invalidRows)
    XCTAssertEqual(GalaxySSIHealthReportFailure.classify(GalaxySSIHealthReportVision.ReplyProblem.unsupportedMetrics), .unsupportedMetrics)
    XCTAssertEqual(GalaxySSIHealthReportFailure.classify(GalaxySSIHealthReportVision.ReplyProblem.unreadableImage), .unreadableImage)
    XCTAssertEqual(GalaxySSIHealthReportFailure.classify(GalaxySSIHealthReportVision.ReplyProblem.ambiguousSample), .ambiguousSample)
    XCTAssertEqual(GalaxySSIHealthReportFailure.classify(AgentDataDisclosureBlockedError(destination: "Codex")), .privacy)
  }

  private func expect(_ h: Harness, _ problem: Delivery.Problem) async {
    do { _ = try await h.run(); XCTFail("Expected delivery failure") }
    catch { XCTAssertEqual(error as? Delivery.Problem, problem) }
  }

  private func request() -> Codex.Request {
    let route = GalaxySSIHealthDesktopResearch.Route(connector: .init(contactId: "desktop:codex", desktopId: "desktop",
      clientRouteId: "route", modelId: "saved-model", reasoningEffort: .high), desktopFingerprint: "pinned")
    return .init(target: .init(route: route, authority: "Fixture Desktop"))
  }

  private func admission(_ request: Codex.Request, nonce: String) -> [String: Any] {
    var item = request.evidenceBinding!.fields.mapValues { $0 as Any }
    item["status"] = "unavailable"; item["execution_generation"] = 0
    return ["type": "agent_task_recovery_result", "request_id": nonce, "desktop_id": "desktop",
      "client_route_id": "route", "items": [item]]
  }

  @MainActor private final class Harness {
    var clock: UInt64 = 0
    var publications = 0, probes = 0
    var reply: GalaxySSIHealthReportCodexExchange.Outcome?
    var observed = Delivery.Admission.unknown
    var allowed = true, cancelSleep = false
    var onPublish: ((Int) -> Bool)?
    var onProbe: (() -> Delivery.Admission)?
    var onSleep: (() -> Void)?
    func run() async throws -> String {
      try await Delivery.receive(publish: { self.publications += 1; return self.onPublish?(self.publications) ?? true },
        probe: { self.probes += 1; return self.onProbe?() ?? self.observed }, outcome: { self.reply }, valid: { self.allowed },
        timing: .init(earlyWait: 1, responseWait: 1, retryDelay: 0, poll: 1, activeGrace: 1, completedGrace: 1), now: { self.clock },
        sleep: { if self.cancelSleep { throw CancellationError() }; self.clock += $0; self.onSleep?() })
    }
  }
}
