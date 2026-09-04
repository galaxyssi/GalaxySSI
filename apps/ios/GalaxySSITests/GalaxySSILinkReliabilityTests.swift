import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSILinkReliabilityTests: XCTestCase {
  func testTransportPrivacyRequiresExplicitAuthorizationForBackgroundCognition() {
    let cognition: [String: Any] = [
      "type": "text",
      "conversation_id": "global-cognition:task-1"
    ]
    let evolution: [String: Any] = [
      "type": "text",
      "conversation_id": "self-evolution:task-1"
    ]
    let autonomous: [String: Any] = [
      "type": "text",
      "conversation_id": "global-autonomous:run-1"
    ]

    XCTAssertTrue(GalaxySSITransportPrivacyPolicy.isLocalOnly(cognition))
    XCTAssertFalse(GalaxySSITransportPrivacyPolicy.isLocalOnly(
      cognition,
      trustedBackgroundCognitionAuthorized: true
    ))
    XCTAssertTrue(GalaxySSITransportPrivacyPolicy.isLocalOnly(autonomous))
    XCTAssertFalse(GalaxySSITransportPrivacyPolicy.isLocalOnly(
      autonomous,
      trustedBackgroundCognitionAuthorized: true
    ))
    XCTAssertTrue(GalaxySSITransportPrivacyPolicy.isLocalOnly(
      evolution,
      trustedBackgroundCognitionAuthorized: true
    ))
  }

  func testGlobalAgentSettingsDecodePairedAuthorizationAsOptIn() throws {
    let defaults = try JSONDecoder().decode(GlobalAgentSettings.self, from: Data("{}".utf8))
    XCTAssertFalse(defaults.allowPairedAgentCognition)

    var authorized = defaults
    authorized.allowPairedAgentCognition = true
    let restored = try JSONDecoder().decode(
      GlobalAgentSettings.self,
      from: JSONEncoder().encode(authorized)
    )
    XCTAssertTrue(restored.allowPairedAgentCognition)
  }

  func testOutboxRetriesAndAcknowledgesMessages() {
    let store = makeDeliveryStore()
    let now = Date(timeIntervalSince1970: 100)

    store.enqueue(messageId: "m1", topic: "topic/up", wirePayload: "{\"type\":\"text\"}", now: now)
    XCTAssertEqual(store.pending(now: now).map(\.messageId), ["m1"])

    store.markAttempt(messageId: "m1", now: now)
    XCTAssertTrue(store.pending(now: now).isEmpty)
    XCTAssertEqual(store.pending(now: now.addingTimeInterval(2)).map(\.messageId), ["m1"])

    store.markPublished(messageId: "m1", now: now.addingTimeInterval(2))
    XCTAssertNotNil(store.nextRetryDelay(now: now.addingTimeInterval(2)))

    store.acknowledge(messageId: "m1")
    XCTAssertTrue(store.pending(now: now.addingTimeInterval(10)).isEmpty)
  }

  func testOutboxAttachmentDependenciesBlockReleaseAndDiscard() {
    let store = makeDeliveryStore()
    let now = Date(timeIntervalSince1970: 100)
    let transferId = String(repeating: "a", count: 64)

    store.enqueue(
      messageId: "blocked",
      topic: "topic/up",
      wirePayload: "{\"type\":\"text\"}",
      blockedByAttachmentTransferIds: [transferId.uppercased(), transferId],
      now: now
    )
    XCTAssertTrue(store.pending(now: now).isEmpty)
    XCTAssertNil(store.nextRetryDelay(now: now))

    XCTAssertEqual(store.releaseAttachmentDependency(transferId.uppercased(), now: now), 1)
    XCTAssertEqual(store.pending(now: now).map(\.messageId), ["blocked"])
    XCTAssertEqual(store.releaseAttachmentDependency(transferId, now: now), 0)

    let discardStore = makeDeliveryStore()
    discardStore.enqueue(
      messageId: "blocked-discard",
      topic: "topic/up",
      wirePayload: "{\"type\":\"text\"}",
      blockedByAttachmentTransferIds: [String(repeating: "b", count: 64)],
      now: now
    )
    discardStore.enqueue(messageId: "ready", topic: "topic/up", wirePayload: "{\"type\":\"text\"}", now: now)

    XCTAssertEqual(discardStore.discardBlockedByAttachmentTransfers([String(repeating: "b", count: 64)]), 1)
    XCTAssertEqual(discardStore.pending(now: now).map(\.messageId), ["ready"])
  }

  func testPendingLinkMessageEncodesAndroidAttachmentDependencyKey() throws {
    let transferId = String(repeating: "a", count: 64)
    let message = PendingLinkMessage(
      messageId: "m1",
      topic: "topic/up",
      wirePayload: "{}",
      status: "queued",
      attempts: 0,
      nextAttemptAt: Date(timeIntervalSince1970: 100),
      createdAt: Date(timeIntervalSince1970: 100),
      updatedAt: Date(timeIntervalSince1970: 100),
      blockedByAttachmentTransferIds: [transferId.uppercased(), "invalid", transferId]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try encoder.encode(message)) as? [String: Any])

    XCTAssertEqual(object["blocked_by_attachment_transfers"] as? [String], [transferId])
    XCTAssertNil(object["blockedByAttachmentTransferIds"])
  }

  func testOutboxFileBacksLargeWirePayloads() throws {
    let suite = "GalaxySSILinkReliabilityTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let payloadRoot = temporaryOutboxPayloadRoot()
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: payloadRoot.deletingLastPathComponent())
    }
    let store = GalaxySSILinkDeliveryStore(
      defaults: defaults,
      payloadStore: GalaxySSILinkOutboxPayloadStore(rootURL: payloadRoot)
    )
    let now = Date(timeIntervalSince1970: 100)
    let largePayload = String(
      repeating: "x",
      count: GalaxySSILinkOutboxPayloadStore.fileBackedWireThresholdBytes + 1
    )

    store.enqueue(messageId: "large", topic: "topic/up", wirePayload: largePayload, now: now)

    let persisted = try XCTUnwrap(defaults.data(forKey: "galaxyssi-ios-link-delivery-v1"))
    XCTAssertFalse(String(decoding: persisted, as: UTF8.self).contains(largePayload))
    XCTAssertEqual(store.pending(now: now).first?.wirePayload, largePayload)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: payloadRoot.path).count, 1)

    store.acknowledge(messageId: "large")

    XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: payloadRoot.path).isEmpty) ?? true)
  }

  func testAttachmentBrokerAckTimeoutDoesNotExtendOrdinaryMessages() {
    let watchdog = MqttBrokerAckWatchdog(timeoutSeconds: 12)
    watchdog.onPublished(packetId: 7, now: 1, timeoutSeconds: 12)
    watchdog.onPublished(packetId: 8, now: 1, timeoutSeconds: 30)

    XCTAssertEqual(watchdog.nextCheckDelay(now: 13), 0)
    XCTAssertEqual(watchdog.oldestTimedOutPendingAge(now: 13), 12)

    watchdog.onAcknowledged(packetId: 7)

    XCTAssertEqual(watchdog.nextCheckDelay(now: 13), 18)
    XCTAssertNil(watchdog.oldestTimedOutPendingAge(now: 13))
  }

  func testLargeEncryptedWirePayloadUsesAttachmentAckTimeout() {
    XCTAssertEqual(
      MqttBrokerAckTimeoutPolicy.timeoutSeconds(wirePayloadBytes: 1_024),
      MqttBrokerAckTimeoutPolicy.defaultTimeoutSeconds
    )
    XCTAssertEqual(
      MqttBrokerAckTimeoutPolicy.timeoutSeconds(wirePayloadBytes: 128 * 1_024),
      MqttBrokerAckTimeoutPolicy.attachmentTimeoutSeconds
    )
  }

  func testPeerSessionRecoveryRequestsAreRateLimitedPerContact() {
    let gate = GalaxySSIPeerSessionRecoveryGate()

    XCTAssertTrue(gate.begin(contactId: "phone:a", nowMillis: 1_000))
    XCTAssertFalse(gate.begin(contactId: "phone:a", nowMillis: 1_001))
    XCTAssertTrue(gate.begin(contactId: "phone:b", nowMillis: 1_001))
    XCTAssertTrue(gate.begin(
      contactId: "phone:a",
      nowMillis: 1_000 + GalaxySSIPeerSessionRecoveryGate.requestCooldownMillis
    ))

    gate.requestFailed(contactId: "phone:a")
    XCTAssertTrue(gate.begin(contactId: "phone:a", nowMillis: 1_002))
    gate.sessionHealthy(contactId: "phone:a")
    XCTAssertTrue(gate.begin(contactId: "phone:a", nowMillis: 1_003))
  }

  func testOnlyExplicitPhoneBundleRefreshReplacesExistingSession() {
    XCTAssertFalse(GalaxySSIPhoneContactBundlePolicy.replacesExistingSession(.request))
    XCTAssertTrue(GalaxySSIPhoneContactBundlePolicy.replacesExistingSession(.refresh))
    XCTAssertTrue(GalaxySSIPhoneContactBundlePolicy.replacesExistingSession(.bundle))
    XCTAssertFalse(GalaxySSIPhoneContactBundlePolicy.replacesExistingSession(.approval))
  }

  func testRecoverablePeerEnvelopeIsBoundedAndDirectOnly() throws {
    let payload: [String: Any] = ["type": "peer_message", "content": "hello"]
    let envelope: [String: Any] = ["message_id": "message-1", "payload": payload]
    let encoded = GalaxySSILinkDeliveryStore.recoverablePeerEnvelope(
      payload: payload,
      applicationEnvelope: envelope,
      isDirectPhoneContact: true
    )

    XCTAssertFalse(encoded.isEmpty)
    XCTAssertEqual(jsonObject(encoded).string("message_id"), "message-1")
    XCTAssertTrue(GalaxySSILinkDeliveryStore.recoverablePeerEnvelope(
      payload: payload,
      applicationEnvelope: envelope,
      isDirectPhoneContact: false
    ).isEmpty)
    XCTAssertTrue(GalaxySSILinkDeliveryStore.recoverablePeerEnvelope(
      payload: ["type": "delivery_ack"],
      applicationEnvelope: envelope,
      isDirectPhoneContact: true
    ).isEmpty)
    XCTAssertTrue(GalaxySSILinkDeliveryStore.recoverablePeerEnvelope(
      payload: payload,
      applicationEnvelope: ["content": String(repeating: "x", count: 70 * 1_024)],
      isDirectPhoneContact: true
    ).isEmpty)
  }

  func testPendingPeerMessageIsReencryptedAfterSessionRefresh() {
    let suite = "GalaxySSILinkPeerRecoveryTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = GalaxySSILinkDeliveryStore(
      defaults: defaults,
      secrets: InMemorySecretStore()
    )
    let now = Date(timeIntervalSince1970: 100)
    let envelope = #"{"message_id":"message-1","payload":{"type":"peer_message"}}"#
    store.enqueue(
      messageId: "message-1",
      topic: "old/topic",
      wirePayload: "old-ciphertext",
      contactId: "phone:a",
      recoverableEnvelope: envelope,
      now: now
    )
    store.markAttempt(messageId: "message-1", now: now)

    let recovered = store.reencryptRecoverableMessages(
      contactId: "phone:a",
      topic: "new/topic",
      now: now.addingTimeInterval(1)
    ) { recoveredEnvelope in
      XCTAssertEqual(recoveredEnvelope.string("message_id"), "message-1")
      return "new-ciphertext"
    }

    XCTAssertEqual(recovered, 1)
    let pending = store.pending(now: now.addingTimeInterval(1)).first
    XCTAssertEqual(pending?.topic, "new/topic")
    XCTAssertEqual(pending?.wirePayload, "new-ciphertext")
    XCTAssertEqual(pending?.attempts, 0)

    store.discard(messageId: "message-1")
    XCTAssertEqual(store.reencryptRecoverableMessages(
      contactId: "phone:a",
      topic: "new/topic",
      now: now.addingTimeInterval(2),
      encrypt: { _ in "unused" }
    ), 0)
  }

  func testDiscardingPermanentlyRejectedOutboxEntryPreservesFollowingMessage() throws {
    let suite = "GalaxySSILinkRejectedOutboxTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let payloadRoot = temporaryOutboxPayloadRoot()
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: payloadRoot.deletingLastPathComponent())
    }
    let store = GalaxySSILinkDeliveryStore(
      defaults: defaults,
      payloadStore: GalaxySSILinkOutboxPayloadStore(rootURL: payloadRoot)
    )
    let now = Date(timeIntervalSince1970: 100)
    let rejected = String(
      repeating: "x",
      count: GalaxySSIMqttWireChunking.maximumReassembledBytes + 1
    )
    store.enqueue(messageId: "rejected", topic: "topic/up", wirePayload: rejected, now: now)
    store.enqueue(messageId: "valid", topic: "topic/up", wirePayload: "encrypted-voice", now: now)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: payloadRoot.path).count, 1)

    store.discard(messageId: "rejected")

    XCTAssertEqual(store.pending(now: now).map(\.messageId), ["valid"])
    XCTAssertEqual(store.pending(now: now).first?.wirePayload, "encrypted-voice")
    XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: payloadRoot.path).isEmpty) ?? true)
  }

  func testIncomingStageDedupeAndCompletion() {
    let store = makeDeliveryStore()

    XCTAssertEqual(store.stageIncoming(messageId: "in-1", payload: "{\"content\":\"hi\"}"), .staged)
    XCTAssertEqual(store.stageIncoming(messageId: "in-1", payload: "{\"content\":\"hi\"}"), .pending)

    store.completeIncoming(messageId: "in-1")

    XCTAssertEqual(store.stageIncoming(messageId: "in-1", payload: "{\"content\":\"hi\"}"), .completed)
  }

  func testAckPolicyMatchesAndroidFallbacks() {
    let transportId = UUID().uuidString
    XCTAssertEqual(
      GalaxySSILinkDeliveryAckPolicy.transportMessageId(payload: ["source_message_id": transportId]),
      transportId
    )
    XCTAssertEqual(
      GalaxySSILinkDeliveryAckPolicy.clientSourceMessageId(payload: ["source_message_id": "local-client-id"]),
      "local-client-id"
    )
  }

  func testChunkingRoundTripsLargeWirePayload() throws {
    let body = String(repeating: "x", count: 700 * 1024)
    let wire = #"{"scheme":"galaxyssi-link-ios-preview","from":"ios","to":"desktop","body":""# +
      body +
      #""}"#

    let packets = try GalaxySSIMqttWireChunking.encode(wirePayload: wire)
    XCTAssertGreaterThan(packets.count, 1)
    XCTAssertTrue(packets.allSatisfy {
      $0.utf8.count <= GalaxySSIMqttWireChunking.maximumPacketBytes
    })

    let assembler = GalaxySSIMqttChunkAssembler()
    var assembled: String?
    for packet in packets {
      assembled = try assembler.accept(scope: "topic", wire: jsonObject(packet))
    }

    XCTAssertEqual(assembled, wire)
  }

  func testCurrentAndroidWireLimitKeepsFittingPayloadDirect() throws {
    let wire = String(repeating: "x", count: 500 * 1024)

    XCTAssertEqual(
      try GalaxySSIMqttWireChunking.encode(wirePayload: wire),
      [wire]
    )
  }

  func testOversizedMqttPayloadIsPermanentlyRejectedBeforeRetry() {
    let wire = String(repeating: "x", count: GalaxySSIMqttWireChunking.maximumReassembledBytes + 1)

    XCTAssertEqual(
      GalaxySSIMqttWireChunking.permanentRejectionReason(wirePayload: wire),
      "MQTT wire payload exceeds reassembly limit."
    )
    XCTAssertThrowsError(try GalaxySSIMqttWireChunking.encode(wirePayload: wire))
  }

  func testExcessiveMqttChunkCountIsPermanentlyRejectedBeforeRetry() {
    let wire = String(repeating: "x", count: 2_000)

    XCTAssertEqual(
      GalaxySSIMqttWireChunking.permanentRejectionReason(
        wirePayload: wire,
        directLimitBytes: 1,
        chunkDataBytes: 1
      ),
      "MQTT wire payload requires too many chunks."
    )
  }

  func testChunkAssemblerRejectsConflictingDuplicate() throws {
    let wire = #"{"scheme":"galaxyssi-link-ios-preview","from":"ios","to":"desktop","body":""# +
      String(repeating: "x", count: 80 * 1024) +
      #""}"#
    let packet = try GalaxySSIMqttWireChunking.encode(wirePayload: wire).first!
    let object = jsonObject(packet)
    var conflicting = object
    conflicting["data"] = Data("different".utf8).base64EncodedString()
    conflicting["chunk_sha256"] = GalaxySSIMqttWireChunking.sha256(Data("different".utf8))

    let assembler = GalaxySSIMqttChunkAssembler()
    _ = try assembler.accept(scope: "topic", wire: object)

    XCTAssertThrowsError(try assembler.accept(scope: "topic", wire: conflicting))
  }

  func testCiphertextDigestIsStableAndFieldBounded() {
    let digest = GalaxySSILinkCiphertextReplayPolicy.digest(wire: [
      "scheme": "signal",
      "from": "desktop",
      "to": "ios",
      "body": "encrypted",
      "ignored": UUID().uuidString
    ])
    let sameDigest = GalaxySSILinkCiphertextReplayPolicy.digest(wire: [
      "scheme": "signal",
      "from": "desktop",
      "to": "ios",
      "body": "encrypted",
      "ignored": UUID().uuidString
    ])

    XCTAssertEqual(digest, sameDigest)
    XCTAssertEqual(digest.count, 64)
  }

  func testMqttPublishGuardCapturesPublishBackpressure() throws {
    let success = MqttPublishGuard.attempt { 42 }
    let failure = MqttPublishGuard.attempt { () -> Int in
      throw GalaxySSIError.invalidPayload("max in-flight")
    }

    XCTAssertEqual(try success.get(), 42)
    XCTAssertThrowsError(try failure.get())
  }

  func testMqttOutboxDispatchPolicyKeepsOfflineAndBackpressureAccepted() {
    let offline = MqttOutboxDispatchPolicy.result(connected: false, published: false)
    let backpressure = MqttOutboxDispatchPolicy.result(connected: true, published: false)
    let immediate = MqttOutboxDispatchPolicy.result(connected: true, published: true)

    XCTAssertEqual(offline, .queued)
    XCTAssertEqual(backpressure, .queued)
    XCTAssertEqual(immediate, .published)
    XCTAssertTrue(offline.accepted)
    XCTAssertTrue(backpressure.accepted)
    XCTAssertTrue(immediate.accepted)
    XCTAssertFalse(MqttPublishResult.failed.accepted)
  }

  func testMqttConnectionRetryBacksOffCapsAndResets() {
    let policy = MqttConnectionRetryPolicy(delaysMillis: [2, 5, 10])

    XCTAssertEqual(policy.nextDelayMillis(), 2)
    XCTAssertEqual(policy.nextDelayMillis(), 5)
    XCTAssertEqual(policy.nextDelayMillis(), 10)
    XCTAssertEqual(policy.nextDelayMillis(), 10)
    policy.reset()
    XCTAssertEqual(policy.nextDelayMillis(), 2)
  }

  func testMqttSubscriptionRecoveryWaitsForAllResultsAndIgnoresStaleGenerations() {
    let state = MqttSubscriptionRecoveryState()
    let firstGeneration = state.begin(subscriptionCount: 2)

    XCTAssertEqual(state.complete(generation: firstGeneration, succeeded: true), .pending)
    XCTAssertEqual(state.complete(generation: firstGeneration, succeeded: true), .ready)

    let retryGeneration = state.begin(subscriptionCount: 2)
    XCTAssertEqual(state.complete(generation: retryGeneration, succeeded: false), .pending)
    XCTAssertEqual(state.complete(generation: retryGeneration, succeeded: true), .retry)

    let staleGeneration = state.begin(subscriptionCount: 1)
    state.invalidate()
    XCTAssertEqual(state.complete(generation: staleGeneration, succeeded: true), .stale)
  }

  private func makeDeliveryStore() -> GalaxySSILinkDeliveryStore {
    let suite = "GalaxySSILinkReliabilityTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return GalaxySSILinkDeliveryStore(defaults: defaults)
  }

  private func temporaryOutboxPayloadRoot() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("GalaxySSILinkOutboxPayloadTests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("galaxyssi-link-outbox-v1", isDirectory: true)
  }

  private func jsonObject(_ text: String) -> [String: Any] {
    let data = Data(text.utf8)
    return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
  }
}
