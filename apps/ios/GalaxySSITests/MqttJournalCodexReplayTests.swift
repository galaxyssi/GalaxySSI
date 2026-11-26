import XCTest
@testable import GalaxySSI

private func journalReplayFixture(source: ChatMessage, desktop: String = "desktop", contact: String = "codex",
  agent: String = "codex", route: String = "route", invocation: [String: String]? = nil)
  throws -> (record: AgentDesktopReplyRecoveryRecord, payload: [String: Any]) {
  var seed = try XCTUnwrap(AgentCodexReplaySeed(source: source, text: source.content, targetId: contact,
    executionMode: .planOnly, hasAttachments: false, voiceSessionId: "", lockedToOrigin: false,
    invocation: invocation, transportContext: "Original context"))
  XCTAssertEqual(seed.budget.next(failed: contact, attemptId: source.id.uuidString,
    confirmedTimeout: true, alternatives: []), contact)
  let attempt = UUID()
  let binding = AgentDesktopReplyBinding(desktopId: desktop, displayContactId: source.contactId,
    sourceId: source.id, contactId: contact, agentId: agent, identity: .init(clientRouteId: route,
      conversationId: source.conversationId, taskId: attempt.uuidString, turnId: source.turnId), attemptSourceId: attempt)
  let record = AgentDesktopReplyRecoveryRecord(binding: binding, createdAt: 1_000,
    codexReplay: seed, codexDispatchPending: true)
  var payload: [String: Any] = binding.fields.mapValues { $0 as Any }
  payload["type"] = "text"
  payload["message_id"] = attempt.uuidString
  payload["client_message_id"] = attempt.uuidString
  payload["desktop_id"] = desktop
  payload["content"] = source.content
  payload["_galaxyssi_conversation_id"] = binding.identity.conversationId
  payload["_galaxyssi_turn_id"] = binding.identity.turnId
  payload["_galaxyssi_task_id"] = binding.identity.taskId
  payload["execution_mode"] = AgentTaskExecutionMode.planOnly.rawValue
  payload["_galaxyssi_task_execution_mode"] = AgentTaskExecutionMode.planOnly.rawValue
  payload["_galaxyssi_conversation_context"] = seed.transportContext
  payload["_galaxyssi_long_term_write_allowed"] = "false"
  payload["_galaxyssi_conversation_has_attachments"] = "false"
  payload["time"] = 2_000
  if let invocation { payload["agent_invocation"] = invocation }
  return (record, payload)
}

final class MqttJournalCodexReplayTests: XCTestCase {
  private func source() -> ChatMessage {
    ChatMessage(contactId: "hermes", content: "Review the project", isMine: true, conversationId: "conversation", turnId: "turn")
  }

  func testExactSavedAttemptSupportsExistingClientSourceFallbackWithoutInventingIdentity() throws {
    let original = source(), f = try journalReplayFixture(source: original)
    XCTAssertTrue(AgentJournalCodexReplayPolicy.matchesRequest(f.payload, record: f.record, source: original))
    var clientOnly = f.payload
    clientOnly.removeValue(forKey: "source_message_id")
    XCTAssertTrue(AgentJournalCodexReplayPolicy.matchesRequest(clientOnly, record: f.record, source: original))
    XCTAssertNotEqual(f.record.binding.sourceIdentity, original.id.uuidString)
  }

  func testEveryRequestIdentityAndOriginalTextDimensionIsRequired() throws {
    let original = source(), f = try journalReplayFixture(source: original)
    for key in ["message_id", "client_message_id", "source_message_id", "client_route_id", "conversation_id",
                "turn_id", "task_id", "contact_id", "agent_id", "desktop_id", "content", "_galaxyssi_conversation_context",
                "_galaxyssi_conversation_id", "_galaxyssi_turn_id", "_galaxyssi_task_id"] {
      var wrong = f.payload
      wrong[key] = "other"
      XCTAssertFalse(AgentJournalCodexReplayPolicy.matchesRequest(wrong, record: f.record, source: original), key)
    }
    var changed = original
    changed.content = "A different request"
    XCTAssertFalse(AgentJournalCodexReplayPolicy.matchesRequest(f.payload, record: f.record, source: changed))
  }

  func testReplayCannotGainEffectsAttachmentsVoiceOrTeamPrivileges() throws {
    let original = source(), f = try journalReplayFixture(source: original)
    let mutations: [String: Any] = ["execution_mode": AgentTaskExecutionMode.autoComplete.rawValue,
      "_galaxyssi_task_execution_mode": AgentTaskExecutionMode.autoComplete.rawValue,
      "_galaxyssi_long_term_write_allowed": "true", "_galaxyssi_conversation_has_attachments": "true",
      "attachments": [] as [String], "voice_session_id": "voice", "run_id": "team", "peer_chat": true, "agent_team_message": true]
    for (key, value) in mutations {
      var wrong = f.payload
      wrong[key] = value
      XCTAssertFalse(AgentJournalCodexReplayPolicy.matchesRequest(wrong, record: f.record, source: original), key)
    }
  }

  func testManualTerminalAndMissingReplayRecordsFailClosed() throws {
    let original = source(), f = try journalReplayFixture(source: original)
    var record = f.record
    record.manualTargetLocked = true
    XCTAssertFalse(AgentJournalCodexReplayPolicy.matchesRequest(f.payload, record: record, source: original))
    record = f.record; record.status = "completed"
    XCTAssertFalse(AgentJournalCodexReplayPolicy.matchesRequest(f.payload, record: record, source: original))
    record = f.record; record.terminalObservedAt = 2_000
    XCTAssertFalse(AgentJournalCodexReplayPolicy.matchesRequest(f.payload, record: record, source: original))
    record = f.record; record.codexReplay = nil
    XCTAssertFalse(AgentJournalCodexReplayPolicy.matchesRequest(f.payload, record: record, source: original))
    record = f.record; record.binding.attemptSourceId = nil
    XCTAssertFalse(AgentJournalCodexReplayPolicy.matchesRequest(f.payload, record: record, source: original))
  }

  func testOriginalInvocationIsExactAndDoesNotLeakIntoAlternativeTarget() throws {
    let original = source(), f = try journalReplayFixture(source: original, invocation: ["model_id": "selected", "reasoning_effort": "low"])
    XCTAssertTrue(AgentJournalCodexReplayPolicy.matchesRequest(f.payload, record: f.record, source: original))
    var payload = f.payload
    payload["agent_invocation"] = ["model_id": "replacement"]
    XCTAssertFalse(AgentJournalCodexReplayPolicy.matchesRequest(payload, record: f.record, source: original))
    var record = f.record
    var seed = try XCTUnwrap(record.codexReplay)
    XCTAssertEqual(seed.budget.next(failed: "codex", attemptId: record.binding.sourceIdentity,
      confirmedTimeout: true, alternatives: ["other-agent"]), "other-agent")
    record.codexReplay = seed
    record.binding.contactId = "other-agent"
    record.binding.agentId = "other"
    payload = f.payload
    payload["contact_id"] = "other-agent"; payload["agent_id"] = "other"
    XCTAssertFalse(AgentJournalCodexReplayPolicy.matchesRequest(payload, record: record, source: original))
    payload.removeValue(forKey: "agent_invocation")
    XCTAssertTrue(AgentJournalCodexReplayPolicy.matchesRequest(payload, record: record, source: original))
  }

  func testReceiptPresentationKeepsAttemptTraceWhileMappingOnlyTheLocalSource() throws {
    let original = source(), f = try journalReplayFixture(source: original)
    let event = MqttDeliveryCompletions.Event(identity: sendTestIdentity(), messageID: f.record.binding.sourceIdentity,
      wireHash: String(repeating: "a", count: 64), traffic: MqttMultipathPolicy.Traffic.message.rawValue, requestHash: nil,
      sourceMessageID: f.record.binding.sourceIdentity, contactID: "codex", attachmentTransferID: "", receivedAt: 3_000, consumedAt: nil)
    let mapped = try XCTUnwrap(AgentJournalCodexReplayPolicy.presentationEvent(event, record: f.record, source: original))
    XCTAssertEqual(mapped.sourceMessageID, original.id.uuidString)
    XCTAssertEqual(mapped.messageID, event.messageID)
    XCTAssertEqual(mapped.wireHash, event.wireHash)
    XCTAssertEqual(mapped.identity, event.identity)
    XCTAssertEqual(event.sourceMessageID, f.record.binding.sourceIdentity)
    var wrong = f.record
    wrong.binding.attemptSourceId = UUID()
    XCTAssertNil(AgentJournalCodexReplayPolicy.presentationEvent(event, record: wrong, source: original))
  }
}

extension GalaxySSIStoreTests {
  @MainActor
  func testJournalReplayNeedsExplicitCurrentOwnerAndProjectsDeliveryToOriginalMessage() throws {
    let store = makeStore()
    let link = try store.addServerLink(from: makePairingQRCode())
    store.markServerPaired(desktopId: link.desktopId)
    let desktop = try XCTUnwrap(store.contacts.first { $0.isDesktopDeviceContact && $0.desktopId == link.desktopId })
    let contact = try XCTUnwrap(store.contact(id: "\(link.desktopId):codex"))
    let target = try XCTUnwrap(MqttPeerChatProjection(store: store, localFingerprint: link.routes.localFingerprint).destination(for: desktop))
    let session = store.createAgentSession(title: "Journal recovery")
    let original = store.appendOutgoing("Review the project", to: "hermes", turnId: "turn", conversationOverride: session.id)
    let f = try journalReplayFixture(source: original, desktop: link.desktopId, contact: contact.id,
      agent: contact.connectorAgentId, route: target.routeId)
    let identities = AgentTaskIdentityStore(defaults: store.defaults, storageKeyPrefix: "journal-replay-test")
    XCTAssertTrue(identities.register(contactId: contact.id, sourceMessageId: f.record.binding.sourceIdentity, identity: f.record.binding.identity))
    var projection = MqttDesktopConnectorProjection(store: store, identities: identities, commitResponse: { _, _ in })
    XCTAssertThrowsError(try projection.outgoingRequest(f.payload, target: target))
    var current = true
    projection.resolveCodexReplayOwner = { source, endpoint, identity, destination in
      guard current, source == f.record.binding.sourceIdentity, endpoint.id == contact.id,
            identity == f.record.binding.identity, destination.routeId == target.routeId else { return nil }
      return .init(message: original, codexReplay: f.record)
    }
    let request = try projection.outgoingRequest(f.payload, target: target)
    XCTAssertEqual(request.sourceMessageID, f.record.binding.sourceIdentity)
    XCTAssertEqual(request.messageID, f.record.binding.sourceIdentity)
    var wrong = f.payload
    wrong["content"] = "Changed queued request"
    XCTAssertThrowsError(try projection.outgoingRequest(wrong, target: target))
    let event = MqttDeliveryCompletions.Event(identity: request.identity, messageID: request.messageID,
      wireHash: String(repeating: "a", count: 64), traffic: request.traffic.rawValue, requestHash: nil,
      sourceMessageID: request.sourceMessageID, contactID: contact.id, attachmentTransferID: "", receivedAt: 3_000, consumedAt: nil)
    try projection.projectCompletion(event, target: target)
    XCTAssertEqual(store.persistedMessage(id: original.id, contactId: original.contactId)?.deliveryStatus, .delivered)
    current = false
    XCTAssertFalse(projection.isCurrentSendOwner(contactID: contact.id, source: request.sourceMessageID, target: target))
    XCTAssertThrowsError(try projection.outgoingRequest(f.payload, target: target))
  }
}
