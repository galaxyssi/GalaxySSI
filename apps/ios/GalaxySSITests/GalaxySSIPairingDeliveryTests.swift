import XCTest
@testable import GalaxySSI

final class GalaxySSIPairingDeliveryTests: XCTestCase {
  private var suite = ""
  private var defaults: UserDefaults!
  private var secrets = InMemorySecretStore()
  private var now: Int64 = 1_000_000
  private let fingerprint = String(repeating: "b", count: 64)
  private let secret = Data(repeating: 7, count: 32).base64URLEncodedString()

  override func setUp() {
    super.setUp()
    suite = "PairingDeliveryTests-\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)!
    secrets = InMemorySecretStore()
    now = 1_000_000
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suite)
    defaults = nil
    super.tearDown()
  }

  func testEncryptedRestartRetainsOriginalControlIDAndPayload() throws {
    let store = makeStore()
    let original = payload()
    XCTAssertTrue(enqueue(original, in: store))
    let first = try XCTUnwrap(store.takeDue().first)
    XCTAssertEqual(first.attempts, 1)
    XCTAssertNil(defaults.data(forKey: GalaxySSIPairingDeliveryStore.storageKey))
    let disk = try XCTUnwrap(defaults.data(forKey: GalaxySSIPairingDeliveryStore.storageKey + ".encrypted.v1"))
    XCTAssertNil(disk.range(of: Data(first.controlId.utf8)))
    XCTAssertNil(disk.range(of: Data(secret.utf8)))
    XCTAssertNotEqual(disk, first.payload)

    now += 2_000
    let restored = makeStore()
    XCTAssertTrue(enqueue(payload(), in: restored))
    XCTAssertEqual(restored.pending().count, 1)
    let retried = try XCTUnwrap(restored.takeDue().first)
    XCTAssertEqual(retried.controlId, first.controlId)
    XCTAssertEqual(retried.payload, first.payload)
    XCTAssertEqual(retried.payloadHash, first.payloadHash)
    XCTAssertEqual(retried.attempts, 2)
  }

  func testOnlyExactPeerFingerprintControlAndHashCanRetireDelivery() throws {
    let store = makeStore()
    XCTAssertTrue(enqueue(payload(), in: store))
    let pending = try XCTUnwrap(store.takeDue().first)
    let receipt: [String: Any] = ["ack_control_id": pending.controlId, "ack_payload_hash": pending.payloadHash]
    XCTAssertFalse(store.acknowledge(peer: "wrong-peer", fingerprint: fingerprint, receipt: receipt))
    XCTAssertFalse(store.acknowledge(peer: pending.peer, fingerprint: "wrong-fingerprint", receipt: receipt))
    XCTAssertFalse(store.acknowledge(peer: pending.peer, fingerprint: fingerprint, receipt: [
      "ack_control_id": pending.controlId, "ack_payload_hash": "wrong-hash"
    ]))
    XCTAssertFalse(store.acknowledge(peer: pending.peer, fingerprint: fingerprint, receipt: [
      "ack_control_id": UUID().uuidString, "ack_payload_hash": pending.payloadHash
    ]))
    XCTAssertEqual(store.pending().count, 1)
    XCTAssertTrue(store.acknowledge(peer: pending.peer, fingerprint: fingerprint, receipt: receipt))
    XCTAssertTrue(makeStore().pending().isEmpty)
  }

  func testRetriesBoundedAndExpiredControlsAreNotReplayed() throws {
    let store = makeStore()
    XCTAssertTrue(enqueue(payload(), in: store))
    for expected in 1...GalaxySSIPairingDeliveryStore.maximumAttempts {
      let attempt = try XCTUnwrap(store.takeDue().first)
      XCTAssertEqual(attempt.attempts, expected)
      now = attempt.nextAttemptAt
    }
    XCTAssertTrue(store.takeDue().isEmpty)
    XCTAssertNil(store.nextDelayMillis())
    XCTAssertEqual(store.pending().count, 1)
    now = 1_000_000 + GalaxySSIPhoneContactControl.maximumAgeMillis
    XCTAssertTrue(makeStore().pending().isEmpty)
  }

  func testQueueCapAndExplicitRecoveryAreDistinct() {
    let store = makeStore()
    XCTAssertTrue(enqueue(payload(), in: store))
    var recovery = payload()
    recovery["session_recovery"] = true
    XCTAssertTrue(enqueue(recovery, in: store))
    XCTAssertEqual(store.pending().count, 2)
    for index in 2..<GalaxySSIPairingDeliveryStore.maximumPending {
      var next = payload()
      next["to"] = "peer-\(index)"
      XCTAssertTrue(enqueue(next, in: store))
    }
    var overflow = payload()
    overflow["to"] = "overflow-peer"
    XCTAssertFalse(enqueue(overflow, in: store))
    XCTAssertEqual(store.pending().count, GalaxySSIPairingDeliveryStore.maximumPending)
  }

  func testApprovalSupersedesRejectionWithoutReplayingBoth() {
    let store = makeStore()
    XCTAssertTrue(enqueue(payload(kind: "opaque_contact_reject"), in: store))
    XCTAssertTrue(enqueue(payload(kind: "opaque_contact_accept"), in: store))
    XCTAssertEqual(store.pending().map(\.kind), ["opaque_contact_accept"])
    XCTAssertFalse(enqueue(payload(kind: "opaque_contact_receipt"), in: store))
  }

  func testAcceptedControlsSurviveRestartAndAreBoundToSenderAndPayload() {
    let original = payload()
    XCTAssertTrue(makeStore().markAccepted(original))
    let restored = makeStore()
    XCTAssertTrue(restored.accepted(original))
    var other = original
    other["from"] = "another-peer"
    XCTAssertFalse(restored.accepted(other))
    other = original
    other["session_recovery"] = true
    XCTAssertFalse(restored.accepted(other))
    XCTAssertFalse(makeStore(identity: "new-local-identity").accepted(original))
    now += GalaxySSIPhoneContactControl.maximumAgeMillis
    XCTAssertFalse(restored.accepted(original))
  }

  func testDesktopClaimSurvivesRestartAndIdentityChangeInvalidatesIt() throws {
    let store = makeStore()
    let claim: [String: Any] = ["type": "galaxyssi_pairing_claim", "time": now, "pairing_token": "secret-token"]
    XCTAssertTrue(store.enqueue(
      payload: claim, topic: secret, secret: secret, fingerprint: fingerprint,
      desktopId: "desktop-1", desktopName: "Desktop", clientRouteId: "route-1"
    ))
    let pending = try XCTUnwrap(makeStore().pending().first)
    XCTAssertTrue(pending.isDesktop)
    XCTAssertEqual(pending.clientRouteId, "route-1")
    XCTAssertEqual(pending.desktopName, "Desktop")
    XCTAssertFalse(store.acknowledge(peer: pending.peer, fingerprint: fingerprint, receipt: [
      "ack_control_id": pending.controlId, "ack_payload_hash": pending.payloadHash
    ]))
    XCTAssertTrue(makeStore(identity: "new-local-identity").pending().isEmpty)
    store.discard(controlId: pending.controlId)
    XCTAssertTrue(makeStore().pending().isEmpty)
  }

  func testAndroidCanonicalHashIncludesSlashUnicodeBooleanAndIntegerRules() throws {
    let value: [String: Any] = [
      "time": 123456789, "name": "\u{4e2d}\u{6587}\n", "enabled": true,
      "bundle": ["registrationId": 1, "identityKey": "a/b+=="]
    ]
    let expected = "b76aa6fc4cedec069fb7da628f417707414994f724b83e4030ded8567dee0b9b"
    XCTAssertEqual(GalaxySSIPairingDeliveryStore.payloadHash(value), expected)
    let roundTrip = try XCTUnwrap(JSONSerialization.jsonObject(
      with: JSONSerialization.data(withJSONObject: value)
    ) as? [String: Any])
    XCTAssertEqual(GalaxySSIPairingDeliveryStore.payloadHash(roundTrip), expected)
  }

  private func makeStore(identity: String = "local-identity") -> GalaxySSIPairingDeliveryStore {
    GalaxySSIPairingDeliveryStore(localIdentity: identity, defaults: defaults, secrets: secrets, clock: { self.now })
  }

  private func payload(kind: String = "opaque_contact_confirm") -> [String: Any] {
    ["type": kind, "control_id": UUID().uuidString, "from": "local", "to": "peer", "time": now]
  }

  private func enqueue(_ payload: [String: Any], in store: GalaxySSIPairingDeliveryStore) -> Bool {
    store.enqueue(payload: payload, topic: secret, secret: secret, fingerprint: fingerprint)
  }
}
