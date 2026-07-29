import XCTest
@testable import SignalASI

final class SignalASILinkProtocolTests: XCTestCase {
  func testValidatesAndroidCompatiblePairingQRCode() throws {
    let routeId = "abcdefghijklmnopqrstuv"
    let secret = Data(repeating: 7, count: 32).base64URLEncodedString()
    let qr = pairingQR(routeId: routeId, secret: secret, createdAt: Date())

    let pairing = try SignalASILinkProtocol.decodePairingQRCode(from: qr)

    XCTAssertEqual(pairing.serverRouteId, routeId)
    XCTAssertEqual(pairing.pairingTopic, "signalasichat/v1/\(routeId)/pair")
    XCTAssertEqual(pairing.access.profile, SignalASILinkProtocol.accessRestricted)
    XCTAssertEqual(pairing.pairingSecret.count, 32)
  }

  func testRejectsExpiredPairingQRCode() {
    let routeId = "abcdefghijklmnopqrstuv"
    let secret = Data(repeating: 7, count: 32).base64URLEncodedString()
    let oldDate = Date(timeIntervalSinceNow: -11 * 60)
    let qr = pairingQR(routeId: routeId, secret: secret, createdAt: oldDate)

    XCTAssertThrowsError(try SignalASILinkProtocol.decodePairingQRCode(from: qr))
  }

  func testRouteIdsMatchAndroidShape() throws {
    let routeId = try SignalASILinkProtocol.newRouteId()

    XCTAssertEqual(routeId.count, 22)
    XCTAssertTrue(SignalASILinkProtocol.validRouteId(routeId))
  }

  func testEnvelopeRoundTripPreservesMessageIdentity() throws {
    let payload: [String: Any] = [
      "type": "text",
      "content": "hello",
      "conversation_id": "c1"
    ]

    let envelope = try SignalASILinkProtocol.makeEnvelope(
      payload: payload,
      sourceId: "ios-client",
      targetId: "desktop"
    )
    let unwrapped = SignalASILinkProtocol.unwrapEnvelope(envelope)

    XCTAssertEqual(unwrapped?["content"] as? String, "hello")
    XCTAssertEqual(unwrapped?["conversation_id"] as? String, "c1")
    XCTAssertNotNil(UUID(uuidString: unwrapped?["message_id"] as? String ?? ""))
  }

  private func pairingQR(routeId: String, secret: String, createdAt: Date) -> String {
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
      "pairing_secret": secret,
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
}
