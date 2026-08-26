import XCTest
@testable import SignalASI

@MainActor
final class SignalASIContactExchangeTests: XCTestCase {
  func testMyContactQRPayloadMatchesAndroidWireNames() throws {
    let profile = SignalASIProfile(
      signalASIId: "ios_test",
      name: "Alice",
      identityFingerprint: String(repeating: "a", count: 64),
      identityPublicKey: "public-key"
    )
    let link = ServerLink(
      desktopId: "desktop",
      desktopName: "Desktop",
      desktopFingerprint: String(repeating: "b", count: 64),
      signalName: "desktop",
      routes: SignalASILinkRoutes(
        clientRouteId: "zyxwvutsrqponmlkjihgfe",
        linkSecret: Data(repeating: 7, count: 32).base64URLEncodedString(),
        localFingerprint: String(repeating: "a", count: 64),
        remoteFingerprint: String(repeating: "b", count: 64)
      ),
      paired: true,
      accessProfile: SignalASILinkProtocol.accessRestricted,
      accessScopes: [SignalASILinkProtocol.scopeAgentChat],
      updatedAt: Date(timeIntervalSince1970: 1)
    )

    let text = try SignalASIContactExchange.makeContactQRText(
      profile: profile,
      serverLinks: [link],
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let object = try jsonObject(text)

    XCTAssertEqual(object["type"] as? String, "signalasi_contact")
    XCTAssertEqual(object["version"] as? Int, 1)
    XCTAssertEqual(object["signalasi_id"] as? String, "ios_test")
    XCTAssertEqual(object["identity_public_key"] as? String, "public-key")
    XCTAssertEqual(object["identity_fingerprint"] as? String, String(repeating: "a", count: 64))
    XCTAssertNil(object["mqtt_inbox_topic"])
    XCTAssertNil(object["signal_bundle_ref"])
  }

  func testImportContactQRAddsPendingFriendRequest() throws {
    let store = makeStore()

    let request = try store.importContactQRCodeAsFriendRequest(contactQR(name: "Bob"))

    XCTAssertEqual(request.name, "Bob")
    XCTAssertEqual(request.signalASIId, "signalasi:bob")
    XCTAssertEqual(request.status, .pending)
    XCTAssertEqual(store.pendingFriendRequests.count, 1)
    XCTAssertEqual(store.pendingFriendRequests.first?.identityFingerprint, String(repeating: "c", count: 64))
  }

  func testClassifyQRCodeDetectsDesktopPairing() throws {
    let now = Date()
    let result = try SignalASIContactExchange.classifyQRCode(pairingQR(createdAt: now), now: now)

    guard case .desktopPairing(let pairing) = result else {
      XCTFail("Expected desktop pairing QR")
      return
    }
    XCTAssertEqual(pairing.desktopId, "desktop-test")
    XCTAssertEqual(pairing.desktopName, "Test Mac")
  }

  func testClassifyQRCodeDetectsContactIdentity() throws {
    let result = try SignalASIContactExchange.classifyQRCode(contactQRWithoutType(name: "Device Agent"))

    guard case .contact(let request) = result else {
      XCTFail("Expected contact QR")
      return
    }
    XCTAssertEqual(request.name, "Device Agent")
    XCTAssertEqual(request.signalASIId, "signalasi:device-agent")
  }

  func testClassifyQRCodeDetectsSingleDesktopConnectorAgent() throws {
    let result = try SignalASIContactExchange.classifyQRCode(singleDesktopConnectorAgentQR())

    guard case .contact(let request) = result else {
      XCTFail("Expected single desktop connector Agent QR")
      return
    }
    XCTAssertEqual(request.signalASIId, "desktop-office:codex")
    XCTAssertEqual(request.name, "Codex Agent")
    XCTAssertEqual(request.type, "agent")
    XCTAssertEqual(request.agentKind, "local-cli")
    XCTAssertEqual(request.desktopId, "desktop-office")
    XCTAssertEqual(request.identityFingerprint, String(repeating: "e", count: 64))
  }

  func testClassifyQRCodeImportsNestedCapabilityManifestAgents() throws {
    let result = try SignalASIContactExchange.classifyQRCode(nestedCapabilityManifest(agentKey: "agents"))

    guard case .contacts(let requests) = result else {
      XCTFail("Expected connector Agent requests")
      return
    }
    XCTAssertEqual(requests.count, 2)
    XCTAssertEqual(requests.map(\.signalASIId), [
      "desktop-office:codex",
      "desktop-office:research"
    ])
    XCTAssertEqual(requests.first?.name, "Codex Agent · Office PC")
    XCTAssertEqual(requests.first?.type, "agent")
    XCTAssertEqual(requests.first?.agentKind, "local-cli")
    XCTAssertEqual(requests.first?.desktopId, "desktop-office")
    XCTAssertEqual(requests.first?.desktopName, "Office PC")
    XCTAssertEqual(requests.first?.identityFingerprint, String(repeating: "e", count: 64))
  }

  func testClassifyQRCodeImportsAndroidAvailableTargetsAgents() throws {
    let result = try SignalASIContactExchange.classifyQRCode(nestedCapabilityManifest(agentKey: "available_targets"))

    guard case .contacts(let requests) = result else {
      XCTFail("Expected Android-style available target Agent requests")
      return
    }
    XCTAssertEqual(requests.count, 2)
    XCTAssertEqual(requests.map(\.signalASIId), [
      "desktop-office:codex",
      "desktop-office:research"
    ])
  }

  func testStoreUpsertsNestedCapabilityManifestAgents() throws {
    let store = makeStore()
    let payload = try jsonObject(nestedCapabilityManifest(agentKey: "desktop_agents"))

    XCTAssertEqual(store.updateDesktopAgentContacts(from: payload), 2)

    let codex = try XCTUnwrap(store.contact(id: "desktop-office:codex"))
    XCTAssertEqual(codex.displayName, "Codex Agent · Office PC")
    XCTAssertEqual(codex.type, "agent")
    XCTAssertEqual(codex.agentKind, "local-cli")
    XCTAssertEqual(codex.desktopId, "desktop-office")
    XCTAssertEqual(codex.desktopName, "Office PC")
    XCTAssertEqual(codex.identityFingerprint, String(repeating: "e", count: 64))
    XCTAssertEqual(codex.trustState, .unverified)

    let research = try XCTUnwrap(store.contact(id: "desktop-office:research"))
    XCTAssertEqual(research.setupDetail, "Ready for deep work")
  }

  func testStoreImportsSingleDesktopAgentQRUsingPairedLinkIdentity() throws {
    let store = makeStore()
    let pairing = try SignalASILinkProtocol.decodePairingQRCode(from: pairingQR(createdAt: Date()))
    let link = try store.addServerLink(from: pairing, rotateClientRoute: false)
    store.markServerPaired(desktopId: link.desktopId, access: pairing.access)

    XCTAssertEqual(try store.importDesktopAgentQRCodeAsContacts(singleDesktopAgentQRWithoutIdentity()), 1)

    let codex = try XCTUnwrap(store.contact(id: "desktop-test:codex"))
    XCTAssertEqual(codex.displayName, "Codex Agent · Test Mac")
    XCTAssertEqual(codex.type, "agent")
    XCTAssertEqual(codex.agentKind, "local-cli")
    XCTAssertEqual(codex.desktopId, "desktop-test")
    XCTAssertEqual(codex.identityFingerprint, String(repeating: "a", count: 64))
    XCTAssertEqual(codex.trustState, .verified)
  }

  func testImportContactQRReplacesExistingPendingRequest() throws {
    let store = makeStore()

    _ = try store.importContactQRCodeAsFriendRequest(contactQR(name: "Bob"))
    _ = try store.importContactQRCodeAsFriendRequest(contactQR(name: "Bobby"))

    XCTAssertEqual(store.pendingFriendRequests.count, 1)
    XCTAssertEqual(store.pendingFriendRequests.first?.name, "Bobby")
  }

  func testApprovingFriendRequestCreatesVerifiedContact() throws {
    let store = makeStore()
    let request = try store.importContactQRCodeAsFriendRequest(contactQR(name: "Bob"))

    XCTAssertTrue(store.approveFriendRequest(id: request.id))

    let contact = try XCTUnwrap(store.contact(id: "signalasi:bob"))
    XCTAssertEqual(contact.trustState, .verified)
    XCTAssertEqual(contact.displayName, "Bob")
    XCTAssertEqual(contact.identityFingerprint, String(repeating: "c", count: 64))
    XCTAssertEqual(contact.mqttInboxTopic, "signalasichat/v1/friend/inbox")
    XCTAssertEqual(contact.signalBundleRef, "mqtt:signalasichat/v1/friend/inbox:signalasi:bob")
    XCTAssertEqual(store.pendingFriendRequests.count, 0)
    XCTAssertEqual(store.friendRequest(id: request.id)?.status, .approved)
  }

  func testRejectingFriendRequestKeepsItOutOfPending() throws {
    let store = makeStore()
    let request = try store.importContactQRCodeAsFriendRequest(contactQR(name: "Bob"))

    XCTAssertTrue(store.rejectFriendRequest(id: request.id))

    XCTAssertEqual(store.pendingFriendRequests.count, 0)
    XCTAssertEqual(store.friendRequest(id: request.id)?.status, .rejected)
  }

  func testBackupPayloadIncludesFriendRequests() throws {
    let store = makeStore()
    _ = try store.importContactQRCodeAsFriendRequest(contactQR(name: "Bob"))

    let payload = store.exportBackupPayload(includeContacts: true, includeMessages: false)

    XCTAssertEqual(payload.friendRequests.count, 1)
    XCTAssertEqual(payload.friendRequests.first?.signalASIId, "signalasi:bob")
  }

  func testRejectsInvalidContactQR() {
    XCTAssertThrowsError(try SignalASIContactExchange.importContactQRCode("{\"type\":\"unknown\"}"))
  }

  private func makeStore() -> SignalASIStore {
    let suite = "SignalASIContactExchangeTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return SignalASIStore(defaults: defaults, secrets: InMemorySecretStore())
  }

  private func contactQR(name: String) -> String {
    let object: [String: Any] = [
      "type": "signalasi_contact",
      "version": 1,
      "name": name,
      "signalasi_id": "signalasi:bob",
      "identity_public_key": "public-key",
      "identity_fingerprint": String(repeating: "c", count: 64),
      "mqtt_topic": "signalasichat/v1/friend/inbox",
      "mqtt_inbox_topic": "signalasichat/v1/friend/inbox",
      "signal_bundle_ref": "mqtt:signalasichat/v1/friend/inbox:signalasi:bob",
      "created_at": Int64(Date().timeIntervalSince1970 * 1000)
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
  }

  private func contactQRWithoutType(name: String) -> String {
    let object: [String: Any] = [
      "name": name,
      "signalasi_id": "signalasi:device-agent",
      "identity_public_key": "public-key",
      "identity_fingerprint": String(repeating: "d", count: 64),
      "mqtt_topic": "signalasichat/v1/device/inbox",
      "mqtt_inbox_topic": "signalasichat/v1/device/inbox"
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
  }

  private func singleDesktopConnectorAgentQR() -> String {
    let object: [String: Any] = [
      "id": "codex",
      "name": "Codex Agent",
      "kind": "local-cli",
      "desktop_id": "desktop-office",
      "desktop_name": "Office PC",
      "desktop_fingerprint": String(repeating: "e", count: 64),
      "mqtt_topic": "signalasichat/v1/desktop/up"
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
  }

  private func singleDesktopAgentQRWithoutIdentity() -> String {
    let object: [String: Any] = [
      "type": "agent",
      "id": "codex",
      "name": "Codex Agent",
      "kind": "local-cli",
      "desktop_id": "desktop-test",
      "status": "ready",
      "detail": "Ready for live coding"
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
  }

  private func pairingQR(createdAt: Date) -> String {
    let object: [String: Any] = [
      "t": "o2",
      "n": "Test Mac",
      "h": String(repeating: "a", count: 64),
      "k": Data(repeating: 1, count: 32).base64URLEncodedString(),
      "x": String(repeating: "t", count: 43),
      "e": Data(repeating: 7, count: 32).base64URLEncodedString(),
      "a": 0,
      "c": Int64(createdAt.timeIntervalSince1970)
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
  }

  private func nestedCapabilityManifest(agentKey: String) -> String {
    let object: [String: Any] = [
      "type": "capability_manifest",
      "server": [
        "id": "desktop-office",
        "name": "Office PC",
        "identity_key_sha256": String(repeating: "e", count: 64)
      ],
      agentKey: [
        [
          "id": "codex",
          "name": "Codex Agent",
          "kind": "local-cli",
          "status": "ready",
          "detail": "Ready for live coding"
        ],
        [
          "mobile_contact_id": "research",
          "name": "Research Agent",
          "agent_kind": "custom-cli",
          "status": "ready",
          "detail": "Ready for deep work"
        ],
        [
          "id": "cloud-model",
          "name": "Cloud Model",
          "kind": "cloud-model"
        ]
      ]
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
  }

  private func jsonObject(_ text: String) throws -> [String: Any] {
    let data = try XCTUnwrap(text.data(using: .utf8))
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
}
