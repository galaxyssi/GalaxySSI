import XCTest
@testable import GalaxySSI

final class MqttPeerRoutesTests: XCTestCase {
  func testReceiptWithoutLiveAttemptCommitsCompletionAndDuplicateIsIdempotent() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    let packet = try await f.packet()
    let first = try await f.receipts.accept(packet)
    XCTAssertEqual(first?.messageID, "message")
    XCTAssertNil(try f.outbox.entry(identity: f.entry.identity, messageID: "message"))
    let duplicate = try await f.receipts.accept(packet)
    XCTAssertEqual(duplicate?.receivedAt, first?.receivedAt)
    XCTAssertEqual(try f.outbox.completions.pending().count, 1)
    XCTAssertTrue(f.peer.pool.policy.diagnostics(now: f.peer.time).verifiedDelivery.values.allSatisfy { $0.samples == 0 })
  }

  func testRevocationBeforeReceiptCommitKeepsOutgoingMessage() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    let packet = try await f.packet()
    f.peer.binding.enabled = false
    try f.peer.routes.replace([f.peer.binding])
    do { _ = try await f.receipts.accept(packet); XCTFail("Revoked receipt must fail") }
    catch MqttRouteError.identityChanged { }
    XCTAssertNotNil(try f.outbox.entry(identity: f.entry.identity, messageID: "message"))
    XCTAssertTrue(try f.outbox.completions.pending().isEmpty)
  }

  func testReceiptHashMismatchCannotDeleteOutboxAfterRestart() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    let bad = try MqttDeliveryEnvelope.Frame(message: .init(messageID: "message", contentHash: String(repeating: "e", count: 64),
      sender: f.entry.identity.local, receiver: f.entry.identity.remote, traffic: "message"), attempt: f.frame.attempt)
    let packet = try await f.packet(frame: bad)
    do { _ = try await f.receipts.accept(packet); XCTFail("Wrong hash must fail") }
    catch MqttRouteError.unsolicitedAcknowledgement { }
    XCTAssertNotNil(try f.outbox.entry(identity: f.entry.identity, messageID: "message"))
  }

  func testCompletionWriteFailureDoesNotConfirmLiveDispatch() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    try await f.peer.handshake()
    _ = try await f.dispatch.submit(topic: f.peer.binding.sendTopic, delivery: XCTUnwrap(f.peer.prepare()))
    let frame = try XCTUnwrap(f.publications.first).frame
    let packet = try await f.packet(frame: frame)
    try f.storage.execute("CREATE TRIGGER fail_completion BEFORE INSERT ON mqtt_delivery_completions BEGIN SELECT RAISE(ABORT,'forced'); END")
    do { _ = try await f.receipts.accept(packet); XCTFail("Storage failure must propagate") }
    catch { XCTAssertTrue(error is MqttChunkStorageError) }
    XCTAssertTrue(f.peer.pool.policy.pending(peer: f.peer.binding.scope, messageID: "message"))
    XCTAssertTrue(try f.outbox.completions.pending().isEmpty)
    XCTAssertNotNil(try f.outbox.entry(identity: f.entry.identity, messageID: "message"))
    try f.storage.execute("DROP TRIGGER fail_completion")
    let accepted = try await f.receipts.accept(packet)
    XCTAssertNotNil(accepted)
    XCTAssertFalse(f.peer.pool.policy.pending(peer: f.peer.binding.scope, messageID: "message"))
  }

  func testUnknownPhysicalAttemptCancelsLogicalRetryWithoutInventingRTT() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    try await f.peer.handshake()
    _ = try await f.dispatch.submit(topic: f.peer.binding.sendTopic, delivery: XCTUnwrap(f.peer.prepare()))
    let packet = try await f.packet()
    let result = try await f.receipts.accept(packet)
    XCTAssertNotNil(result)
    XCTAssertFalse(f.peer.pool.policy.pending(peer: f.peer.binding.scope, messageID: "message"))
    XCTAssertTrue(f.peer.pool.policy.diagnostics(now: f.peer.time).verifiedDelivery.values.allSatisfy { $0.samples == 0 })
  }

  func testApprovedOfflineBindingCanCommitOutboxWithoutRouteReadiness() throws {
    let fixture = try PeerRoutesFixture()
    let identity = try MqttBusinessIdentity(fixture.binding)
    XCTAssertFalse(fixture.routes.isReady(scope: identity.scope))
    let result = try fixture.routes.withOutgoing(identity: identity, topics: [fixture.binding.sendTopic]) { "committed" }
    XCTAssertEqual(result, "committed")
    XCTAssertTrue(fixture.path.publications.isEmpty)
  }

  func testRevocationAndKeyRotationPreventQueuedCommit() throws {
    let fixture = try PeerRoutesFixture()
    let identity = try MqttBusinessIdentity(fixture.binding)
    var called = false
    fixture.binding.enabled = false
    try fixture.routes.replace([fixture.binding])
    XCTAssertThrowsError(try fixture.routes.withOutgoing(identity: identity, topics: [fixture.binding.sendTopic]) { called = true })
    fixture.binding.enabled = true
    fixture.binding.secret = Data(repeating: 8, count: 32).base64URLEncodedString()
    try fixture.routes.replace([fixture.binding])
    XCTAssertThrowsError(try fixture.routes.withOutgoing(identity: identity, topics: [fixture.binding.sendTopic]) { called = true })
    XCTAssertFalse(called)
  }

  func testOutgoingCommitRequiresEveryTopicToBelongToCurrentPeer() throws {
    let fixture = try PeerRoutesFixture()
    let identity = try MqttBusinessIdentity(fixture.binding)
    var called = false
    XCTAssertThrowsError(try fixture.routes.withOutgoing(identity: identity, topics: []) { called = true })
    XCTAssertThrowsError(try fixture.routes.withOutgoing(identity: identity,
      topics: [fixture.binding.sendTopic, String(repeating: "x", count: 43)]) { called = true })
    XCTAssertFalse(called)
  }

  func testConnectedBrokerIsNotReadyUntilMatchingPeerAcknowledgement() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    XCTAssertFalse(fixture.routes.isReady(scope: fixture.binding.scope))
    XCTAssertNil(try fixture.prepare())
    try await fixture.handshake()
    XCTAssertTrue(fixture.routes.readyForTopic(fixture.binding.sendTopic))
    let delivery = try XCTUnwrap(fixture.prepare())
    XCTAssertTrue(delivery.authorized("emqx", 1))
    XCTAssertFalse(delivery.authorized("hivemq", 1))
    XCTAssertFalse(delivery.authorized("emqx", 2))
    XCTAssertEqual(fixture.readyEvents, [fixture.binding.scope])
  }

  func testApprovalEnablesWarmHandshakeAndRevocationInvalidatesPreparedPacket() async throws {
    let fixture = try PeerRoutesFixture(enabled: false)
    await fixture.start()
    try await fixture.handshake()
    XCTAssertFalse(fixture.routes.isReady(scope: fixture.binding.scope))
    XCTAssertTrue(fixture.readyEvents.isEmpty)
    fixture.binding.enabled = true
    try fixture.routes.replace([fixture.binding])
    XCTAssertEqual(fixture.readyEvents, [fixture.binding.scope])
    let delivery = try XCTUnwrap(fixture.prepare())
    let frame = try MqttDeliveryEnvelope.Frame(message: delivery.message,
      attempt: .init(attemptID: String(repeating: "f", count: 32), brokerID: "emqx", generation: 1))
    var packet = try MqttSealedPathPublication(publication: .init(topic: fixture.binding.sendTopic,
      payload: delivery.encodeAttempt(frame), frame: frame, receiveTopics: delivery.receiveTopics,
      secretFingerprint: delivery.secretFingerprint, authorized: delivery.authorized), completed: { _ in })
    packet.configurationID = fixture.snapshot.configurationID
    XCTAssertTrue(packet.accepts(snapshot: fixture.snapshot, secretFingerprint: fixture.binding.secretFingerprint))
    fixture.binding.enabled = false
    try fixture.routes.replace([fixture.binding])
    XCTAssertFalse(delivery.authorized("emqx", 1))
    XCTAssertFalse(packet.accepts(snapshot: fixture.snapshot, secretFingerprint: fixture.binding.secretFingerprint))
  }

  func testKeyReplacementRetiresOldClosuresAndRequiresNewHandshake() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    try await fixture.handshake()
    let old = try XCTUnwrap(fixture.prepare())
    let oldBinding = fixture.binding
    fixture.binding.secret = Data(repeating: 8, count: 32).base64URLEncodedString()
    try fixture.routes.replace([fixture.binding])
    XCTAssertFalse(old.authorized("emqx", 1))
    XCTAssertFalse(fixture.routes.isReady(scope: fixture.binding.scope))
    XCTAssertNil(try fixture.prepare())
    let obsolete = try fixture.ingress(["body": "stale"], binding: oldBinding)
    do {
      _ = try await fixture.routes.receive(obsolete)
      XCTFail("An old relationship must not authenticate as its replacement")
    } catch MqttRouteError.identityChanged { }
  }

  func testIngressIsBoundToActualTopicKeyConfigurationAndGeneration() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    let original = try fixture.ingress(["body": "business"])
    var wrongTopic = original
    wrongTopic.topic = String(repeating: "x", count: 43)
    var wrongKey = original
    wrongKey.secretFingerprint = String(repeating: "c", count: 64)
    var wrongGeneration = original
    wrongGeneration.generation = 2
    var wrongConfiguration = original
    wrongConfiguration.configurationID = "obsolete"
    for packet in [wrongTopic, wrongKey, wrongGeneration, wrongConfiguration] {
      do { _ = try await fixture.routes.receive(packet); XCTFail("Unbound ingress must be rejected") }
      catch { XCTAssertTrue(error is MqttRouteError) }
    }
  }

  func testBusinessCommitRechecksBindingAfterIngressParsing() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    let reception = try await fixture.routes.receive(fixture.ingress(["body": "business"]))
    XCTAssertFalse(reception.handled)
    let packet = try XCTUnwrap(reception.packet)
    XCTAssertTrue(fixture.routes.isCurrent(packet))
    var commits = 0
    try fixture.routes.withCurrent(packet) { commits += 1 }
    fixture.binding.enabled = false
    try fixture.routes.replace([fixture.binding])
    XCTAssertFalse(fixture.routes.isCurrent(packet))
    XCTAssertThrowsError(try fixture.routes.withCurrent(packet) { commits += 1 })
    XCTAssertEqual(commits, 1)
  }

  func testDisabledPairCannotForwardBusinessIngress() async throws {
    let fixture = try PeerRoutesFixture(enabled: false)
    await fixture.start()
    do {
      _ = try await fixture.routes.receive(fixture.ingress(["body": "business"]))
      XCTFail("Approval is required for business ingress")
    } catch MqttRouteError.identityChanged { }
  }

  func testRemoteResumeRespondsOnIngressPathWithoutDeclaringApplicationReady() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    let response = try await fixture.routes.receive(fixture.ingress(fixture.remote().wire()))
    XCTAssertTrue(response.handled)
    XCTAssertFalse(fixture.routes.isReady(scope: fixture.binding.scope))
    let packet = try XCTUnwrap(fixture.path.publications.last)
    let value = try XCTUnwrap(JSONSerialization.jsonObject(with: packet.payload) as? [String: Any])
    XCTAssertEqual(value["type"] as? String, "link_resume_ack")
    XCTAssertEqual(packet.generation, 1)
    XCTAssertEqual(packet.topic, fixture.binding.sendTopic)
    _ = try await fixture.routes.receive(fixture.ingress(fixture.remote().wire()))
    XCTAssertEqual(fixture.path.publications.count, 1)
  }

  func testReceiveTopicRotationInvalidatesHandshakeEvenWithSameBrokerGeneration() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    try await fixture.handshake()
    let old = try XCTUnwrap(fixture.prepare())
    fixture.binding.receiveTopics.insert(String(repeating: "c", count: 43))
    try fixture.routes.replace([fixture.binding])
    await fixture.emit(topics: fixture.binding.receiveTopics)
    XCTAssertFalse(fixture.routes.isReady(scope: fixture.binding.scope))
    XCTAssertFalse(old.authorized("emqx", 1))
    await fixture.routes.maintenance()
    XCTAssertEqual(fixture.path.publications.count, 2)
  }

  func testRetirementPreservesEpochAndRemovesOutgoingLookup() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    try await fixture.handshake()
    let first = try fixture.local()
    try fixture.routes.replace([])
    XCTAssertEqual(fixture.routes.blockedReason(topic: fixture.binding.sendTopic), "missing_binding")
    XCTAssertNil(try fixture.persistence.cached(peer: fixture.binding.scope, sender: fixture.binding.receiver,
      receiver: fixture.binding.sender, now: fixture.time))
    try fixture.routes.replace([fixture.binding])
    await fixture.routes.maintenance()
    XCTAssertGreaterThan(try fixture.local().epoch, first.epoch)
  }

  func testMaintenanceRotatesBoundedBatchesAndHonorsUrgentRequest() async throws {
    let fixture = try PeerRoutesFixture()
    let bindings = (0..<20).map { index -> MqttPeerBinding in
      var value = fixture.binding
      value.scope = "peer-\(index)"
      value.sendTopic = Data(repeating: UInt8(index + 10), count: 32).base64URLEncodedString()
      value.sendTopics = [value.sendTopic]
      return value
    }
    try fixture.routes.replace(bindings)
    await fixture.start()
    await fixture.routes.maintenance(limit: 4)
    XCTAssertEqual(fixture.path.publications.count, 4)
    await fixture.routes.maintenance(limit: 4)
    XCTAssertEqual(fixture.path.publications.count, 8)
    fixture.routes.request("peer-19")
    await fixture.routes.maintenance(limit: 1)
    XCTAssertEqual(fixture.path.publications.last?.topic, bindings[19].sendTopic)
    await fixture.routes.maintenance(limit: 0)
    XCTAssertEqual(fixture.path.publications.count, 9)
  }

  func testInvalidReplacementDoesNotRemoveExistingBindings() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    try await fixture.handshake()
    var duplicate = fixture.binding
    duplicate.scope = "other"
    XCTAssertThrowsError(try fixture.routes.replace([fixture.binding, duplicate]))
    XCTAssertTrue(fixture.routes.isReady(scope: fixture.binding.scope))
    var invalid = fixture.binding
    invalid.receiveTopics = []
    XCTAssertThrowsError(try fixture.routes.replace([invalid]))
    XCTAssertTrue(fixture.routes.isReady(scope: fixture.binding.scope))
  }

  func testUnreadablePersistenceBacksOffAndDoesNotEmitSuccessfulHandshake() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    let key = try fixture.persistence.storageKey(fixture.binding.scope)
    fixture.defaults.set(Data([0]), forKey: key + ".encrypted.v1")
    await fixture.routes.maintenance()
    await fixture.routes.maintenance()
    XCTAssertEqual(fixture.failures, 1)
    XCTAssertTrue(fixture.path.publications.isEmpty)
    fixture.time += 5000
    await fixture.routes.maintenance()
    XCTAssertEqual(fixture.failures, 2)
  }

  func testBlockedRecoveryUsesVerifiedPeerHistoryAndCooldownAfterGenerationChange() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    try await fixture.handshake()
    await fixture.emit(topics: fixture.binding.receiveTopics, generation: 2)
    XCTAssertFalse(fixture.routes.readyForTopic(fixture.binding.sendTopic))
    XCTAssertFalse(fixture.routes.recoverBlockedSend(topic: fixture.binding.sendTopic))
    fixture.time += 30_000
    XCTAssertTrue(fixture.routes.recoverBlockedSend(topic: fixture.binding.sendTopic))
    XCTAssertFalse(fixture.routes.recoverBlockedSend(topic: fixture.binding.sendTopic))
    await fixture.routes.maintenance()
    XCTAssertEqual(fixture.path.publications.last?.generation, 2)
    XCTAssertEqual(fixture.routes.blockedReason(topic: fixture.binding.sendTopic), "unconfirmed_local_epoch")
    fixture.time += 119_999
    XCTAssertFalse(fixture.routes.recoverBlockedSend(topic: fixture.binding.sendTopic))
    fixture.time += 1
    XCTAssertTrue(fixture.routes.recoverBlockedSend(topic: fixture.binding.sendTopic))
  }
}

private final class PeerRoutesFixture {
  let suite: String
  let defaults: UserDefaults
  let persistence: MqttRouteState
  let pool: GalaxySSIMqttBrokerPool
  let path: FakeMqttBrokerPath
  var binding: MqttPeerBinding
  var time: Int64 = 1000
  var readyEvents: [String] = []
  var failures = 0
  private(set) var snapshot = MqttBrokerPathSnapshot(brokerID: "emqx", generation: 1, connected: true, subscriptions: [])
  lazy var routes = MqttPeerRoutes(pool: pool, persistence: persistence, wall: { [weak self] in self?.time ?? 0 },
    now: { [weak self] in self?.time ?? 0 }, onReady: { [weak self] in self?.readyEvents.append($0) },
    onFailure: { [weak self] _, _ in self?.failures += 1 })

  init(enabled: Bool = true) throws {
    let suite = "PeerRoutes-\(UUID().uuidString)"
    self.suite = suite
    let defaults = UserDefaults(suiteName: suite)!
    self.defaults = defaults
    persistence = MqttRouteState(defaults: defaults, secrets: InMemorySecretStore())
    let binding = MqttPeerBinding(scope: "pair", sender: String(repeating: "a", count: 64), receiver: String(repeating: "b", count: 64),
      secret: Data(repeating: 7, count: 32).base64URLEncodedString(), sendTopic: String(repeating: "s", count: 43),
      sendTopics: [String(repeating: "s", count: 43)], receiveTopics: [String(repeating: "r", count: 43)], enabled: enabled)
    self.binding = binding
    var created: [String: FakeMqttBrokerPath] = [:]
    let pool = GalaxySSIMqttBrokerPool { endpoint in
      let value = FakeMqttBrokerPath(id: endpoint.id)
      created[endpoint.id] = value
      return value
    }
    self.pool = pool
    let path = created["emqx"]!
    self.path = path
    path.currentSecretFingerprint = binding.secretFingerprint
    pool.onPathState = { [weak self] in self?.routes.synchronize($0) }
    try routes.replace([binding])
  }
  deinit { defaults.removePersistentDomain(forName: suite) }
  func start() async {
    pool.connect(.init(clientID: "routes", serverLinks: [], phoneRoutes: [], rendezvousSecrets: [:], rendezvousExpirations: [:]))
    _ = await pool.readyGenerations(for: binding.receiveTopics)
    await emit(topics: binding.receiveTopics)
  }
  func emit(topics: Set<String>, generation: Int64 = 1) async {
    snapshot.generation = generation
    snapshot.subscriptions = topics
    snapshot.configurationID = path.configuration?.configurationID ?? ""
    path.emit(snapshot)
    _ = await pool.readyGenerations(for: topics)
  }
  func ingress(_ payload: [String: Any], binding: MqttPeerBinding? = nil) throws -> MqttAuthenticatedIngress {
    let binding = binding ?? self.binding
    return MqttAuthenticatedIngress(brokerID: "emqx", generation: snapshot.generation, topic: binding.receiveTopics.sorted()[0],
      secretFingerprint: binding.secretFingerprint, payload: try GalaxySSILinkProtocol.jsonData(payload),
      configurationID: snapshot.configurationID)
  }
  func remote() -> MqttRouteAdvertisement {
    MqttRouteAdvertisement(sender: binding.receiver, receiver: binding.sender, epoch: 2000,
      resumeId: String(repeating: "c", count: 32), issuedAt: time, expiresAt: time + 300_000,
      receiveBrokers: ["emqx"], packetBytes: 1_048_576)
  }
  func local() throws -> MqttRouteAdvertisement {
    let packet = try XCTUnwrap(path.publications.last)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: packet.payload) as? [String: Any])
    return try MqttRouteAdvertisement.parseVerified(object, sender: binding.sender, receiver: binding.receiver, now: time)
  }
  func handshake() async throws {
    await routes.maintenance()
    let ours = try local()
    _ = try await routes.receive(ingress(["type": "link_resume_ack", "advertisement": remote().wire(),
      "acknowledged_route_epoch": ours.epoch, "acknowledged_resume_id": ours.resumeId, "acknowledged_digest": try ours.digest()]))
  }
  func prepare() throws -> MqttDeliveryDispatch.Delivery? {
    try routes.prepareDelivery(topic: binding.sendTopic,
      wire: GalaxySSILinkProtocol.jsonData(["scheme": "signal", "from": "sender", "to": "receiver", "body": "AA=="]),
      messageID: "message", traffic: .message)
  }
}

private final class ReceiptBridgeFixture {
  let peer: PeerRoutesFixture
  let storage: ChunkFixture
  let outbox: MqttBusinessOutbox
  let entry: MqttBusinessOutbox.Entry
  let frame: MqttDeliveryEnvelope.Frame
  var publications: [MqttDeliveryDispatch.Publication] = []
  lazy var dispatch = MqttDeliveryDispatch(policy: peer.pool.policy, publish: { [weak self] packet in
    self?.publications.append(packet); return true
  }, brokerCompleted: { _, _ in }, now: { [weak self] in self?.peer.time ?? 0 })
  lazy var receipts = MqttBusinessReceipts(routes: peer.routes, outbox: outbox, dispatcher: dispatch,
    now: { Date(timeIntervalSince1970: 1) })

  init() throws {
    peer = try PeerRoutesFixture()
    storage = try ChunkFixture()
    outbox = try MqttBusinessOutbox(fileURL: storage.url, secrets: storage.secrets)
    let identity = try MqttBusinessIdentity(peer.binding)
    let wire = try GalaxySSILinkProtocol.jsonData(["scheme": "signal", "from": "sender", "to": "receiver", "body": "AA=="])
    let date = Date(timeIntervalSince1970: 1)
    let message = PendingLinkMessage(messageId: "message", topic: peer.binding.sendTopic, wirePayload: String(decoding: wire, as: UTF8.self),
      status: "queued", attempts: 0, nextAttemptAt: date, createdAt: date, updatedAt: date)
    try outbox.enqueue(identity: identity, message: message, traffic: .message)
    entry = try XCTUnwrap(outbox.entry(identity: identity, messageID: "message"))
    frame = try MqttDeliveryEnvelope.Frame(message: .init(messageID: "message", contentHash: entry.wireHash,
      sender: identity.local, receiver: identity.remote, traffic: "message"),
      attempt: .init(attemptID: String(repeating: "d", count: 32), brokerID: "emqx", generation: 1))
  }

  func packet(frame: MqttDeliveryEnvelope.Frame? = nil) async throws -> MqttPeerRoutes.VerifiedPacket {
    let frame = frame ?? self.frame
    let reception = try await peer.routes.receive(peer.ingress(frame.receiptAfterStore(messageID: "message", wireHash: frame.message.contentHash)))
    return try XCTUnwrap(reception.packet)
  }
}
