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
      let a = contact("desktop-a:codex", desktop: "desktop-a"), b = contact("desktop-b:codex", desktop: "desktop-b")
      store.upsert(a); store.upsert(b)
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
}
