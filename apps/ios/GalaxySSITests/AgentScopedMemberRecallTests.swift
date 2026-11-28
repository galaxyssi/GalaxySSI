import XCTest
@testable import GalaxySSI

@MainActor
final class AgentScopedMemberRecallTests: XCTestCase {
  private func offer(profile: String = "profile") -> AgentScopedMemberRecall.Offer {
    let person = UUID(), team = "research-team"
    return .init(profile: profile, desktop: "desktop", fingerprint: "fingerprint", route: "route",
      contact: "desktop:codex", transportBinding: "transport",
      scope: .init(runId: AgentTeamDispatchIds.supervisorRunId(teamId: team), conversationId: "ios-agent-fixture",
        turnId: UUID().uuidString, memberId: person.uuidString.lowercased(), sourceId: UUID().uuidString),
      teamID: team, personID: person, primaryMemberID: person.uuidString.lowercased(),
      model: "gpt-5.4", effort: .high, deliveryMode: .respond)
  }
  private func payload(_ offer: AgentScopedMemberRecall.Offer, phase: String = "authorize", generation: Int64 = 1,
      nonce: String = "nonce") -> [String: Any] {
    ["type": AgentDesktopCollaborationArchiveRecall.requestType, "contract": AgentDesktopCollaborationArchiveRecall.contract,
      "request_id": nonce, "phase": phase, "expires_at": Int64(60_000), "execution_generation": generation,
      "client_route_id": offer.route, "contact_id": offer.contact, "agent_id": "codex",
      "conversation_id": offer.scope.conversationId, "turn_id": offer.scope.turnId,
      "source_message_id": offer.scope.sourceId, "task_id": offer.scope.sourceId, "arguments": [:] as [String: Any]]
  }
  private func assignment(_ offer: AgentScopedMemberRecall.Offer) -> [String: Any] {
    ["type": "text", "contact_id": offer.contact, "desktop_id": offer.desktop, "agent_id": "codex",
      "client_route_id": offer.route, "conversation_id": offer.scope.conversationId, "turn_id": offer.scope.turnId,
      "task_id": offer.scope.sourceId, "client_message_id": offer.scope.sourceId, "team_id": offer.teamID,
      "agent_instance_id": offer.scope.memberId, "run_id": offer.scope.runId,
      "delivery_mode": offer.deliveryMode.rawValue, "execution_mode": AgentTaskExecutionMode.autoComplete.rawValue,
      "result_contract": AgentOutboundTeamContext.workspaceResultContract, "agent_team_message": true,
      "agent_invocation": AgentInvocationRequestJsonCodec.encode(modelId: offer.model, reasoningEffort: offer.effort)!]
  }
  func testGenerationRulesAllowOnlyCurrentOrOneObservedStepAhead() {
    XCTAssertEqual(AgentScopedMemberRecall.generation(observed: nil, requested: 1), .current)
    XCTAssertEqual(AgentScopedMemberRecall.generation(observed: nil, requested: 2), .unavailable)
    XCTAssertEqual(AgentScopedMemberRecall.generation(observed: 1, requested: 2), .next)
    XCTAssertEqual(AgentScopedMemberRecall.generation(observed: 2, requested: 2), .current)
    XCTAssertEqual(AgentScopedMemberRecall.generation(observed: 2, requested: 1), .unavailable)
    XCTAssertEqual(AgentScopedMemberRecall.generation(observed: 1, requested: 3), .unavailable)
    XCTAssertEqual(AgentScopedMemberRecall.generation(observed: 0, requested: 0), .unavailable)
  }
  func testAuthorizationArgumentsAndUnknownFieldsCannotCarryContent() {
    let original = payload(offer())
    XCTAssertNotNil(AgentScopedMemberRecall.Request(original, now: 1_000))
    for key in ["content", "prompt", "delivery", "path", "agent_team_message", "request_kind"] {
      var changed = original; changed[key] = "forbidden"
      XCTAssertNil(AgentScopedMemberRecall.Request(changed, now: 1_000), key)
    }
    var changed = original; changed["arguments"] = ["mode": "workspace"]
    XCTAssertNil(AgentScopedMemberRecall.Request(changed, now: 1_000))
  }
  func testBooleanAndIntegerLookalikesAreNotAuthority() {
    let original = payload(offer())
    for value in [1 as Any, "true", false] {
      var changed = original; changed[AgentScopedMemberRecall.flag] = value
      XCTAssertNil(AgentScopedMemberRecall.Request(changed, now: 1_000))
    }
    for key in ["execution_generation", "expires_at"] {
      for value in [true as Any, "1", 1.5] {
        var changed = original; changed[key] = value
        XCTAssertNil(AgentScopedMemberRecall.Request(changed, now: 1_000))
      }
    }
    var changed = original; changed["request_id"] = 123
    XCTAssertNil(AgentScopedMemberRecall.Request(changed, now: 1_000))
  }
  func testReadRequiresStampedFlagAndBoundedExpiry() {
    var read = payload(offer(), phase: "read")
    read["arguments"] = ["mode": "workspace"]
    XCTAssertNil(AgentScopedMemberRecall.Request(read, now: 1_000))
    read[AgentScopedMemberRecall.flag] = true
    XCTAssertNotNil(AgentScopedMemberRecall.Request(read, now: 1_000))
    XCTAssertNil(AgentScopedMemberRecall.Request(read, now: 60_000))
    read["expires_at"] = Int64(61_001)
    XCTAssertNil(AgentScopedMemberRecall.Request(read, now: 1_000))
  }
  func testUnavailableProbeDoesNotAuthorize() throws {
    let request = try XCTUnwrap(AgentScopedMemberRecall.Request(payload(offer()), now: 1_000))
    var replay = AgentScopedMemberRecall.AuthorizationReplay()
    XCTAssertEqual(AgentScopedMemberRecall.authorize(request, replay: &replay, now: 1_000, probe: { nil }),
      AgentScopedMemberRecall.unavailable)
  }
  func testTwoCurrentObservationsProduceContentFreeResult() throws {
    let original = offer(), request = try XCTUnwrap(AgentScopedMemberRecall.Request(payload(original), now: 1_000))
    var replay = AgentScopedMemberRecall.AuthorizationReplay(), calls = 0
    let result = AgentScopedMemberRecall.authorize(request, replay: &replay, now: 1_000) {
      calls += 1; return .init(offer: original, generation: .current)
    }
    XCTAssertEqual(calls, 2)
    XCTAssertEqual(result, ["success": .bool(true), "status": .string("authorized")])
    XCTAssertEqual(Set(result.keys), ["success", "status"])
  }
  func testBindingDriftBetweenMetadataReadsDenies() throws {
    let first = offer(), other = offer(profile: "other-profile")
    let request = try XCTUnwrap(AgentScopedMemberRecall.Request(payload(first), now: 1_000))
    var replay = AgentScopedMemberRecall.AuthorizationReplay(), calls = 0
    let result = AgentScopedMemberRecall.authorize(request, replay: &replay, now: 1_000) {
      calls += 1; return .init(offer: calls == 1 ? first : other, generation: .current)
    }
    XCTAssertEqual(result, AgentScopedMemberRecall.unavailable)
  }
  func testWaitingGenerationRequiresFreshNonceToBecomeAuthorized() throws {
    let original = offer()
    let request = try XCTUnwrap(AgentScopedMemberRecall.Request(payload(original, generation: 2), now: 1_000))
    var replay = AgentScopedMemberRecall.AuthorizationReplay()
    let waiting = AgentScopedMemberRecall.authorize(request, replay: &replay, now: 1_000) { .init(offer: original, generation: .next) }
    XCTAssertEqual(waiting, ["success": .bool(false), "status": .string("generation_not_ready")])
    XCTAssertEqual(AgentScopedMemberRecall.authorize(request, replay: &replay, now: 1_001) {
      .init(offer: original, generation: .current)
    }, AgentScopedMemberRecall.unavailable)
    let fresh = try XCTUnwrap(AgentScopedMemberRecall.Request(payload(original, generation: 2, nonce: "fresh"), now: 1_001))
    XCTAssertEqual(AgentScopedMemberRecall.authorize(fresh, replay: &replay, now: 1_001) {
      .init(offer: original, generation: .current)
    }["status"], .string("authorized"))
  }
  func testMidProbePromotionNeedsThirdMatchingObservation() throws {
    let original = offer(), request = try XCTUnwrap(AgentScopedMemberRecall.Request(payload(original, generation: 2), now: 1_000))
    var replay = AgentScopedMemberRecall.AuthorizationReplay(), calls = 0
    let result = AgentScopedMemberRecall.authorize(request, replay: &replay, now: 1_000) {
      calls += 1; return .init(offer: original, generation: calls == 1 ? .next : .current)
    }
    XCTAssertEqual(calls, 3)
    XCTAssertEqual(result["status"], .string("authorized"))
  }
  func testGenerationRegressionDuringProbeDenies() throws {
    let original = offer(), request = try XCTUnwrap(AgentScopedMemberRecall.Request(payload(original), now: 1_000))
    var replay = AgentScopedMemberRecall.AuthorizationReplay(), calls = 0
    XCTAssertEqual(AgentScopedMemberRecall.authorize(request, replay: &replay, now: 1_000) {
      calls += 1; return .init(offer: original, generation: calls == 1 ? .current : .next)
    }, AgentScopedMemberRecall.unavailable)
  }
  func testNonceCannotChangeSemanticFlagOrAssignment() throws {
    let original = offer(), request = try XCTUnwrap(AgentScopedMemberRecall.Request(payload(original), now: 1_000))
    var replay = AgentScopedMemberRecall.AuthorizationReplay()
    _ = AgentScopedMemberRecall.authorize(request, replay: &replay, now: 1_000) { .init(offer: original, generation: .current) }
    var changed = request.payload; changed[AgentScopedMemberRecall.flag] = true
    let changedRequest = try XCTUnwrap(AgentScopedMemberRecall.Request(changed, now: 1_000))
    XCTAssertEqual(AgentScopedMemberRecall.authorize(changedRequest, replay: &replay, now: 1_000) {
      .init(offer: original, generation: .current)
    }, AgentScopedMemberRecall.unavailable)
  }
  func testOfferStampsOnlyExactOriginalAndPreservesModelOnDenial() {
    let original = offer()
    var body = assignment(original)
    XCTAssertTrue(original.encode(&body))
    XCTAssertNil(body["agent_team_message"])
    XCTAssertTrue(AgentScopedMemberRecall.trueFlag(body[AgentScopedMemberRecall.flag]))
    XCTAssertTrue(original.matches(body))
    for key in ["task_id", "contact_id", "team_id", "agent_instance_id", "client_route_id", "request_kind"] {
      var changed = assignment(original); changed[key] = "changed"
      let invocation = changed["agent_invocation"] as? [String: String]
      XCTAssertFalse(original.encode(&changed), key)
      XCTAssertEqual(changed["agent_invocation"] as? [String: String], invocation)
      XCTAssertNil(changed[AgentScopedMemberRecall.flag])
    }
  }
  func testOrdinaryTeamOwnerCanSendWhenOptionalOfferIsNotStamped() {
    let original = offer(), message = ChatMessage(contactId: "hermes", content: "Research", isMine: true,
      conversationId: original.scope.conversationId, turnId: original.scope.turnId)
    let team = AgentTeamReplyOwner(supervisorRunId: original.scope.runId, memberId: original.scope.memberId,
      conversationId: original.scope.conversationId, turnId: original.scope.turnId, sourceMessageId: original.scope.sourceId,
      contactId: original.contact, deliveryMode: .respond)
    let owner = MqttDesktopConnectorProjection.TaskOwner(message: message, team: team, teamID: original.teamID, originalRecallOffer: original)
    XCTAssertTrue(owner.matches(assignment(original)))
    var body = assignment(original); XCTAssertTrue(original.encode(&body)); XCTAssertTrue(owner.matches(body))
    body["agent_invocation"] = ["model_id": "another-model"]
    XCTAssertFalse(owner.matches(body))
  }
  func testConfirmationRequiresBoundReceiptShape() {
    var body = payload(offer(), phase: "confirm")
    body[AgentScopedMemberRecall.flag] = true
    body["arguments"] = ["mode": "evidence"]
    body["delivery"] = ["receipt_id": "short-lived-hmac-token", "content_sha256": String(repeating: "a", count: 64)]
    XCTAssertNotNil(AgentScopedMemberRecall.Request(body, now: 1_000))
    body["delivery"] = ["receipt_id": "short-lived-hmac-token", "content_sha256": "wrong"]
    XCTAssertNil(AgentScopedMemberRecall.Request(body, now: 1_000))
  }
  func testArchivedOfferIsOptionalForOldMembersAndRoundTrips() throws {
    var member = AgentTeamMemberSnapshot(agentId: "desktop:codex")
    XCTAssertNil(try JSONDecoder().decode(AgentTeamMemberSnapshot.self, from: JSONEncoder().encode(member)).originalRecallOffer)
    member.originalRecallOffer = offer()
    XCTAssertEqual(try JSONDecoder().decode(AgentTeamMemberSnapshot.self,
      from: JSONEncoder().encode(member)).originalRecallOffer, member.originalRecallOffer)
  }
  func testAuthorizationResponseRejectsContentAndNumericBoolean() {
    var body = payload(offer())
    body.removeValue(forKey: "arguments"); body.removeValue(forKey: "expires_at")
    body["type"] = AgentDesktopCollaborationArchiveRecall.responseType
    body["result"] = ["success": true, "status": "authorized"]
    XCTAssertTrue(AgentScopedMemberRecall.acceptsResponse(body))
    body["result"] = ["success": true, "status": "authorized", "content": "not permitted"]
    XCTAssertFalse(AgentScopedMemberRecall.acceptsResponse(body))
    body["result"] = ["success": 1, "status": "authorized"]
    XCTAssertFalse(AgentScopedMemberRecall.acceptsResponse(body))
  }
  private func peerFixture() -> (AgentScopedMemberRecall.Offer, GalaxySSIContact, ServerLink) {
    let original = offer()
    let link = ServerLink(desktopId: original.desktop, desktopName: "Fixture Desktop",
      desktopFingerprint: original.fingerprint, signalName: "fixture-signal",
      routes: .init(clientRouteId: original.route, linkSecret: "fixture-secret", localFingerprint: "fixture-phone",
        remoteFingerprint: original.fingerprint), paired: true, accessProfile: "fixture", accessScopes: [], updatedAt: Date())
    let bound = AgentScopedMemberRecall.Offer(profile: original.profile, desktop: original.desktop,
      fingerprint: original.fingerprint, route: original.route, contact: original.contact,
      transportBinding: GalaxySSITransportReceiptJournal.binding(peerId: link.desktopId, routes: link.routes),
      scope: original.scope, teamID: original.teamID, personID: original.personID,
      primaryMemberID: original.primaryMemberID, model: original.model, effort: original.effort, deliveryMode: original.deliveryMode)
    let contact = GalaxySSIContact(id: bound.contact, galaxySSIId: "fixture-peer", name: "Fixture", displayName: "Fixture",
      type: "agent", agentKind: "agent", deliveryMode: .pcConnector, trustState: .verified,
      desktopId: bound.desktop, desktopName: "Fixture Desktop", identityFingerprint: bound.fingerprint,
      setupStatus: "ready", setupDetail: "", cloudProvider: "", cloudModels: [], selectedCloudModelId: "",
      agentId: "codex", deleted: false, createdAt: Date(), updatedAt: Date())
    return (bound, contact, link)
  }
  func testCurrentPeerMustRetainArchivedContactFingerprintAndRouteSecret() {
    let (bound, contact, originalLink) = peerFixture()
    var link = originalLink
    XCTAssertTrue(bound.matchesPeer(contact, link: link))
    var changed = contact; changed.identityFingerprint = bound.fingerprint.uppercased()
    XCTAssertTrue(bound.matchesPeer(changed, link: link))
    changed.identityFingerprint = "replacement"
    XCTAssertFalse(bound.matchesPeer(changed, link: link))
    changed = contact; changed.deleted = true
    XCTAssertFalse(bound.matchesPeer(changed, link: link))
    changed = contact; changed.desktop_disconnected = true
    XCTAssertFalse(bound.matchesPeer(changed, link: link))
    link.routes.linkSecret = "replacement-secret"
    XCTAssertFalse(bound.matchesPeer(contact, link: link))
  }
  func testPeerRevocationAndRouteReplacementCannotReuseArchivedOffer() {
    let (bound, contact, originalLink) = peerFixture()
    var link = originalLink
    XCTAssertTrue(bound.matchesPeer(contact, link: link))
    var changed = contact; changed.id = "other:codex"
    XCTAssertFalse(bound.matchesPeer(changed, link: link))
    changed = contact; changed.agentId = "other-agent"
    XCTAssertFalse(bound.matchesPeer(changed, link: link))
    changed = contact; changed.trustState = .unverified
    XCTAssertFalse(bound.matchesPeer(changed, link: link))
    link.paired = false
    XCTAssertFalse(bound.matchesPeer(contact, link: link))
    link.paired = true; link.routes.clientRouteId = "replacement-route"
    XCTAssertFalse(bound.matchesPeer(contact, link: link))
  }
}
