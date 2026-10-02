import XCTest
@testable import GalaxySSI

final class MqttPeerRouteSessionTests: XCTestCase {
  private let alice = String(repeating: "a", count: 64)
  private let bob = String(repeating: "b", count: 64)
  private var suite = ""
  private var defaults: UserDefaults!
  private var secrets = InMemorySecretStore()
  private var wall: Int64 = 1_000
  private var uptime: Int64 = 1_000
  private let paths: [String: Int64] = ["emqx": 1]

  override func setUp() {
    super.setUp()
    suite = "MqttPeerRouteSessionTests-\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)!
    secrets = InMemorySecretStore()
    wall = 1_000
    uptime = 1_000
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suite)
    super.tearDown()
  }

  func testAndroidRouteAdvertisementDigestVector() throws {
    let advertisement = MqttRouteAdvertisement(sender: alice, receiver: bob, epoch: 1_000,
      resumeId: String(repeating: "c", count: 32), issuedAt: 1_000, expiresAt: 301_000,
      receiveBrokers: ["emqx", "hivemq"], packetBytes: 1_048_576)
    XCTAssertEqual(try advertisement.digest(), "21d951fc073d56abcf59437dd7b0ed12cc6e34dc3cb5b3b07becdaaa2e2d9269")
    let json = try JSONSerialization.data(withJSONObject: advertisement.wire())
    let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
    XCTAssertEqual(try MqttRouteAdvertisement.parseVerified(wire, sender: alice, receiver: bob, now: wall), advertisement)
  }

  func testStrictCountersCapabilitiesBrokersAndIdentityValidation() {
    let valid = remote().wire()
    let mutations: [(String, Any)] = [
      ("route_epoch", true), ("route_epoch", "1"), ("route_epoch", 1.5), ("route_epoch", 0),
      ("route_epoch", MqttRouteProtocol.maximumInteger + 1), ("multipath", 1), ("chunk_acks", false),
      ("receive_brokers", ["emqx", "emqx"]), ("receive_brokers", ["unknown"]),
      ("supported_brokers", ["emqx"]), ("expires_at_ms", wall), ("expires_at_ms", wall + 300_001),
      ("sender_fingerprint", alice), ("resume_id", "invalid"), ("max_encoded_packet_bytes", 1_048_577)
    ]
    for (key, value) in mutations {
      var changed = valid
      changed[key] = value
      XCTAssertThrowsError(try MqttRouteAdvertisement.parseVerified(changed, sender: bob, receiver: alice, now: wall), key)
    }
  }

  func testPersistentEpochAndWatermarkSurviveRetirementAndRestart() throws {
    let first = try persistence().issue(peer: "pair", sender: alice, receiver: bob, brokers: ["emqx"], now: wall)
    let advertisement = remote(epoch: 8)
    XCTAssertEqual(try persistence().record(peer: "pair", advertisement: advertisement, now: wall), .new)
    try persistence().forget(peer: "pair")
    XCTAssertNil(try persistence().cached(peer: "pair", sender: bob, receiver: alice, now: wall))
    let second = try persistence().issue(peer: "pair", sender: alice, receiver: bob, brokers: ["emqx"], now: wall)
    XCTAssertGreaterThan(second.epoch, first.epoch)
    XCTAssertEqual(try persistence().record(peer: "pair", advertisement: advertisement, now: wall), .duplicate)
    XCTAssertEqual(try persistence().record(peer: "pair", advertisement: remote(epoch: 7), now: wall), .stale)
    var conflict = advertisement
    conflict.packetBytes = 65_536
    XCTAssertEqual(try persistence().record(peer: "pair", advertisement: conflict, now: wall), .conflict)
  }

  func testCorruptOrUndecryptableMetadataFailsClosed() throws {
    let state = persistence()
    _ = try state.issue(peer: "pair", sender: alice, receiver: bob, brokers: ["emqx"], now: wall)
    let wrongSecrets = MqttRouteState(defaults: defaults, secrets: InMemorySecretStore())
    XCTAssertThrowsError(try wrongSecrets.issue(peer: "pair", sender: alice, receiver: bob, brokers: ["emqx"], now: wall))
    let key = try state.storageKey("pair")
    defaults.set(Data([1, 2, 3]), forKey: key + ".encrypted.v1")
    XCTAssertThrowsError(try state.issue(peer: "pair", sender: alice, receiver: bob, brokers: ["emqx"], now: wall))
    XCTAssertThrowsError(try state.record(peer: "pair", advertisement: remote(), now: wall))
  }

  func testExpiredCacheDoesNotEraseReplayWatermark() throws {
    let state = persistence()
    XCTAssertEqual(try state.record(peer: "pair", advertisement: remote(epoch: 20), now: wall), .new)
    advance(300_001)
    XCTAssertNil(try state.cached(peer: "pair", sender: bob, receiver: alice, now: wall))
    XCTAssertEqual(try state.record(peer: "pair", advertisement: remote(epoch: 19), now: wall), .stale)
  }

  func testRouteMetadataIsEncryptedAndBoundToItsPeerKey() throws {
    let state = persistence()
    _ = try state.record(peer: "pair", advertisement: remote(), now: wall)
    let key = try state.storageKey("pair")
    XCTAssertNil(defaults.data(forKey: key))
    let disk = try XCTUnwrap(defaults.data(forKey: key + ".encrypted.v1"))
    XCTAssertNil(disk.range(of: Data(bob.utf8)))
    defaults.set(disk, forKey: try state.storageKey("another-peer") + ".encrypted.v1")
    XCTAssertThrowsError(try state.issue(peer: "another-peer", sender: alice, receiver: bob, brokers: ["emqx"], now: wall))
  }

  func testFullTwoWayResumeHandshakeAndControlRateLimit() throws {
    let session = try makeSession()
    let local = try advertised(session)
    let inbound = remote()
    let response = try receive(session, inbound.wire()).response
    XCTAssertEqual(response?.payload["type"] as? String, "link_resume_ack")
    XCTAssertEqual(response?.payload["acknowledged_digest"] as? String, try inbound.digest())
    XCTAssertFalse(session.ready(readyGenerations: paths))
    XCTAssertNil(try receive(session, inbound.wire()).response)
    advance(1_000)
    XCTAssertNotNil(try receive(session, inbound.wire()).response)
    XCTAssertTrue(try receive(session, ack(local: local, advertisement: inbound)).becameReady)
    XCTAssertTrue(session.ready(readyGenerations: paths))
    XCTAssertTrue(try session.maintenance(readyGenerations: paths).isEmpty)
  }

  func testSchedulerRouteRequiresCurrentHandshakeAndDoesNotExtendDuplicateLease() throws {
    let session = try makeSession()
    let local = try advertised(session)
    let inbound = remote()
    XCTAssertNil(session.schedulingRoute(readyGenerations: paths))
    _ = try receive(session, ack(local: local, advertisement: inbound))
    let route = try XCTUnwrap(session.schedulingRoute(readyGenerations: paths))
    let policy = MqttMultipathPolicy()
    policy.synchronize(["emqx": .init(brokerID: "emqx", generation: 1, connected: true, subscriptions: ["inbox"])])
    XCTAssertTrue(policy.acceptVerifiedResume(peer: "pair", route: route, now: uptime))
    advance(1000)
    _ = try receive(session, inbound.wire())
    XCTAssertEqual(session.schedulingRoute(readyGenerations: paths), route)
    XCTAssertNil(session.schedulingRoute(readyGenerations: ["emqx": 2]))
    session.setEnabled(false)
    XCTAssertNil(session.schedulingRoute(readyGenerations: paths))
  }

  func testStalledRecoveryRenewsOnlyTheVerifiedPeerAndRejectsOldACK() throws {
    let first = try makeSession()
    let second = try makeSession(scope: "second")
    let firstLocal = try advertised(first)
    let secondLocal = try advertised(second)
    _ = try receive(first, ack(local: firstLocal))
    _ = try receive(second, ack(local: secondLocal))
    let changed: [String: Int64] = ["emqx": 2]
    XCTAssertFalse(first.ready(readyGenerations: changed))
    XCTAssertFalse(first.recoverBlockedSend(readyGenerations: changed))
    advance(30_001)
    XCTAssertTrue(first.recoverBlockedSend(readyGenerations: changed))
    let renewed = try advertised(first, generations: changed)
    XCTAssertGreaterThan(renewed.epoch, firstLocal.epoch)
    XCTAssertTrue(second.ready(readyGenerations: paths))
    XCTAssertTrue(try second.maintenance(readyGenerations: paths).isEmpty)
    _ = try receive(first, ack(local: firstLocal), generation: 2, generations: changed)
    XCTAssertFalse(first.ready(readyGenerations: changed))
    _ = try receive(first, ack(local: renewed, advertisement: remote(epoch: 2)), generation: 2, generations: changed)
    XCTAssertTrue(first.ready(readyGenerations: changed))
  }

  func testUnverifiedOfflineDisabledAndHealthyPeersNeverForceRecovery() throws {
    let session = try makeSession()
    let local = try advertised(session)
    XCTAssertFalse(session.recoverBlockedSend(readyGenerations: paths))
    advance(30_001)
    XCTAssertFalse(session.recoverBlockedSend(readyGenerations: paths))
    _ = try receive(session, ack(local: local))
    XCTAssertFalse(session.recoverBlockedSend(readyGenerations: paths))
    XCTAssertFalse(session.recoverBlockedSend(readyGenerations: [:]))
    session.setEnabled(false)
    XCTAssertFalse(session.recoverBlockedSend(readyGenerations: ["emqx": 2]))
    session.setEnabled(true)
    XCTAssertTrue(session.ready(readyGenerations: paths))
  }

  func testRecoveryHasCooldownAndExpiresAuthentication() throws {
    let session = try makeSession()
    let local = try advertised(session)
    _ = try receive(session, ack(local: local))
    let changed: [String: Int64] = ["emqx": 2]
    XCTAssertFalse(session.recoverBlockedSend(readyGenerations: changed))
    advance(30_000)
    XCTAssertTrue(session.recoverBlockedSend(readyGenerations: changed))
    _ = try advertised(session, generations: changed)
    advance(30_000)
    XCTAssertFalse(session.recoverBlockedSend(readyGenerations: changed))
    advance(90_000)
    XCTAssertTrue(session.recoverBlockedSend(readyGenerations: changed))
    advance(300_001)
    XCTAssertFalse(session.recoverBlockedSend(readyGenerations: changed))
  }

  func testWrongIdentityGenerationDigestAndUnsolicitedACKCannotConfirmRoute() throws {
    let session = try makeSession()
    let local = try advertised(session)
    let payload = try ack(local: local)
    XCTAssertThrowsError(try session.receiveVerified(payload, brokerID: "emqx", generation: 1,
      authenticationID: "old-identity", readyGenerations: paths))
    XCTAssertThrowsError(try receive(session, payload, generation: 2))
    var tampered = payload
    tampered["acknowledged_digest"] = String(repeating: "0", count: 64)
    XCTAssertThrowsError(try receive(session, tampered))
    let unrequested = try makeSession(scope: "unrequested")
    XCTAssertThrowsError(try receive(unrequested, payload))
    XCTAssertFalse(session.ready(readyGenerations: paths))
  }

  func testWallClockRollbackDoesNotExtendVerifiedRouteLease() throws {
    let session = try makeSession()
    let local = try advertised(session)
    let payload = try ack(local: local)
    _ = try receive(session, payload)
    uptime += MqttRouteProtocol.resumeTTL + 1
    // Duplicate same-epoch proof must not renew the monotonic lease after wall-clock rollback.
    _ = try receive(session, payload)
    XCTAssertFalse(session.ready(readyGenerations: paths))
  }

  func testBrokerGenerationChangeAndNoCommonBrokerStayBlocked() throws {
    let session = try makeSession()
    let local = try advertised(session)
    var other = remote()
    other.receiveBrokers = ["hivemq"]
    XCTAssertFalse(try receive(session, ack(local: local, advertisement: other)).becameReady)
    XCTAssertFalse(session.ready(readyGenerations: paths))
    XCTAssertEqual(session.blockedReason(readyGenerations: paths), "no_verified_common_route")
    XCTAssertEqual(session.blockedReason(readyGenerations: ["emqx": 2]), "changed_broker_generation")
    XCTAssertThrowsError(try session.maintenance(readyGenerations: ["unknown": 1]))
  }

  func testLeaseRenewalDoesNotRepeatApplicationReadyEvent() throws {
    let session = try makeSession()
    let local = try advertised(session)
    XCTAssertTrue(try receive(session, ack(local: local)).becameReady)
    advance(150_001)
    let renewed = try advertised(session)
    XCTAssertGreaterThan(renewed.epoch, local.epoch)
    XCTAssertFalse(try receive(session, ack(local: renewed, advertisement: remote(epoch: 2))).becameReady)
    XCTAssertTrue(session.ready(readyGenerations: paths))
  }

  func testRetiredSessionRejectsTrafficWithoutResettingEpoch() throws {
    let session = try makeSession()
    let first = try advertised(session)
    _ = try receive(session, ack(local: first))
    try session.retire()
    XCTAssertFalse(session.ready(readyGenerations: paths))
    XCTAssertTrue(try session.maintenance(readyGenerations: paths).isEmpty)
    XCTAssertThrowsError(try receive(session, remote(epoch: 2).wire()))
    let replacement = try makeSession()
    XCTAssertGreaterThan(try advertised(replacement).epoch, first.epoch)
    XCTAssertFalse(replacement.ready(readyGenerations: paths))
  }

  private func makeSession(scope: String = "pair") throws -> MqttPeerRouteSession {
    try MqttPeerRouteSession(binding: MqttPeerRouteBinding(scope: scope, sender: alice, receiver: bob,
      authenticationID: "trusted-pair"), persistence: persistence(), wall: { self.wall }, monotonic: { self.uptime })
  }

  private func persistence() -> MqttRouteState { MqttRouteState(defaults: defaults, secrets: secrets) }

  private func advance(_ milliseconds: Int64) { wall += milliseconds; uptime += milliseconds }

  private func remote(epoch: Int64 = 1) -> MqttRouteAdvertisement {
    MqttRouteAdvertisement(sender: bob, receiver: alice, epoch: epoch, resumeId: String(repeating: "d", count: 32),
      issuedAt: wall, expiresAt: wall + MqttRouteProtocol.resumeTTL, receiveBrokers: ["emqx"], packetBytes: 1_048_576)
  }

  private func advertised(_ session: MqttPeerRouteSession, generations: [String: Int64]? = nil) throws -> MqttRouteAdvertisement {
    let publication = try XCTUnwrap(session.maintenance(readyGenerations: generations ?? paths).first)
    return try MqttRouteAdvertisement.parseVerified(publication.payload, sender: alice, receiver: bob, now: wall)
  }

  private func ack(local: MqttRouteAdvertisement, advertisement: MqttRouteAdvertisement? = nil) throws -> [String: Any] {
    ["type": "link_resume_ack", "advertisement": (advertisement ?? remote()).wire(),
     "acknowledged_route_epoch": local.epoch, "acknowledged_resume_id": local.resumeId,
     "acknowledged_digest": try local.digest()]
  }

  private func receive(_ session: MqttPeerRouteSession, _ payload: [String: Any], generation: Int64 = 1,
                       generations: [String: Int64]? = nil) throws -> MqttPeerRouteReception {
    try session.receiveVerified(payload, brokerID: "emqx", generation: generation,
      authenticationID: "trusted-pair", readyGenerations: generations ?? paths)
  }
}
