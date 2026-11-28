import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIDesktopDisconnectTests: XCTestCase {
  private func pairing(_ id: String, fingerprint: String) -> PairingQRCode {
    PairingQRCode(desktopId: id, desktopName: "Same computer name", desktopFingerprint: fingerprint,
      pairingTopic: GalaxySSILinkProtocol.pairingTopic(secret: Data(repeating: 1, count: 32).base64URLEncodedString()),
      pairingToken: String(repeating: "t", count: 43), pairingSecret: Data(repeating: 1, count: 32),
      access: PairingAccess(profile: GalaxySSILinkProtocol.accessDesktopExecutor, scopes: [GalaxySSILinkProtocol.scopeDesktopExecutor]),
      controlAuthorizationToken: "control-token", raw: [:])
  }
  private func withStore(_ body: (GalaxySSIStore, UserDefaults, InMemorySecretStore) throws -> Void) throws {
    let suite = "DesktopDisconnectTests-\(UUID().uuidString)", secrets = InMemorySecretStore()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(GalaxySSIStore(defaults: defaults, secrets: secrets), defaults, secrets)
  }
  private func contact(_ id: String, desktop: String) -> GalaxySSIContact {
    var value = GalaxySSIContact.hermes()
    value.id = id; value.galaxySSIId = id; value.desktopId = desktop
    value.type = "agent"; value.agentKind = "codex"; value.agentId = "codex"
    value.trustState = .verified; value.deliveryMode = .pcConnector
    value.displayName = "Same Agent name"
    return value
  }
  private func install(_ value: GalaxySSIContact, store: GalaxySSIStore) throws -> GalaxySSIContact {
    let request = store.addFriendRequest(GalaxySSIFriendRequest(id: "fixture-" + value.id,
      galaxySSIId: value.galaxySSIId, name: value.displayName, type: value.type,
      identityPublicKey: "", identityFingerprint: value.identityFingerprint, mqttTopic: "", mqttInboxTopic: "",
      agentKind: value.agentKind, desktopId: value.desktopId, desktopName: value.desktopName))
    XCTAssertTrue(store.approveFriendRequest(id: request.id))
    return try XCTUnwrap(store.contact(id: value.id))
  }
  func testConfirmationBindsExactDesktopAndFullFingerprintNotDisplayName() throws {
    try withStore { store, _, _ in
      _ = try store.addServerLink(from: pairing("desktop-a", fingerprint: String(repeating: "a", count: 64)))
      _ = try store.addServerLink(from: pairing("desktop-b", fingerprint: String(repeating: "b", count: 64)))
      store.markServerPaired(desktopId: "desktop-a"); store.markServerPaired(desktopId: "desktop-b")
      let policy = GalaxySSIPairingLifecycle.self
      XCTAssertNil(policy.disconnectTarget(desktopId: "desktop-a", fingerprint: "", links: store.serverLinks))
      XCTAssertNil(policy.disconnectTarget(desktopId: "desktop-a", fingerprint: String(repeating: "b", count: 64), links: store.serverLinks))
      XCTAssertNil(policy.disconnectTarget(desktopId: "Same computer name", fingerprint: String(repeating: "a", count: 64), links: store.serverLinks))
      let selected = try XCTUnwrap(policy.disconnectTarget(desktopId: "desktop-a", fingerprint: String(repeating: "A", count: 64), links: store.serverLinks))
      XCTAssertEqual(selected.desktopId, "desktop-a")
      XCTAssertNil(policy.disconnectTarget(desktopId: "desktop-a", fingerprint: selected.desktopFingerprint, links: store.serverLinks + [selected]))
      store.removeServer(desktopId: "desktop-a")
      XCTAssertNil(policy.disconnectTarget(desktopId: selected.desktopId, fingerprint: selected.desktopFingerprint, links: store.serverLinks))
    }
  }
  func testDisconnectRetainsExactHistoryAndOtherDesktopAcrossRestartAndRepeatedCleanup() throws {
    try withStore { store, defaults, secrets in
      let a = try install(contact("desktop-a:codex", desktop: "desktop-a"), store: store)
      let b = try install(contact("desktop-b:codex", desktop: "desktop-b"), store: store)
      let first = store.appendIncoming("Keep A", from: a.id, remoteMessageId: "keep-a")
      let second = store.appendIncoming("Keep B", from: b.id, remoteMessageId: "keep-b")
      let removed = store.removeDesktopPairing(desktopId: "desktop-a", deleteMessages: false, preserveHistory: true)
      XCTAssertTrue(removed.contains(a.id)); XCTAssertFalse(removed.contains(b.id))
      let archived = try XCTUnwrap(store.contact(id: a.id))
      XCTAssertTrue(archived.isDesktopHistoryOnly); XCTAssertTrue(archived.deleted); XCTAssertFalse(archived.isCommunicable)
      XCTAssertFalse(store.visibleContacts.contains { $0.id == a.id }); XCTAssertEqual(store.contact(id: b.id), b)
      XCTAssertFalse(ScannedAgentConversationPolicy.opensAgentConversation(archived))
      XCTAssertNotNil(GalaxySSIConversationHubContactHistoryPolicy.visibleSummary(archived, summary: store.conversationSummary(for:)))
      _ = store.removeDesktopPairing(desktopId: "desktop-a")
      XCTAssertNotNil(store.persistedMessage(id: first.id, contactId: a.id))
      let reopened = GalaxySSIStore(defaults: defaults, secrets: secrets)
      XCTAssertTrue(reopened.contact(id: a.id)?.isDesktopHistoryOnly == true)
      XCTAssertNotNil(reopened.persistedMessage(id: first.id, contactId: a.id))
      XCTAssertNotNil(reopened.persistedMessage(id: second.id, contactId: b.id))
      let summaries = GalaxySSIConversationHubModels.contactSummaries(contacts: reopened.conversationHistoryContacts,
        summary: reopened.conversationSummary(for:), isPinned: { _ in false })
      let archivedRows = GalaxySSIConversationHubModels.unifiedConversations(agents: [], contacts: summaries, query: "", archived: true)
      XCTAssertEqual(archivedRows.recent.map(\.id), [a.id]); XCTAssertEqual(archivedRows.recent.first?.unreadCount, 0)
      let activeRows = GalaxySSIConversationHubModels.unifiedConversations(agents: [], contacts: summaries, query: "", archived: false)
      XCTAssertFalse((activeRows.pinned + activeRows.recent).contains { $0.id == a.id })
      var ordinaryDeleted = b; ordinaryDeleted.deleted = true
      XCTAssertNil(GalaxySSIConversationHubContactHistoryPolicy.visibleSummary(ordinaryDeleted, summary: reopened.conversationSummary(for:)))
    }
  }
  func testStaleDesktopDeviceMetadataCannotReactivateHistoryWithoutPairing() throws {
    try withStore { store, _, _ in
      let qr = pairing("desktop-a", fingerprint: String(repeating: "a", count: 64))
      _ = try store.addServerLink(from: qr); store.markServerPaired(desktopId: qr.desktopId)
      let old = try XCTUnwrap(store.serverLinks.first { $0.desktopId == qr.desktopId })
      let payload: [String: Any] = ["desktop_id": qr.desktopId, "desktop_fingerprint": qr.desktopFingerprint]
      XCTAssertTrue(store.updatePairedDesktopDevice(from: payload, link: old))
      _ = store.removeDesktopPairing(desktopId: qr.desktopId, deleteMessages: false, preserveHistory: true)
      XCTAssertFalse(store.updatePairedDesktopDevice(from: payload, link: old))
      XCTAssertTrue(store.contact(id: qr.desktopId)?.isDesktopHistoryOnly == true)
      _ = try store.addServerLink(from: qr)
      XCTAssertFalse(store.updatePairedDesktopDevice(from: payload, link: old))
      store.markServerPaired(desktopId: qr.desktopId)
      let current = try XCTUnwrap(store.serverLinks.first { $0.desktopId == qr.desktopId })
      XCTAssertTrue(store.updatePairedDesktopDevice(from: payload, link: current))
      XCTAssertFalse(store.contact(id: qr.desktopId)?.isDesktopHistoryOnly == true)
      XCTAssertTrue(store.contact(id: qr.desktopId)?.isCommunicable == true)
    }
  }
  func testContactMarkerRoundTripsAndOlderContactsDecodeWithoutIt() throws {
    var value = contact("desktop-a:codex", desktop: "desktop-a"); value.desktop_disconnected = true
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(GalaxySSIContact.self, from: data), value)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "desktop_disconnected")
    XCTAssertFalse(try JSONDecoder().decode(GalaxySSIContact.self, from: JSONSerialization.data(withJSONObject: object)).isDesktopHistoryOnly)
  }
  func testDefaultRevocationPreservesLocalHistoryAndMatchingIdentityRestoresIt() throws {
    try withStore { store, defaults, secrets in
      let qr = pairing("desktop-a", fingerprint: String(repeating: "a", count: 64))
      _ = try store.addServerLink(from: qr); store.markServerPaired(desktopId: qr.desktopId)
      var agent = contact("desktop-a:codex", desktop: qr.desktopId); agent.identityFingerprint = qr.desktopFingerprint
      agent = try install(agent, store: store)
      let message = store.appendIncoming("Keep across revocation", from: agent.id, remoteMessageId: "revocation-preserved")
      _ = store.removeDesktopPairing(desktopId: qr.desktopId)
      let reopened = GalaxySSIStore(defaults: defaults, secrets: secrets)
      XCTAssertTrue(reopened.contact(id: agent.id)?.isDesktopHistoryOnly == true)
      XCTAssertNotNil(reopened.persistedMessage(id: message.id, contactId: agent.id))
      XCTAssertFalse(reopened.serverLinks.contains { $0.desktopId == qr.desktopId })
      _ = try reopened.addServerLink(from: qr)
      XCTAssertTrue(reopened.contact(id: agent.id)?.isDesktopHistoryOnly == true)
      reopened.markServerPaired(desktopId: qr.desktopId)
      XCTAssertFalse(reopened.contact(id: agent.id)?.isDesktopHistoryOnly == true)
      XCTAssertTrue(reopened.contact(id: agent.id)?.isCommunicable == true)
      XCTAssertNotNil(reopened.persistedMessage(id: message.id, contactId: agent.id))
    }
  }
  func testDifferentFingerprintCannotRestoreArchivedDeviceOrAgentWithSameIdOrName() throws {
    try withStore { store, _, _ in
      let oldQR = pairing("desktop-a", fingerprint: String(repeating: "a", count: 64))
      _ = try store.addServerLink(from: oldQR); store.markServerPaired(desktopId: oldQR.desktopId)
      let oldLink = try XCTUnwrap(store.serverLinks.first)
      XCTAssertTrue(store.updatePairedDesktopDevice(from: ["desktop_id": oldQR.desktopId], link: oldLink))
      var agent = contact("desktop-a:codex", desktop: oldQR.desktopId); agent.identityFingerprint = oldQR.desktopFingerprint
      agent = try install(agent, store: store); _ = store.removeDesktopPairing(desktopId: oldQR.desktopId)
      let otherQR = pairing(oldQR.desktopId, fingerprint: String(repeating: "b", count: 64))
      _ = try store.addServerLink(from: otherQR); store.markServerPaired(desktopId: otherQR.desktopId)
      let current = try XCTUnwrap(store.serverLinks.first)
      XCTAssertFalse(store.updatePairedDesktopDevice(from: ["desktop_id": otherQR.desktopId,
        "desktop_fingerprint": otherQR.desktopFingerprint], link: current))
      _ = store.updateDesktopAgentContacts(from: ["desktop_id": otherQR.desktopId,
        "desktop_fingerprint": otherQR.desktopFingerprint,
        "agents": [["id": agent.id, "agent_id": "codex", "kind": "local-cli", "name": agent.displayName]]], link: current)
      XCTAssertTrue(store.contact(id: agent.id)?.isDesktopHistoryOnly == true)
      XCTAssertTrue(store.contact(id: otherQR.desktopId)?.isDesktopHistoryOnly == true)
      XCTAssertEqual(store.contact(id: agent.id)?.identityFingerprint, oldQR.desktopFingerprint)
    }
  }
  func testArchivedRestorationRequiresFullSavedFingerprintNotBlankOrAbbreviatedIdentity() {
    var archived = contact("desktop-a:codex", desktop: "desktop-a"); archived.desktop_disconnected = true
    let full = String(repeating: "a", count: 64)
    for identity in ["", "aaaa", String(repeating: "g", count: 64)] {
      archived.identityFingerprint = identity
      XCTAssertFalse(GalaxySSIPairingLifecycle.canRestoreHistory(archived, pairedFingerprint: full))
    }
    archived.identityFingerprint = full
    XCTAssertFalse(GalaxySSIPairingLifecycle.canRestoreHistory(archived, pairedFingerprint: nil))
    XCTAssertFalse(GalaxySSIPairingLifecycle.canRestoreHistory(archived, pairedFingerprint: String(repeating: "b", count: 64)))
    XCTAssertTrue(GalaxySSIPairingLifecycle.canRestoreHistory(archived, pairedFingerprint: full.uppercased()))
  }
  func testConfirmedLocalDeletionKeepsPairingOtherChatsAndReplayTombstonesAcrossRestart() throws {
    try withStore { store, defaults, secrets in
      let qr = pairing("desktop-a", fingerprint: String(repeating: "a", count: 64))
      _ = try store.addServerLink(from: qr); store.markServerPaired(desktopId: qr.desktopId)
      let link = try XCTUnwrap(store.serverLinks.first)
      var agent = contact("desktop-a:codex", desktop: qr.desktopId); agent.identityFingerprint = qr.desktopFingerprint
      let other = try install(contact("desktop-b:codex", desktop: "desktop-b"), store: store)
      agent = try install(agent, store: store)
      let removed = store.appendIncoming("Delete only here", from: agent.id, remoteMessageId: "local-delete-a")
      let retained = store.appendIncoming("Keep other computer", from: other.id, remoteMessageId: "local-keep-b")
      let personal = store.appendIncoming("Keep phone-owned Agent", from: "hermes", remoteMessageId: "local-keep-hermes")
      XCTAssertFalse(store.clearPairedDesktopLocalHistory(link, owner: "wrong owner"))
      XCTAssertNotNil(store.persistedMessage(id: removed.id, contactId: agent.id))
      XCTAssertTrue(store.clearPairedDesktopLocalHistory(link, owner: store.profile.identityFingerprint))
      XCTAssertEqual(store.serverLinks.first, link); XCTAssertEqual(store.contact(id: agent.id), agent)
      XCTAssertNil(store.persistedMessage(id: removed.id, contactId: agent.id))
      let reopened = GalaxySSIStore(defaults: defaults, secrets: secrets)
      XCTAssertEqual(reopened.serverLinks.first, link)
      XCTAssertNil(reopened.persistedMessage(id: removed.id, contactId: agent.id))
      XCTAssertNotNil(reopened.persistedMessage(id: retained.id, contactId: other.id))
      XCTAssertNotNil(reopened.persistedMessage(id: personal.id, contactId: "hermes"))
      let replay = reopened.appendIncoming("Delete only here", from: agent.id, remoteMessageId: "local-delete-a")
      XCTAssertNil(reopened.persistedMessage(id: replay.id, contactId: agent.id))
      _ = reopened.removeDesktopPairing(desktopId: qr.desktopId)
      XCTAssertFalse(reopened.clearPairedDesktopLocalHistory(link, owner: reopened.profile.identityFingerprint))
    }
  }
  func testLocalDeletionRejectsAReplacedRouteAndDoesNotDeleteAnotherIdentityArchive() throws {
    try withStore { store, _, _ in
      let first = pairing("desktop-a", fingerprint: String(repeating: "a", count: 64))
      _ = try store.addServerLink(from: first); store.markServerPaired(desktopId: first.desktopId)
      let original = try XCTUnwrap(store.serverLinks.first)
      var agent = contact("desktop-a:codex", desktop: first.desktopId); agent.identityFingerprint = first.desktopFingerprint
      agent = try install(agent, store: store)
      let retained = store.appendIncoming("Old identity history", from: agent.id, remoteMessageId: "old-identity-history")
      _ = store.removeDesktopPairing(desktopId: first.desktopId)
      let next = pairing(first.desktopId, fingerprint: String(repeating: "b", count: 64))
      _ = try store.addServerLink(from: next); store.markServerPaired(desktopId: next.desktopId)
      XCTAssertFalse(store.clearPairedDesktopLocalHistory(original, owner: store.profile.identityFingerprint))
      let current = try XCTUnwrap(store.serverLinks.first)
      XCTAssertTrue(store.clearPairedDesktopLocalHistory(current, owner: store.profile.identityFingerprint))
      XCTAssertNotNil(store.persistedMessage(id: retained.id, contactId: agent.id))
    }
  }
  func testDatabaseLocalDeletionIsScopedAndRejectsInvalidTargetsBeforeAnyMutation() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("history.sqlite"), secrets = InMemorySecretStore()
    let database = GalaxySSIChatHistoryDatabase(fileURL: file, secrets: secrets)
    let a = ChatMessage(contactId: "desktop-a:codex", content: "Remove", isMine: false,
      deliveryStatus: .delivered, remoteMessageId: "remote-a")
    let b = ChatMessage(contactId: "desktop-b:codex", content: "Keep", isMine: false,
      deliveryStatus: .delivered, remoteMessageId: "remote-b")
    XCTAssertTrue(database.upsert(a)); XCTAssertTrue(database.upsert(b))
    XCTAssertThrowsError(try database.deleteContactHistories([a.contactId, ""]))
    XCTAssertEqual(database.message(id: a.id), a); XCTAssertEqual(database.message(id: b.id), b)
    try database.deleteContactHistories([a.contactId])
    XCTAssertNil(database.message(id: a.id)); XCTAssertEqual(database.message(id: b.id), b)
    let reopened = GalaxySSIChatHistoryDatabase(fileURL: file, secrets: secrets)
    var replay = a; replay.id = UUID()
    XCTAssertFalse(reopened.upsert(replay)); XCTAssertEqual(reopened.message(id: b.id), b)
  }
}
