import XCTest
@testable import GalaxySSI

final class AgentSupervisedAnswerPreviewTests: XCTestCase {
  private func scope() -> AgentSupervisedAnswerPreview.Scope {
    .init(token: UUID(), profile: "profile", owner: AgentPairedPhonePlannerRoute.ownerPrefix + "request",
      source: 41, route: .init(contactId: "desktop:codex", desktopId: "desktop", clientRouteId: "route",
        modelId: "selected", reasoningEffort: .automatic),
      identity: .init(clientRouteId: "route", conversationId: "conversation", taskId: "remote-task", turnId: "turn"), generation: 1)
  }

  private func payload(sequence: Int64 = 1, text: String = "First paragraph of the answer.") -> [String: Any] {
    ["type": "agent_task_event", "agent_id": "codex", "contact_id": "desktop:codex", "desktop_id": "desktop",
      "client_route_id": "route", "conversation_id": "conversation", "task_id": "remote-task", "turn_id": "turn",
      "source_message_id": "41", "execution_generation": 1, "task_status": "running",
      "partial_result": ["format": AgentSupervisedAnswerPreview.format, "user_visible": true,
        "sequence": sequence, "text": text]]
  }

  func testExplicitUserVisibleRunningCodexPreviewPreservesExactScopeAndText() throws {
    let owner = scope(), preview = try XCTUnwrap(AgentSupervisedAnswerPreview(payload: payload(), scope: owner))
    XCTAssertEqual(preview.scope, owner)
    XCTAssertEqual(preview.id, owner.owner)
    XCTAssertEqual(preview.sequence, 1)
    XCTAssertEqual(preview.text, "First paragraph of the answer.")
    var numeric = payload()
    numeric["source_message_id"] = 41
    XCTAssertNotNil(AgentSupervisedAnswerPreview(payload: numeric, scope: owner))
  }

  func testEveryEnvelopeIdentityMustMatchOriginalInvocation() {
    let owner = scope()
    for key in ["type", "agent_id", "contact_id", "desktop_id", "client_route_id", "conversation_id",
                "task_id", "turn_id", "source_message_id", "execution_generation", "task_status"] {
      var changed = payload()
      changed[key] = "other"
      XCTAssertNil(AgentSupervisedAnswerPreview(payload: changed, scope: owner), key)
    }
  }

  func testMarkerVisibilityAndSequenceAreRequiredAndStrictlyTyped() {
    for key in ["format", "user_visible", "sequence"] {
      var changed = payload(), partial = changed["partial_result"] as! [String: Any]
      partial.removeValue(forKey: key)
      changed["partial_result"] = partial
      XCTAssertNil(AgentSupervisedAnswerPreview(payload: changed, scope: scope()), key)
    }
    for value in [false, 1, "true"] as [Any] {
      var changed = payload(), partial = changed["partial_result"] as! [String: Any]
      partial["user_visible"] = value
      changed["partial_result"] = partial
      XCTAssertNil(AgentSupervisedAnswerPreview(payload: changed, scope: scope()))
    }
    XCTAssertNil(AgentSupervisedAnswerPreview(payload: payload(sequence: -1), scope: scope()))
  }

  func testControlPlansToolMarkupAndPrivateRecoveryMarkersAreNeverPreviewed() {
    for text in ["{\"execution_location\":\"phone\",\"actions\":[]}",
      "{\"disposition\":\"respond\",\"final_response\":\"answer\"}",
      "```json\n{\"action\":{\"kind\":\"CALL_NATIVE_TOOL\"}}", "<tool_call>private arguments</tool_call>",
      "GALAXYSSI_RECOVERY_ACTION_V1", "   "] {
      XCTAssertNil(AgentSupervisedAnswerPreview(payload: payload(text: text), scope: scope()), text)
    }
  }

  func testTextIsBoundedWithoutInventingRichOutputOrCompletion() throws {
    let preview = try XCTUnwrap(AgentSupervisedAnswerPreview(payload: payload(text: String(repeating: "x", count: 64_001)), scope: scope()))
    XCTAssertEqual(preview.text.count, 64_000)
    XCTAssertFalse(AgentSupervisedAnswerPreview.claims(["type": "text", "partial_result": ["format": AgentSupervisedAnswerPreview.format]]))
    var terminal = payload()
    terminal["task_status"] = "completed"
    XCTAssertNil(AgentSupervisedAnswerPreview(payload: terminal, scope: scope()))
  }

  func testOnlyIncreasingSequenceForSameRequestTokenCanAdvance() throws {
    let owner = scope()
    let first = try XCTUnwrap(AgentSupervisedAnswerPreview(payload: payload(), scope: owner))
    XCTAssertTrue(first.advances(nil))
    XCTAssertFalse(first.advances(first))
    let next = try XCTUnwrap(AgentSupervisedAnswerPreview(payload: payload(sequence: 2), scope: owner))
    XCTAssertTrue(next.advances(first))
    XCTAssertFalse(first.advances(next))
    let different = try XCTUnwrap(AgentSupervisedAnswerPreview(payload: payload(sequence: 3), scope: scope()))
    XCTAssertFalse(different.advances(first))
  }

  func testSourceDoesNotAcceptAmbiguousNumbersBooleansOrForeignUUIDs() {
    for value in ["041", "+41", "0", "-1", "9007199254740992", true, UUID().uuidString] as [Any] {
      var changed = payload()
      changed["source_message_id"] = value
      XCTAssertNil(AgentSupervisedAnswerPreview(payload: changed, scope: scope()))
    }
  }
}

extension GalaxySSIStoreTests {
  @MainActor
  func testJournalMarkedNumericPreviewRoutesOnlyToEphemeralCallbackWithoutChatWrite() throws {
    let store = makeStore()
    let link = try store.addServerLink(from: makePairingQRCode())
    store.markServerPaired(desktopId: link.desktopId)
    let desktop = try XCTUnwrap(store.contacts.first { $0.isDesktopDeviceContact && $0.desktopId == link.desktopId })
    let contact = try XCTUnwrap(store.contact(id: "\(link.desktopId):codex"))
    let target = try XCTUnwrap(MqttPeerChatProjection(store: store, localFingerprint: link.routes.localFingerprint).destination(for: desktop))
    let session = store.createAgentSession(title: "Answer preview")
    let identity = AgentTaskIdentity(clientRouteId: target.routeId, conversationId: session.id, taskId: "remote-task", turnId: "turn")
    let identities = AgentTaskIdentityStore(defaults: store.defaults, storageKeyPrefix: "answer-preview-test")
    XCTAssertTrue(identities.register(contactId: contact.id, sourceMessageId: "41", identity: identity))
    let files = try ChunkFixture(), journal = try MqttSignalStateJournal(fileURL: files.url, secrets: files.secrets)
    let messageID = UUID().uuidString, business = try MqttBusinessIdentity(target.peer.binding)
    let payload: [String: Any] = ["type": "agent_task_event", "message_id": messageID, "agent_id": "codex",
      "contact_id": contact.id, "desktop_id": link.desktopId, "client_route_id": target.routeId,
      "conversation_id": session.id, "task_id": identity.taskId, "turn_id": identity.turnId,
      "source_message_id": "41", "execution_generation": 1, "task_status": "running",
      "partial_result": ["format": AgentSupervisedAnswerPreview.format, "user_visible": true,
        "sequence": 1, "text": "A temporary answer paragraph."]]
    let hash = MqttRouteProtocol.digest(Data(messageID.utf8))
    _ = try journal.inbox.accept(identity: business, messageID: messageID, payload: payload,
      ciphertextDigest: hash, wireHash: hash, receiptRequired: true)
    let item = try XCTUnwrap(journal.inbox.pending().first)
    var projection = MqttDesktopConnectorProjection(store: store, identities: identities, commitResponse: { _, _ in
      XCTFail("Preview must not become a connector result")
    })
    let before = store.messages(for: "hermes")
    try projection.project(item, payload: payload, target: target)
    var calls = 0
    projection.receiveAnswerPreview = { received, desktop, route in
      calls += 1
      XCTAssertEqual(received.string("source_message_id"), "41")
      XCTAssertEqual(desktop, link.desktopId)
      XCTAssertEqual(route, target.routeId)
    }
    try projection.project(item, payload: payload, target: target)
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(store.messages(for: "hermes"), before)
    var foreign = payload
    foreign["client_route_id"] = "foreign"
    XCTAssertThrowsError(try projection.project(item, payload: foreign, target: target))
    XCTAssertEqual(calls, 1)
  }
}
