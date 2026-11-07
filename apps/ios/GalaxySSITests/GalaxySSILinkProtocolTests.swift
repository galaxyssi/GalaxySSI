import XCTest
@testable import GalaxySSI

final class GalaxySSILinkProtocolTests: XCTestCase {
  func testContactReminderEnvelopeUsesAndroidFieldsAndRejectsInvalidLifetimes() throws {
    let envelope = GalaxySSIContactReminderEnvelope(id: UUID().uuidString.lowercased(),
      createdAt: 50_000, expiresAt: 170_000, action: .request)
    var payload = envelope.payload(messageId: "message", recipient: "paired-target", sender: "sender", now: 50_000)
    XCTAssertEqual(payload["type"] as? String, "peer_attention")
    XCTAssertEqual(payload["contact_id"] as? String, "paired-target")
    XCTAssertEqual(GalaxySSIContactReminderEnvelope(payload, now: 50_001), envelope)
    XCTAssertNil(GalaxySSIContactReminderEnvelope(payload, now: 170_000))
    XCTAssertNil(GalaxySSIContactReminderEnvelope(payload, now: 19_999))
    payload["expires_at"] = 170_001
    XCTAssertNil(GalaxySSIContactReminderEnvelope(payload, now: 50_001))
    payload["expires_at"] = true
    XCTAssertNil(GalaxySSIContactReminderEnvelope(payload, now: 50_001))
  }

  @MainActor
  func testContactReminderReplayDoesNotAlertTwiceAndCancellationSurvivesReopen() throws {
    let suite = "contact-reminders-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let secrets = InMemorySecretStore()
    let store = GalaxySSIContactReminderStore(defaults: defaults, secrets: secrets, owner: "local")
    let id = UUID().uuidString
    let request = GalaxySSIContactReminderEnvelope(id: id, createdAt: 5_000, expiresAt: 125_000, action: .request)
    let first = try XCTUnwrap(store.receive(request, authenticatedPeer: "peer-a", enabled: true, quiet: false, now: 5_001))
    XCTAssertTrue(first.shouldAlert)
    XCTAssertEqual(first.record.pendingAction, .received)

    let reopened = GalaxySSIContactReminderStore(defaults: defaults, secrets: secrets, owner: "local")
    let repeated = try XCTUnwrap(reopened.receive(request, authenticatedPeer: "peer-a", enabled: true, quiet: false, now: 6_000))
    XCTAssertFalse(repeated.shouldAlert)
    XCTAssertEqual(repeated.record.historyID, first.record.historyID)
    XCTAssertNil(try reopened.receive(request, authenticatedPeer: "peer-b", enabled: true, quiet: false, now: 6_000))
    let foreign = GalaxySSIContactReminderStore(defaults: defaults, secrets: secrets, owner: "other-account")
    XCTAssertTrue(try foreign.records(now: 6_000).isEmpty)

    let cancelled = GalaxySSIContactReminderEnvelope(id: UUID().uuidString, createdAt: 5_000,
      expiresAt: 125_000, action: .cancelled)
    XCTAssertFalse(try XCTUnwrap(reopened.receive(cancelled, authenticatedPeer: "peer-a",
      enabled: true, quiet: false, now: 6_000)).shouldAlert)
    let late = GalaxySSIContactReminderEnvelope(id: cancelled.id, createdAt: 5_000, expiresAt: 125_000, action: .request)
    XCTAssertNil(try reopened.receive(late, authenticatedPeer: "peer-a", enabled: true, quiet: false, now: 6_001))
    XCTAssertEqual(try reopened.records(now: 125_000).first(where: { $0.id == id })?.status, .expired)
    let unavailable = GalaxySSIContactReminderStore(defaults: defaults, secrets: InMemorySecretStore(), owner: "local")
    XCTAssertThrowsError(try unavailable.records(now: 6_000))
  }

  @MainActor
  func testContactReminderStaleReceiptCannotClearPendingCancellation() throws {
    let suite = "contact-reminder-cancel-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = GalaxySSIContactReminderStore(defaults: defaults, secrets: InMemorySecretStore(), owner: "local")
    let record = try store.create(peerID: "peer", now: 5_000)
    XCTAssertEqual(try store.act(id: record.id, action: .cancelled, now: 5_001)?.status, .cancelled)
    let receipt = try XCTUnwrap(store.receive(record.envelope(.received), authenticatedPeer: "peer",
      enabled: true, quiet: false, now: 5_002))
    XCTAssertEqual(receipt.record.status, .cancelled)
    XCTAssertEqual(receipt.record.pendingAction, .cancelled)
    try store.markQueued(id: record.id, action: .request, now: 5_003)
    XCTAssertEqual(try store.records(now: 5_004).first?.pendingAction, .cancelled)
  }

  func testOutgoingReminderPanelKeepsExactSelectionAndClosesOnTerminalStateOrExpiry() {
    func reminder(_ id: String, peer: String = "peer", outgoing: Bool = true) -> GalaxySSIContactReminder {
      GalaxySSIContactReminder(id: id, peerID: peer, outgoing: outgoing, createdAt: 1_000,
        expiresAt: 3_000, historyID: nil, status: .queued, pendingAction: nil)
    }
    let selection = GalaxySSIContactReminderPanelSelection(owner: "account", id: "selected", peerID: "peer")
    var selected = reminder("selected")
    var older = reminder("older")
    older.status = .acknowledged
    XCTAssertEqual(selection.resolve(in: [older, selected], owner: "account", now: 2_999), selected)
    XCTAssertNil(selection.resolve(in: [older], owner: "account", now: 2_999))
    XCTAssertNil(selection.resolve(in: [selected], owner: "different", now: 2_999))
    XCTAssertNil(selection.resolve(in: [reminder("selected", peer: "different")], owner: "account", now: 2_999))
    XCTAssertNil(selection.resolve(in: [reminder("selected", outgoing: false)], owner: "account", now: 2_999))
    XCTAssertNil(selection.resolve(in: [selected], owner: "account", now: 3_000))
    selected.status = .muted
    XCTAssertEqual(selection.resolve(in: [selected], owner: "account", now: 2_999), selected)
    let terminal: [GalaxySSIContactReminderStatus] = [.acknowledged, .dismissed, .cancelled, .disabled, .expired, .failed]
    for status in terminal {
      selected.status = status
      XCTAssertNil(selection.resolve(in: [selected, older], owner: "account", now: 2_999))
    }
  }

  func testValidatesAndroidCompatibleOpaquePairingQRCode() throws {
    let secret = Data(repeating: 7, count: 32).base64URLEncodedString()
    let qr = pairingQR(secret: secret, createdAt: Date())

    let pairing = try GalaxySSILinkProtocol.decodePairingQRCode(from: qr)

    XCTAssertEqual(pairing.pairingTopic, GalaxySSILinkProtocol.pairingTopic(secret: secret))
    XCTAssertEqual(pairing.access.profile, GalaxySSILinkProtocol.accessRestricted)
    XCTAssertEqual(pairing.pairingSecret.count, 32)
  }

  func testRejectsExpiredPairingQRCode() {
    let secret = Data(repeating: 7, count: 32).base64URLEncodedString()
    let qr = pairingQR(secret: secret, createdAt: Date(timeIntervalSinceNow: -11 * 60))

    XCTAssertThrowsError(try GalaxySSILinkProtocol.decodePairingQRCode(from: qr))
  }

  func testOpaqueRelationshipTopicsAreDirectionalAndRotating() throws {
    let secret = try GalaxySSILinkProtocol.newLinkSecret()
    let first = String(repeating: "a", count: 64)
    let second = String(repeating: "b", count: 64)
    let epoch: Int64 = 42

    let up = GalaxySSILinkProtocol.relationshipTopic(
      linkSecret: secret,
      senderFingerprint: first,
      receiverFingerprint: second,
      epoch: epoch
    )
    let down = GalaxySSILinkProtocol.relationshipTopic(
      linkSecret: secret,
      senderFingerprint: second,
      receiverFingerprint: first,
      epoch: epoch
    )
    let next = GalaxySSILinkProtocol.relationshipTopic(
      linkSecret: secret,
      senderFingerprint: first,
      receiverFingerprint: second,
      epoch: epoch + 1
    )

    XCTAssertTrue(GalaxySSILinkProtocol.validTopic(up))
    XCTAssertNotEqual(up, down)
    XCTAssertNotEqual(up, next)
  }

  func testKdfMatchesCrossPlatformVector() throws {
    let pairingSecret = Data(repeating: 7, count: 32).base64URLEncodedString()
    let first = String(repeating: "a", count: 64)
    let second = String(repeating: "b", count: 64)
    XCTAssertEqual(
      GalaxySSILinkProtocol.pairingTopic(secret: pairingSecret),
      "iqybsnTHlrBIWbkyg5Zi5dQZEQ3BJG0ArcFQ_wXslUg"
    )
    let linkSecret = try GalaxySSILinkProtocol.deriveLinkSecret(
      pairingSecret: pairingSecret,
      firstFingerprint: first,
      secondFingerprint: second
    )
    XCTAssertEqual(linkSecret, "pGaVty_M7X2vnVGROCAJtadESdd7P63LtQq9NbQJ3XM")
    XCTAssertEqual(
      GalaxySSILinkProtocol.relationshipTopic(
        linkSecret: linkSecret,
        senderFingerprint: first,
        receiverFingerprint: second,
        epoch: 42
      ),
      "D4Un2eXXG1aMiV07pQ862RAJRiT0zEnnIHhzgmhJ6F4"
    )
  }

  func testIdentityBoundPhoneRoutesAreSymmetric() throws {
    let sharedSecret = Data((0..<32).map { UInt8($0) })
    let firstFingerprint = String(repeating: "1", count: 64)
    let secondFingerprint = String(repeating: "2", count: 64)

    let firstSecret = try GalaxySSILinkProtocol.deriveIdentityBoundLinkSecret(
      sharedSecret: sharedSecret,
      firstFingerprint: firstFingerprint,
      secondFingerprint: secondFingerprint
    )
    let secondSecret = try GalaxySSILinkProtocol.deriveIdentityBoundLinkSecret(
      sharedSecret: sharedSecret,
      firstFingerprint: secondFingerprint,
      secondFingerprint: firstFingerprint
    )
    let firstRoute = try GalaxySSILinkProtocol.deriveIdentityBoundRouteId(
      linkSecret: firstSecret,
      firstFingerprint: firstFingerprint,
      secondFingerprint: secondFingerprint
    )
    let secondRoute = try GalaxySSILinkProtocol.deriveIdentityBoundRouteId(
      linkSecret: secondSecret,
      firstFingerprint: secondFingerprint,
      secondFingerprint: firstFingerprint
    )

    XCTAssertEqual(firstSecret, secondSecret)
    XCTAssertEqual(firstRoute, secondRoute)
    XCTAssertTrue(GalaxySSILinkProtocol.validLinkSecret(firstSecret))
    XCTAssertTrue(GalaxySSILinkProtocol.validRouteId(firstRoute))
  }

  func testDifferentSignalAgreementProducesDifferentPhoneRelationship() throws {
    let firstFingerprint = String(repeating: "1", count: 64)
    let secondFingerprint = String(repeating: "2", count: 64)
    let first = try GalaxySSILinkProtocol.deriveIdentityBoundLinkSecret(
      sharedSecret: Data(repeating: 3, count: 32),
      firstFingerprint: firstFingerprint,
      secondFingerprint: secondFingerprint
    )
    let second = try GalaxySSILinkProtocol.deriveIdentityBoundLinkSecret(
      sharedSecret: Data(repeating: 4, count: 32),
      firstFingerprint: firstFingerprint,
      secondFingerprint: secondFingerprint
    )

    XCTAssertNotEqual(first, second)
  }

  func testTrustedMatchingPhoneIdentityRefreshesRoutesWithoutDroppingContactState() throws {
    let remoteId = "galaxyssi:\(String(repeating: "a", count: 16))"
    let remoteFingerprint = String(repeating: "a", count: 64)
    let localFingerprint = String(repeating: "b", count: 64)
    let linkSecret = try GalaxySSILinkProtocol.deriveIdentityBoundLinkSecret(
      sharedSecret: Data(repeating: 7, count: 32),
      firstFingerprint: localFingerprint,
      secondFingerprint: remoteFingerprint
    )
    let routeId = try GalaxySSILinkProtocol.deriveIdentityBoundRouteId(
      linkSecret: linkSecret,
      firstFingerprint: localFingerprint,
      secondFingerprint: remoteFingerprint
    )
    var contact = GalaxySSIContact.hermes()
    contact.id = remoteId
    contact.galaxySSIId = remoteId
    contact.name = "Renamed friend"
    contact.displayName = "Renamed friend"
    contact.type = "person"
    contact.trustState = .verified
    contact.identityFingerprint = remoteFingerprint
    contact.linkClientRouteId = String(repeating: "e", count: 22)
    contact.linkSecret = String(repeating: "f", count: 43)
    contact.linkLocalFingerprint = localFingerprint
    let routes = GalaxySSILinkRoutes(
      clientRouteId: routeId,
      linkSecret: linkSecret,
      localFingerprint: localFingerprint,
      remoteFingerprint: remoteFingerprint
    )

    let refreshed = try XCTUnwrap(
      GalaxySSIPhoneRelationshipRouteRefresh.apply(
        existing: contact,
        remoteCard: [
          "galaxyssi_id": remoteId,
          "identity_fingerprint": remoteFingerprint
        ],
        routes: routes,
        now: Date(timeIntervalSince1970: 42)
      )
    )

    XCTAssertEqual(refreshed.name, "Renamed friend")
    XCTAssertEqual(refreshed.displayName, "Renamed friend")
    XCTAssertEqual(refreshed.opaquePhoneRoutes, routes)
    XCTAssertEqual(refreshed.updatedAt, Date(timeIntervalSince1970: 42))
  }

  func testDifferentOrUntrustedPhoneIdentityCannotRefreshRelationship() throws {
    let remoteId = "galaxyssi:\(String(repeating: "a", count: 16))"
    let remoteFingerprint = String(repeating: "a", count: 64)
    let localFingerprint = String(repeating: "b", count: 64)
    let linkSecret = try GalaxySSILinkProtocol.deriveIdentityBoundLinkSecret(
      sharedSecret: Data(repeating: 7, count: 32),
      firstFingerprint: localFingerprint,
      secondFingerprint: remoteFingerprint
    )
    let routeId = try GalaxySSILinkProtocol.deriveIdentityBoundRouteId(
      linkSecret: linkSecret,
      firstFingerprint: localFingerprint,
      secondFingerprint: remoteFingerprint
    )
    let routes = GalaxySSILinkRoutes(
      clientRouteId: routeId,
      linkSecret: linkSecret,
      localFingerprint: localFingerprint,
      remoteFingerprint: remoteFingerprint
    )
    var contact = GalaxySSIContact.hermes()
    contact.id = remoteId
    contact.galaxySSIId = remoteId
    contact.type = "person"
    contact.trustState = .verified
    contact.identityFingerprint = remoteFingerprint

    XCTAssertNil(
      GalaxySSIPhoneRelationshipRouteRefresh.apply(
        existing: contact,
        remoteCard: [
          "galaxyssi_id": remoteId,
          "identity_fingerprint": String(repeating: "9", count: 64)
        ],
        routes: routes
      )
    )
    contact.trustState = .unverified
    XCTAssertNil(
      GalaxySSIPhoneRelationshipRouteRefresh.apply(
        existing: contact,
        remoteCard: [
          "galaxyssi_id": remoteId,
          "identity_fingerprint": remoteFingerprint
        ],
        routes: routes
      )
    )
  }

  func testOpaqueWirePacketRoundTrip() throws {
    let secret = try GalaxySSILinkProtocol.newLinkSecret()
    let payload = Data("{\"type\":\"text\",\"content\":\"hello\"}".utf8)

    let wire = try GalaxySSILinkProtocol.sealWirePacket(payload, secret: secret)
    let opened = try GalaxySSILinkProtocol.openWirePacket(wire, secret: secret)

    XCTAssertEqual(opened, payload)
    XCTAssertFalse(String(decoding: wire, as: UTF8.self).contains("text"))
  }

  func testEnvelopeRoundTripPreservesMessageIdentity() throws {
    let envelope = try GalaxySSILinkProtocol.makeEnvelope(
      payload: ["type": "text", "content": "hello", "conversation_id": "c1"],
      sourceId: "ios-client",
      targetId: "desktop"
    )
    let unwrapped = GalaxySSILinkProtocol.unwrapEnvelope(envelope)

    XCTAssertEqual(unwrapped?["content"] as? String, "hello")
    XCTAssertEqual(unwrapped?["conversation_id"] as? String, "c1")
    XCTAssertNotNil(UUID(uuidString: unwrapped?["message_id"] as? String ?? ""))
  }

  private func pairingQR(secret: String, createdAt: Date) -> String {
    let object: [String: Any] = [
      "t": "o2",
      "n": "Test Mac",
      "h": String(repeating: "a", count: 64),
      "k": Data(repeating: 1, count: 32).base64URLEncodedString(),
      "x": String(repeating: "t", count: 43),
      "e": secret,
      "a": 0,
      "c": Int64(createdAt.timeIntervalSince1970)
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
  }
}
