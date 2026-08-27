import XCTest
@testable import SignalASI

final class SignalASILinkProtocolTests: XCTestCase {
  func testValidatesAndroidCompatibleOpaquePairingQRCode() throws {
    let secret = Data(repeating: 7, count: 32).base64URLEncodedString()
    let qr = pairingQR(secret: secret, createdAt: Date())

    let pairing = try SignalASILinkProtocol.decodePairingQRCode(from: qr)

    XCTAssertEqual(pairing.pairingTopic, SignalASILinkProtocol.pairingTopic(secret: secret))
    XCTAssertEqual(pairing.access.profile, SignalASILinkProtocol.accessRestricted)
    XCTAssertEqual(pairing.pairingSecret.count, 32)
  }

  func testRejectsExpiredPairingQRCode() {
    let secret = Data(repeating: 7, count: 32).base64URLEncodedString()
    let qr = pairingQR(secret: secret, createdAt: Date(timeIntervalSinceNow: -11 * 60))

    XCTAssertThrowsError(try SignalASILinkProtocol.decodePairingQRCode(from: qr))
  }

  func testOpaqueRelationshipTopicsAreDirectionalAndRotating() throws {
    let secret = try SignalASILinkProtocol.newLinkSecret()
    let first = String(repeating: "a", count: 64)
    let second = String(repeating: "b", count: 64)
    let epoch: Int64 = 42

    let up = SignalASILinkProtocol.relationshipTopic(
      linkSecret: secret,
      senderFingerprint: first,
      receiverFingerprint: second,
      epoch: epoch
    )
    let down = SignalASILinkProtocol.relationshipTopic(
      linkSecret: secret,
      senderFingerprint: second,
      receiverFingerprint: first,
      epoch: epoch
    )
    let next = SignalASILinkProtocol.relationshipTopic(
      linkSecret: secret,
      senderFingerprint: first,
      receiverFingerprint: second,
      epoch: epoch + 1
    )

    XCTAssertTrue(SignalASILinkProtocol.validTopic(up))
    XCTAssertNotEqual(up, down)
    XCTAssertNotEqual(up, next)
  }

  func testKdfMatchesCrossPlatformVector() throws {
    let pairingSecret = Data(repeating: 7, count: 32).base64URLEncodedString()
    let first = String(repeating: "a", count: 64)
    let second = String(repeating: "b", count: 64)
    XCTAssertEqual(
      SignalASILinkProtocol.pairingTopic(secret: pairingSecret),
      "iqybsnTHlrBIWbkyg5Zi5dQZEQ3BJG0ArcFQ_wXslUg"
    )
    let linkSecret = try SignalASILinkProtocol.deriveLinkSecret(
      pairingSecret: pairingSecret,
      firstFingerprint: first,
      secondFingerprint: second
    )
    XCTAssertEqual(linkSecret, "pGaVty_M7X2vnVGROCAJtadESdd7P63LtQq9NbQJ3XM")
    XCTAssertEqual(
      SignalASILinkProtocol.relationshipTopic(
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

    let firstSecret = try SignalASILinkProtocol.deriveIdentityBoundLinkSecret(
      sharedSecret: sharedSecret,
      firstFingerprint: firstFingerprint,
      secondFingerprint: secondFingerprint
    )
    let secondSecret = try SignalASILinkProtocol.deriveIdentityBoundLinkSecret(
      sharedSecret: sharedSecret,
      firstFingerprint: secondFingerprint,
      secondFingerprint: firstFingerprint
    )
    let firstRoute = try SignalASILinkProtocol.deriveIdentityBoundRouteId(
      linkSecret: firstSecret,
      firstFingerprint: firstFingerprint,
      secondFingerprint: secondFingerprint
    )
    let secondRoute = try SignalASILinkProtocol.deriveIdentityBoundRouteId(
      linkSecret: secondSecret,
      firstFingerprint: secondFingerprint,
      secondFingerprint: firstFingerprint
    )

    XCTAssertEqual(firstSecret, secondSecret)
    XCTAssertEqual(firstRoute, secondRoute)
    XCTAssertTrue(SignalASILinkProtocol.validLinkSecret(firstSecret))
    XCTAssertTrue(SignalASILinkProtocol.validRouteId(firstRoute))
  }

  func testDifferentSignalAgreementProducesDifferentPhoneRelationship() throws {
    let firstFingerprint = String(repeating: "1", count: 64)
    let secondFingerprint = String(repeating: "2", count: 64)
    let first = try SignalASILinkProtocol.deriveIdentityBoundLinkSecret(
      sharedSecret: Data(repeating: 3, count: 32),
      firstFingerprint: firstFingerprint,
      secondFingerprint: secondFingerprint
    )
    let second = try SignalASILinkProtocol.deriveIdentityBoundLinkSecret(
      sharedSecret: Data(repeating: 4, count: 32),
      firstFingerprint: firstFingerprint,
      secondFingerprint: secondFingerprint
    )

    XCTAssertNotEqual(first, second)
  }

  func testTrustedMatchingPhoneIdentityRefreshesRoutesWithoutDroppingContactState() throws {
    let remoteId = "signalasi:\(String(repeating: "a", count: 16))"
    let remoteFingerprint = String(repeating: "a", count: 64)
    let localFingerprint = String(repeating: "b", count: 64)
    let linkSecret = try SignalASILinkProtocol.deriveIdentityBoundLinkSecret(
      sharedSecret: Data(repeating: 7, count: 32),
      firstFingerprint: localFingerprint,
      secondFingerprint: remoteFingerprint
    )
    let routeId = try SignalASILinkProtocol.deriveIdentityBoundRouteId(
      linkSecret: linkSecret,
      firstFingerprint: localFingerprint,
      secondFingerprint: remoteFingerprint
    )
    var contact = SignalASIContact.hermes()
    contact.id = remoteId
    contact.signalASIId = remoteId
    contact.name = "Renamed friend"
    contact.displayName = "Renamed friend"
    contact.type = "person"
    contact.trustState = .verified
    contact.identityFingerprint = remoteFingerprint
    contact.linkClientRouteId = String(repeating: "e", count: 22)
    contact.linkSecret = String(repeating: "f", count: 43)
    contact.linkLocalFingerprint = localFingerprint
    let routes = SignalASILinkRoutes(
      clientRouteId: routeId,
      linkSecret: linkSecret,
      localFingerprint: localFingerprint,
      remoteFingerprint: remoteFingerprint
    )

    let refreshed = try XCTUnwrap(
      SignalASIPhoneRelationshipRouteRefresh.apply(
        existing: contact,
        remoteCard: [
          "signalasi_id": remoteId,
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
    let remoteId = "signalasi:\(String(repeating: "a", count: 16))"
    let remoteFingerprint = String(repeating: "a", count: 64)
    let localFingerprint = String(repeating: "b", count: 64)
    let linkSecret = try SignalASILinkProtocol.deriveIdentityBoundLinkSecret(
      sharedSecret: Data(repeating: 7, count: 32),
      firstFingerprint: localFingerprint,
      secondFingerprint: remoteFingerprint
    )
    let routeId = try SignalASILinkProtocol.deriveIdentityBoundRouteId(
      linkSecret: linkSecret,
      firstFingerprint: localFingerprint,
      secondFingerprint: remoteFingerprint
    )
    let routes = SignalASILinkRoutes(
      clientRouteId: routeId,
      linkSecret: linkSecret,
      localFingerprint: localFingerprint,
      remoteFingerprint: remoteFingerprint
    )
    var contact = SignalASIContact.hermes()
    contact.id = remoteId
    contact.signalASIId = remoteId
    contact.type = "person"
    contact.trustState = .verified
    contact.identityFingerprint = remoteFingerprint

    XCTAssertNil(
      SignalASIPhoneRelationshipRouteRefresh.apply(
        existing: contact,
        remoteCard: [
          "signalasi_id": remoteId,
          "identity_fingerprint": String(repeating: "9", count: 64)
        ],
        routes: routes
      )
    )
    contact.trustState = .unverified
    XCTAssertNil(
      SignalASIPhoneRelationshipRouteRefresh.apply(
        existing: contact,
        remoteCard: [
          "signalasi_id": remoteId,
          "identity_fingerprint": remoteFingerprint
        ],
        routes: routes
      )
    )
  }

  func testOpaqueWirePacketRoundTrip() throws {
    let secret = try SignalASILinkProtocol.newLinkSecret()
    let payload = Data("{\"type\":\"text\",\"content\":\"hello\"}".utf8)

    let wire = try SignalASILinkProtocol.sealWirePacket(payload, secret: secret)
    let opened = try SignalASILinkProtocol.openWirePacket(wire, secret: secret)

    XCTAssertEqual(opened, payload)
    XCTAssertFalse(String(decoding: wire, as: UTF8.self).contains("text"))
  }

  func testEnvelopeRoundTripPreservesMessageIdentity() throws {
    let envelope = try SignalASILinkProtocol.makeEnvelope(
      payload: ["type": "text", "content": "hello", "conversation_id": "c1"],
      sourceId: "ios-client",
      targetId: "desktop"
    )
    let unwrapped = SignalASILinkProtocol.unwrapEnvelope(envelope)

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
