import XCTest
@testable import GalaxySSI

final class MqttBrokerPoolTests: XCTestCase {
  private let topics: Set<String> = ["incoming", "control"]

  func testCatalogMatchesAndroidTLSPaths() {
    XCTAssertEqual(Set(MqttBrokerEndpoint.catalog.map(\.id)), MqttRouteProtocol.brokerIDs)
    XCTAssertEqual(MqttBrokerEndpoint.catalog.first { $0.id == "mosquitto" }?.tlsPort, 8886)
    XCTAssertTrue(MqttBrokerEndpoint.catalog.allSatisfy { !$0.host.isEmpty && $0.tlsPort > 0 })
  }

  func testReadinessRequiresEveryPeerTopicButNotOtherPeersTopics() {
    let snapshots = ["emqx": snapshot("emqx", topics: topics),
                     "hivemq": snapshot("hivemq", topics: ["incoming"])]
    XCTAssertEqual(MqttBrokerPathPolicy.readyGenerations(snapshots, topics: topics), ["emqx": 1])
    XCTAssertEqual(MqttBrokerPathPolicy.readyGenerations(snapshots, topics: ["incoming"]), ["emqx": 1, "hivemq": 1])
    XCTAssertTrue(MqttBrokerPathPolicy.readyGenerations(snapshots, topics: []).isEmpty)
  }

  func testSUBACKMustMatchCountAndOnlyGrantsSuccessfulTopics() {
    XCTAssertEqual(MqttBrokerPathPolicy.acknowledgedTopics([1, 0x80], requested: topics), ["control"])
    XCTAssertEqual(MqttBrokerPathPolicy.acknowledgedTopics([0, 2], requested: topics), topics)
    XCTAssertNil(MqttBrokerPathPolicy.acknowledgedTopics([1], requested: topics))
    XCTAssertNil(MqttBrokerPathPolicy.acknowledgedTopics([1, 3], requested: topics))
    XCTAssertNil(MqttBrokerPathPolicy.acknowledgedTopics([1, 1, 1], requested: topics))
  }

  func testLostSUBACKExpiresOnlyTimedOutRequests() {
    let pending: [UInt16: Int64] = [1: 1_000, 2: 12_000, 3: 20_000]
    XCTAssertEqual(MqttBrokerPathPolicy.expiredSubscriptionIDs(pending, now: 15_999), [])
    XCTAssertEqual(MqttBrokerPathPolicy.expiredSubscriptionIDs(pending, now: 16_000), [1])
    XCTAssertEqual(MqttBrokerPathPolicy.expiredSubscriptionIDs(pending, now: 27_000), [1, 2])
  }

  func testPathAuthorizationBindsGenerationSubscriptionsAndKey() {
    let publication = publication()
    let ready = snapshot("emqx", topics: topics)
    XCTAssertTrue(MqttBrokerPathPolicy.accepts(publication, snapshot: ready, currentSecretFingerprint: "secret-hash"))
    XCTAssertFalse(MqttBrokerPathPolicy.accepts(publication, snapshot: ready, currentSecretFingerprint: "rotated-key"))
    XCTAssertFalse(MqttBrokerPathPolicy.accepts(publication, snapshot: snapshot("emqx", generation: 2, topics: topics),
                                               currentSecretFingerprint: "secret-hash"))
    XCTAssertFalse(MqttBrokerPathPolicy.accepts(publication, snapshot: snapshot("emqx", topics: ["incoming"]),
                                               currentSecretFingerprint: "secret-hash"))
    var reconfigured = ready
    reconfigured.configurationID = "new-configuration"
    XCTAssertFalse(MqttBrokerPathPolicy.accepts(publication, snapshot: reconfigured,
                                               currentSecretFingerprint: "secret-hash"))
  }

  func testPoolStartsThreeIndependentClientsAndAggregatesReadiness() async {
    let (pool, paths) = rig()
    await start(pool)
    paths["emqx"]!.emit(snapshot("emqx", topics: topics))
    paths["hivemq"]!.emit(snapshot("hivemq", topics: ["incoming"]))
    let ready = await pool.readyGenerations(for: topics)
    XCTAssertEqual(ready, ["emqx": 1])
    XCTAssertEqual(pool.policy.readyBrokers(receiveTopics: topics), ["emqx"])
    XCTAssertEqual(Set(paths.values.compactMap { $0.configuration?.clientID }),
                   ["test:emqx", "test:hivemq", "test:mosquitto"])
  }

  func testPublicationNeverFallsBackToAnUnselectedBroker() async {
    let (pool, paths) = rig()
    await start(pool)
    paths["emqx"]!.emit(snapshot("emqx", generation: 2, topics: topics))
    paths["hivemq"]!.emit(snapshot("hivemq", topics: topics))
    let rejected = await pool.publish(publication(), brokerID: "emqx")
    XCTAssertEqual(rejected, .failed)
    XCTAssertEqual(paths["hivemq"]!.publications.count, 0)
    let accepted = await pool.publish(publication(), brokerID: "hivemq")
    XCTAssertEqual(accepted, .queued)
    XCTAssertEqual(paths["hivemq"]!.publications.count, 1)
  }

  func testTransportRechecksGenerationAfterPoolSelection() async {
    let (pool, paths) = rig()
    await start(pool)
    let emqx = paths["emqx"]!
    emqx.emit(snapshot("emqx", topics: topics))
    emqx.invalidateBeforePublish = true
    let result = await pool.publish(publication(), brokerID: "emqx")
    XCTAssertEqual(result, .failed)
    XCTAssertTrue(emqx.publications.isEmpty)
  }

  func testOldConnectionCallbacksCannotRestoreReadiness() async {
    let (pool, paths) = rig()
    await start(pool)
    paths["emqx"]!.emit(snapshot("emqx", generation: 2, topics: topics))
    paths["emqx"]!.emit(snapshot("emqx", generation: 1, topics: topics))
    let ready = await pool.readyGenerations(for: topics)
    XCTAssertEqual(ready, ["emqx": 2])
  }

  func testDisconnectRejectsOldLifecycleReadiness() async {
    let (pool, paths) = rig()
    await start(pool)
    let oldConfigurationID = paths["emqx"]!.configuration!.configurationID
    paths["emqx"]!.emit(snapshot("emqx", topics: topics))
    _ = await pool.readyGenerations(for: topics)
    pool.disconnect()
    let stopped = await pool.readyGenerations(for: topics)
    XCTAssertTrue(stopped.isEmpty)
    XCTAssertTrue(pool.policy.readyBrokers(receiveTopics: topics).isEmpty)
    await start(pool)
    paths["emqx"]!.emit(snapshot("emqx", topics: topics), configurationID: oldConfigurationID)
    let stale = await pool.readyGenerations(for: topics)
    XCTAssertTrue(stale.isEmpty)
    paths["emqx"]!.emit(snapshot("emqx", generation: 2, topics: topics))
    let fresh = await pool.readyGenerations(for: topics)
    XCTAssertEqual(fresh, ["emqx": 2])
  }

  func testIngressRequiresCurrentBrokerGenerationAndSubscribedTopic() async {
    let (pool, paths) = rig()
    let received = IngressRecorder()
    pool.onAuthenticatedIngress = { received.append($0) }
    await start(pool)
    paths["emqx"]!.emit(snapshot("emqx", generation: 2, topics: topics))
    for (broker, generation, topic) in [("emqx", Int64(1), "incoming"), ("emqx", 2, "other"),
                                       ("hivemq", 2, "incoming"), ("emqx", 2, "incoming")] {
      paths["emqx"]!.emitIngress(MqttAuthenticatedIngress(brokerID: broker, generation: generation,
        topic: topic, secretFingerprint: "secret-hash", payload: Data()))
    }
    _ = await pool.readyGenerations(for: topics)
    XCTAssertEqual(received.count, 1)
    pool.disconnect()
    paths["emqx"]!.emitIngress(MqttAuthenticatedIngress(brokerID: "emqx", generation: 2,
      topic: "incoming", secretFingerprint: "secret-hash", payload: Data()))
    _ = await pool.readyGenerations(for: topics)
    XCTAssertEqual(received.count, 1)
  }

  func testReconfigurationRejectsDelayedSnapshotsAndIngressEvenWithHigherGeneration() async {
    let (pool, paths) = rig()
    let received = IngressRecorder()
    pool.onAuthenticatedIngress = { received.append($0) }
    await start(pool)
    let emqx = paths["emqx"]!
    let previousID = emqx.configuration!.configurationID
    emqx.emit(snapshot("emqx", topics: topics))
    _ = await pool.readyGenerations(for: topics)
    await start(pool)
    emqx.emit(snapshot("emqx", generation: 20, topics: topics), configurationID: previousID)
    let stale = await pool.readyGenerations(for: topics)
    XCTAssertTrue(stale.isEmpty)
    emqx.emit(snapshot("emqx", topics: topics))
    emqx.onAuthenticatedIngress?(MqttAuthenticatedIngress(brokerID: "emqx", generation: 1,
      topic: "incoming", secretFingerprint: "secret-hash", payload: Data(), configurationID: previousID))
    let fresh = await pool.readyGenerations(for: topics)
    XCTAssertEqual(fresh, ["emqx": 1])
    XCTAssertEqual(received.count, 0)
  }

  func testDurableOutstandingIDsAreUnionedAcrossConnections() async {
    let (pool, paths) = rig()
    paths["emqx"]!.outstanding = ["first", "shared"]
    paths["hivemq"]!.outstanding = ["second", "shared"]
    let result = await pool.outstandingDurableMessageIds()
    XCTAssertEqual(result, ["first", "second", "shared"])
  }

  func testKeepaliveRequiresPINGRESPAndDoesNotExtendItsOwnDeadline() {
    var liveness = MqttConnectionLiveness()
    liveness.connected(at: 1_000)
    XCTAssertEqual(liveness.check(at: 15_999), .none)
    XCTAssertEqual(liveness.check(at: 16_000), .ping)
    liveness.received(at: 20_000, pingResponse: false)
    XCTAssertEqual(liveness.check(at: 45_999), .none)
    XCTAssertEqual(liveness.check(at: 46_000), .reconnect)
    liveness.connected(at: 50_000)
    XCTAssertEqual(liveness.check(at: 65_000), .ping)
    liveness.received(at: 65_100, pingResponse: true)
    XCTAssertEqual(liveness.check(at: 70_000), .none)
  }

  func testIncomingTrafficCannotSuppressClientKeepalive() {
    var liveness = MqttConnectionLiveness()
    liveness.connected(at: 1_000)
    liveness.received(at: 15_999, pingResponse: false)
    XCTAssertEqual(liveness.check(at: 16_000), .ping)
    liveness.sent(at: 17_000)
    XCTAssertEqual(liveness.check(at: 46_000), .reconnect)
  }

  func testOutgoingTrafficPostponesOnlyTheNextPing() {
    var liveness = MqttConnectionLiveness()
    liveness.connected(at: 1_000)
    liveness.sent(at: 15_000)
    XCTAssertEqual(liveness.check(at: 16_000), .none)
    XCTAssertEqual(liveness.check(at: 30_000), .ping)
    liveness.received(at: 31_000, pingResponse: true)
    XCTAssertEqual(liveness.check(at: 45_000), .ping)
  }

  func testLastFragmentPUBACKCannotCompleteWholeMessage() {
    let acknowledgements = MqttPublishAckGroup(packetCount: 3)
    XCTAssertFalse(acknowledgements.acknowledge(2))
    XCTAssertFalse(acknowledgements.acknowledge(2))
    XCTAssertFalse(acknowledgements.acknowledge(0))
    XCTAssertTrue(acknowledgements.acknowledge(1))
    XCTAssertFalse(acknowledgements.acknowledge(1))
  }

  func testFragmentAcknowledgementsSurviveRetryAndRejectUnknownIndex() {
    let acknowledgements = MqttPublishAckGroup(packetCount: 2)
    XCTAssertFalse(acknowledgements.acknowledge(-1))
    XCTAssertFalse(acknowledgements.acknowledge(2))
    XCTAssertFalse(acknowledgements.acknowledge(0))
    let retry = acknowledgements
    XCTAssertFalse(retry.acknowledge(0))
    XCTAssertTrue(retry.acknowledge(1))
    XCTAssertFalse(acknowledgements.acknowledge(1))
    let empty = MqttPublishAckGroup(packetCount: 0)
    XCTAssertFalse(empty.acknowledge(0))
    XCTAssertTrue(MqttPublishAckGroup(packetCount: 1).acknowledge(0))
  }

  private func snapshot(_ id: String, generation: Int64 = 1, topics: Set<String>) -> MqttBrokerPathSnapshot {
    MqttBrokerPathSnapshot(brokerID: id, generation: generation, connected: true, subscriptions: topics)
  }

  private func publication() -> MqttPathPublication {
    MqttPathPublication(topic: "outgoing", payload: Data("payload".utf8), generation: 1,
                        receiveTopics: topics, secretFingerprint: "secret-hash")
  }

  private func configuration() -> MqttBrokerPathConfiguration {
    MqttBrokerPathConfiguration(clientID: "test", serverLinks: [], phoneRoutes: [],
                                rendezvousSecrets: [:], rendezvousExpirations: [:])
  }

  private func start(_ pool: GalaxySSIMqttBrokerPool) async {
    pool.connect(configuration())
    _ = await pool.readyGenerations(for: topics)
  }

  private func rig() -> (GalaxySSIMqttBrokerPool, [String: FakeMqttBrokerPath]) {
    var paths: [String: FakeMqttBrokerPath] = [:]
    let pool = GalaxySSIMqttBrokerPool { endpoint in
      let path = FakeMqttBrokerPath(id: endpoint.id)
      paths[endpoint.id] = path
      return path
    }
    return (pool, paths)
  }
}

private final class IngressRecorder {
  private let lock = NSLock()
  private var packets: [MqttAuthenticatedIngress] = []
  var count: Int { lock.lock(); defer { lock.unlock() }; return packets.count }
  func append(_ packet: MqttAuthenticatedIngress) {
    lock.lock()
    packets.append(packet)
    lock.unlock()
  }
}

private final class FakeMqttBrokerPath: MqttBrokerPathTransport {
  var onPathState: ((MqttBrokerPathSnapshot) -> Void)?
  var onAuthenticatedIngress: ((MqttAuthenticatedIngress) -> Void)?
  var configuration: MqttBrokerPathConfiguration?
  var publications: [MqttPathPublication] = []
  var outstanding: Set<String> = []
  var invalidateBeforePublish = false
  private var snapshot: MqttBrokerPathSnapshot

  init(id: String) { snapshot = .init(brokerID: id, generation: 0, connected: false, subscriptions: []) }
  func configurePath(_ configuration: MqttBrokerPathConfiguration) { self.configuration = configuration }
  func emit(_ next: MqttBrokerPathSnapshot, configurationID: String? = nil) {
    snapshot = next
    snapshot.configurationID = configurationID ?? configuration?.configurationID ?? ""
    onPathState?(snapshot)
  }
  func emitIngress(_ ingress: MqttAuthenticatedIngress) {
    var scoped = ingress
    scoped.configurationID = configuration?.configurationID ?? ""
    onAuthenticatedIngress?(scoped)
  }
  func publishOnPath(_ publication: MqttPathPublication) async -> MqttPublishResult {
    if invalidateBeforePublish { snapshot.generation += 1 }
    guard MqttBrokerPathPolicy.accepts(publication, snapshot: snapshot, currentSecretFingerprint: "secret-hash") else { return .failed }
    publications.append(publication)
    return .queued
  }
  func outstandingDurableMessageIds() async -> Set<String> { outstanding }
  func disconnect() { snapshot.connected = false }
}
