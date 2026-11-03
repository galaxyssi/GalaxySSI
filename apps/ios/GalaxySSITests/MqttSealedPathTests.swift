import XCTest
@testable import GalaxySSI

final class MqttSealedPathTests: XCTestCase {
  private let secret = Data(repeating: 7, count: 32).base64URLEncodedString()
  private let topic = String(repeating: "a", count: 43)
  private let inbox = String(repeating: "b", count: 43)

  func testEncryptedSizeEstimateMatchesActualPaddingBuckets() throws {
    for size in [0, 1, 1019, 1020, 16_379, 16_380, 65_531, 65_532, 131_067, 131_068, 262_139, 262_140, 524_283] {
      let sealed = try GalaxySSILinkProtocol.sealWirePacket(Data(repeating: 1, count: size), secret: secret)
      XCTAssertEqual(try GalaxySSILinkProtocol.sealedWirePacketByteCount(payloadBytes: size), sealed.count)
    }
    for size in [-1, 524_284, Int.max] {
      XCTAssertThrowsError(try GalaxySSILinkProtocol.sealedWirePacketByteCount(payloadBytes: size))
    }
  }

  func testSignalFactorySealsEachAttemptOnceAndBoundsLongestMetadata() throws {
    let delivery = try makeDelivery()
    for broker in MqttRouteProtocol.brokerIDs {
      for generation in [Int64(1), MqttRouteProtocol.maximumInteger] {
        let frame = try MqttDeliveryEnvelope.Frame(message: delivery.message,
          attempt: .init(attemptID: String(repeating: "f", count: 32), brokerID: broker, generation: generation))
        let payload = try delivery.encodeAttempt(frame)
        let opened = try GalaxySSILinkProtocol.openWirePacket(payload, secret: secret)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: opened) as? [String: Any])
        let verified = try MqttDeliveryEnvelope.parseVerifiedFrame(object, sender: frame.message.sender,
          receiver: frame.message.receiver, ingressBroker: broker)
        XCTAssertEqual(verified, frame)
        XCTAssertEqual(object["body"] as? String, "AA==")
        XCTAssertLessThanOrEqual(try MqttDeliveryDispatch.packetBytes(topic: topic, payloadBytes: payload.count), delivery.sizeBound)
      }
    }
    XCTAssertEqual(delivery.secretFingerprint, MqttRouteProtocol.digest(Data(secret.utf8)))
  }

  func testFactoryRejectsWrongHashInvalidSecretAndOversizedWire() throws {
    let base = try makeDelivery()
    let changed = try MqttDeliveryEnvelope.Message(messageID: "m", contentHash: String(repeating: "d", count: 64),
      sender: base.message.sender, receiver: base.message.receiver, traffic: "message")
    XCTAssertThrowsError(try MqttSignalDelivery.make(peer: "pair", topic: topic, wire: wire(), message: changed,
      secret: secret, receiveTopics: [inbox], authorized: { _, _ in true }))
    XCTAssertThrowsError(try MqttSignalDelivery.make(peer: "pair", topic: topic, wire: wire(), message: base.message,
      secret: "invalid", receiveTopics: [inbox], authorized: { _, _ in true }))
    XCTAssertThrowsError(try makeDelivery(body: String(repeating: "a", count: 524_280)))
  }

  func testFactoryCannotEncodeDifferentMessageInPreparedDelivery() throws {
    let delivery = try makeDelivery()
    let other = try MqttDeliveryEnvelope.Message(messageID: "other", contentHash: delivery.message.contentHash,
      sender: delivery.message.sender, receiver: delivery.message.receiver, traffic: "message")
    let frame = try MqttDeliveryEnvelope.Frame(message: other,
      attempt: .init(attemptID: String(repeating: "c", count: 32), brokerID: "emqx", generation: 1))
    XCTAssertThrowsError(try delivery.encodeAttempt(frame))
  }

  func testSealedAuthorizationFencesBrokerGenerationConfigurationTopicsAndSecret() throws {
    var packet = try publication()
    packet.configurationID = "current"
    var snapshot = MqttBrokerPathSnapshot(brokerID: "emqx", generation: 1, connected: true, subscriptions: [inbox])
    snapshot.configurationID = "current"
    let fingerprint = packet.publication.secretFingerprint
    XCTAssertTrue(packet.accepts(snapshot: snapshot, secretFingerprint: fingerprint))
    XCTAssertFalse(packet.accepts(snapshot: snapshot, secretFingerprint: String(repeating: "d", count: 64)))
    snapshot.generation = 2
    XCTAssertFalse(packet.accepts(snapshot: snapshot, secretFingerprint: fingerprint))
    snapshot.generation = 1
    snapshot.configurationID = "replacement"
    XCTAssertFalse(packet.accepts(snapshot: snapshot, secretFingerprint: fingerprint))
    snapshot.configurationID = "current"
    snapshot.brokerID = "hivemq"
    XCTAssertFalse(packet.accepts(snapshot: snapshot, secretFingerprint: fingerprint))
    snapshot.brokerID = "emqx"
    snapshot.subscriptions = []
    XCTAssertFalse(packet.accepts(snapshot: snapshot, secretFingerprint: fingerprint))
  }

  func testPoolUsesSealedTransportAndDoesNotReencodePayload() async throws {
    let (pool, paths) = await rig()
    let packet = try publication()
    let result = await pool.publishSealed(packet)
    XCTAssertTrue(result.accepted)
    XCTAssertEqual(paths["emqx"]?.sealedPublications.count, 1)
    XCTAssertTrue(paths.values.allSatisfy { $0.publications.isEmpty })
    let forwarded = try XCTUnwrap(paths["emqx"]?.sealedPublications.first)
    XCTAssertEqual(forwarded.publication.payload, packet.publication.payload)
    XCTAssertEqual(forwarded.configurationID, paths["emqx"]?.configuration?.configurationID)
    let decoded = try GalaxySSILinkProtocol.openWirePacket(forwarded.publication.payload, secret: secret)
    XCTAssertNotNil(try JSONSerialization.jsonObject(with: decoded) as? [String: Any])
  }

  func testPathRepeatsGenerationAndSecretGateAfterPoolSelection() async throws {
    let (pool, paths) = await rig()
    let packet = try publication()
    paths["emqx"]?.currentSecretFingerprint = String(repeating: "d", count: 64)
    let rotated = await pool.publishSealed(packet)
    XCTAssertEqual(rotated, .failed)
    paths["emqx"]?.currentSecretFingerprint = packet.publication.secretFingerprint
    paths["emqx"]?.invalidateBeforePublish = true
    let stale = await pool.publishSealed(packet)
    XCTAssertEqual(stale, .failed)
    XCTAssertTrue(paths.values.allSatisfy { $0.sealedPublications.isEmpty })
  }

  func testPoolCannotPublishAfterDisconnect() async throws {
    let (pool, _) = await rig()
    pool.disconnect()
    _ = await pool.readyGenerations(for: [inbox])
    let result = await pool.publishSealed(try publication())
    XCTAssertEqual(result, .failed)
  }

  func testRealClientRejectsUnconfiguredSealedPublish() async throws {
    let client = GalaxySSIMqttClient()
    let result = await client.publishSealedOnPath(try publication())
    XCTAssertEqual(result, .failed)
    client.disconnect()
  }

  func testCompletionIsExactlyOnceAcrossFailureAndSuccessRace() {
    let events = PhysicalCompletionRecorder()
    let completion = MqttPhysicalCompletion { events.append($0) }
    DispatchQueue.concurrentPerform(iterations: 100) { completion.finish($0 % 2 == 0) }
    XCTAssertEqual(events.values.count, 1)
    completion.finish(true)
    XCTAssertEqual(events.values.count, 1)
  }

  func testPoolDispatcherConnectsPubackCallbackWithoutTreatingItAsPeerReceipt() async throws {
    let (pool, paths) = await rig()
    let events = PhysicalCompletionRecorder()
    let acknowledged = expectation(description: "Broker completion reaches dispatcher")
    let dispatch = pool.makeDeliveryDispatcher(brokerCompleted: { _, value in events.append(value); acknowledged.fulfill() }, now: { 1000 })
    let delivery = try makeDelivery()
    _ = try await dispatch.submit(topic: topic, delivery: delivery)
    let packets = paths.values.flatMap(\.sealedPublications)
    let packet = try XCTUnwrap(packets.first)
    XCTAssertEqual(packets.count, 1)
    packet.completed(true)
    await fulfillment(of: [acknowledged], timeout: 2)
    XCTAssertEqual(events.values, [true])
    XCTAssertTrue(pool.policy.pending(peer: "pair", messageID: delivery.message.messageID))
    XCTAssertEqual(pool.policy.diagnostics(now: 1000).inflightPackets, 0)
    let state = await dispatch.diagnostics()
    XCTAssertEqual(state.queuedCopies, 2)
    pool.disconnect()
    _ = await pool.readyGenerations(for: [inbox])
    await dispatch.close()
  }

  func testPoolDispatcherReceivesDisconnectFailureWithoutHanging() async throws {
    let (pool, _) = await rig()
    let events = PhysicalCompletionRecorder()
    let failed = expectation(description: "Physical disconnect finishes submission")
    // A control publishes all eligible copies immediately, with no delayed hedge left after failure.
    let dispatch = pool.makeDeliveryDispatcher(brokerCompleted: { _, value in events.append(value); failed.fulfill() }, now: { 1000 })
    _ = try await dispatch.submit(topic: topic, delivery: makeDelivery(traffic: "control"))
    pool.disconnect()
    _ = await pool.readyGenerations(for: [inbox])
    await fulfillment(of: [failed], timeout: 2)
    XCTAssertEqual(events.values, [false])
    XCTAssertEqual(pool.policy.diagnostics(now: 1000).inflightPackets, 0)
    await dispatch.close()
  }

  private func wire(body: String = "AA==") throws -> Data {
    try JSONSerialization.data(withJSONObject: ["scheme": "signal", "from": "sender", "to": "receiver", "body": body])
  }
  private func makeDelivery(body: String = "AA==", traffic: String = "message") throws -> MqttDeliveryDispatch.Delivery {
    let data = try wire(body: body)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let message = try MqttDeliveryEnvelope.Message(messageID: "message", contentHash: MqttDeliveryEnvelope.contentHash(object),
      sender: String(repeating: "a", count: 64), receiver: String(repeating: "b", count: 64), traffic: traffic)
    return try MqttSignalDelivery.make(peer: "pair", topic: topic, wire: data, message: message, secret: secret,
      receiveTopics: [inbox], authorized: { _, _ in true })
  }
  private func publication() throws -> MqttSealedPathPublication {
    let delivery = try makeDelivery()
    let frame = try MqttDeliveryEnvelope.Frame(message: delivery.message,
      attempt: .init(attemptID: String(repeating: "c", count: 32), brokerID: "emqx", generation: 1))
    return try .init(publication: .init(topic: topic, payload: delivery.encodeAttempt(frame), frame: frame,
      receiveTopics: [inbox], secretFingerprint: delivery.secretFingerprint, authorized: delivery.authorized), completed: { _ in })
  }
  private func rig() async -> (GalaxySSIMqttBrokerPool, [String: FakeMqttBrokerPath]) {
    var paths: [String: FakeMqttBrokerPath] = [:]
    let pool = GalaxySSIMqttBrokerPool { endpoint in
      let path = FakeMqttBrokerPath(id: endpoint.id)
      path.currentSecretFingerprint = MqttRouteProtocol.digest(Data(secret.utf8))
      paths[endpoint.id] = path
      return path
    }
    pool.connect(.init(clientID: "test", serverLinks: [], phoneRoutes: [], rendezvousSecrets: [:], rendezvousExpirations: [:]))
    _ = await pool.readyGenerations(for: [inbox])
    for (broker, path) in paths { path.emit(.init(brokerID: broker, generation: 1, connected: true, subscriptions: [inbox])) }
    _ = await pool.readyGenerations(for: [inbox])
    _ = pool.policy.acceptVerifiedResume(peer: "pair", route: .init(epoch: 1, receiveBrokers: MqttRouteProtocol.brokerIDs,
      packetBytes: 1_048_576, chunkACKs: true, expiresAt: 300_000), now: 1000)
    return (pool, paths)
  }
}

private final class PhysicalCompletionRecorder {
  private let lock = NSLock()
  private var events: [Bool] = []
  var values: [Bool] { lock.lock(); defer { lock.unlock() }; return events }
  func append(_ value: Bool) { lock.lock(); events.append(value); lock.unlock() }
}
