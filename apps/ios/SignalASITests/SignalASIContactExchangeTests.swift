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
      routes: SignalASILinkRoutes(serverRouteId: "abcdefghijklmnopqrstuv", clientRouteId: "zyxwvutsrqponmlkjihgfe"),
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
    XCTAssertEqual(object["mqtt_inbox_topic"] as? String, "signalasichat/v1/abcdefghijklmnopqrstuv/zyxwvutsrqponmlkjihgfe/down")
    XCTAssertEqual(object["signal_bundle_ref"] as? String, "mqtt:signalasichat/v1/abcdefghijklmnopqrstuv/zyxwvutsrqponmlkjihgfe/down:ios_test")
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

  private func pairingQR(createdAt: Date) -> String {
    let routeId = "abcdefghijklmnopqrstuv"
    let object: [String: Any] = [
      "type": "signalasi_verify",
      "protocol": SignalASILinkProtocol.name,
      "version": SignalASILinkProtocol.version,
      "role": "server",
      "desktop_id": "desktop-test",
      "desktop_name": "Test Mac",
      "identity_key_sha256": String(repeating: "a", count: 64),
      "server_route_id": routeId,
      "pairing_topic": "signalasichat/v1/\(routeId)/pair",
      "pairing_token": String(repeating: "t", count: 32),
      "pairing_secret": Data(repeating: 7, count: 32).base64URLEncodedString(),
      "pairing_access": [
        "contract_version": SignalASILinkProtocol.accessContract,
        "version": 1,
        "profile": SignalASILinkProtocol.accessRestricted,
        "scopes": [
          SignalASILinkProtocol.scopeAgentChat,
          SignalASILinkProtocol.scopeExplicitAttachments,
          SignalASILinkProtocol.scopeTaskWorkspace
        ]
      ],
      "created_at": Int64(createdAt.timeIntervalSince1970 * 1000)
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
  }

  private func jsonObject(_ text: String) throws -> [String: Any] {
    let data = try XCTUnwrap(text.data(using: .utf8))
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
}
