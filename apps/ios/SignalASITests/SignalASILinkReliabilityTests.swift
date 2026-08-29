import XCTest
@testable import SignalASI

@MainActor
final class SignalASILinkReliabilityTests: XCTestCase {
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
    let suite = "SignalASILinkReliabilityTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let payloadRoot = temporaryOutboxPayloadRoot()
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: payloadRoot.deletingLastPathComponent())
    }
    let store = SignalASILinkDeliveryStore(
      defaults: defaults,
      payloadStore: SignalASILinkOutboxPayloadStore(rootURL: payloadRoot)
    )
    let now = Date(timeIntervalSince1970: 100)
    let largePayload = String(
      repeating: "x",
      count: SignalASILinkOutboxPayloadStore.fileBackedWireThresholdBytes + 1
    )

    store.enqueue(messageId: "large", topic: "topic/up", wirePayload: largePayload, now: now)

    let persisted = try XCTUnwrap(defaults.data(forKey: "signalasi-ios-link-delivery-v1"))
    XCTAssertFalse(String(decoding: persisted, as: UTF8.self).contains(largePayload))
    XCTAssertEqual(store.pending(now: now).first?.wirePayload, largePayload)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: payloadRoot.path).count, 1)

    store.acknowledge(messageId: "large")

    XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: payloadRoot.path).isEmpty) ?? true)
  }

  func testDiscardingPermanentlyRejectedOutboxEntryPreservesFollowingMessage() throws {
    let suite = "SignalASILinkRejectedOutboxTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let payloadRoot = temporaryOutboxPayloadRoot()
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: payloadRoot.deletingLastPathComponent())
    }
    let store = SignalASILinkDeliveryStore(
      defaults: defaults,
      payloadStore: SignalASILinkOutboxPayloadStore(rootURL: payloadRoot)
    )
    let now = Date(timeIntervalSince1970: 100)
    let rejected = String(
      repeating: "x",
      count: SignalASIMqttWireChunking.maximumReassembledBytes + 1
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
      SignalASILinkDeliveryAckPolicy.transportMessageId(payload: ["source_message_id": transportId]),
      transportId
    )
    XCTAssertEqual(
      SignalASILinkDeliveryAckPolicy.clientSourceMessageId(payload: ["source_message_id": "local-client-id"]),
      "local-client-id"
    )
  }

  func testChunkingRoundTripsLargeWirePayload() throws {
    let body = String(repeating: "x", count: 700 * 1024)
    let wire = #"{"scheme":"signalasi-link-ios-preview","from":"ios","to":"desktop","body":""# +
      body +
      #""}"#

    let packets = try SignalASIMqttWireChunking.encode(wirePayload: wire)
    XCTAssertGreaterThan(packets.count, 1)
    XCTAssertTrue(packets.allSatisfy {
      $0.utf8.count <= SignalASIMqttWireChunking.maximumPacketBytes
    })

    let assembler = SignalASIMqttChunkAssembler()
    var assembled: String?
    for packet in packets {
      assembled = try assembler.accept(scope: "topic", wire: jsonObject(packet))
    }

    XCTAssertEqual(assembled, wire)
  }

  func testCurrentAndroidWireLimitKeepsFittingPayloadDirect() throws {
    let wire = String(repeating: "x", count: 500 * 1024)

    XCTAssertEqual(
      try SignalASIMqttWireChunking.encode(wirePayload: wire),
      [wire]
    )
  }

  func testOversizedMqttPayloadIsPermanentlyRejectedBeforeRetry() {
    let wire = String(repeating: "x", count: SignalASIMqttWireChunking.maximumReassembledBytes + 1)

    XCTAssertEqual(
      SignalASIMqttWireChunking.permanentRejectionReason(wirePayload: wire),
      "MQTT wire payload exceeds reassembly limit."
    )
    XCTAssertThrowsError(try SignalASIMqttWireChunking.encode(wirePayload: wire))
  }

  func testExcessiveMqttChunkCountIsPermanentlyRejectedBeforeRetry() {
    let wire = String(repeating: "x", count: 2_000)

    XCTAssertEqual(
      SignalASIMqttWireChunking.permanentRejectionReason(
        wirePayload: wire,
        directLimitBytes: 1,
        chunkDataBytes: 1
      ),
      "MQTT wire payload requires too many chunks."
    )
  }

  func testChunkAssemblerRejectsConflictingDuplicate() throws {
    let wire = #"{"scheme":"signalasi-link-ios-preview","from":"ios","to":"desktop","body":""# +
      String(repeating: "x", count: 80 * 1024) +
      #""}"#
    let packet = try SignalASIMqttWireChunking.encode(wirePayload: wire).first!
    let object = jsonObject(packet)
    var conflicting = object
    conflicting["data"] = Data("different".utf8).base64EncodedString()
    conflicting["chunk_sha256"] = SignalASIMqttWireChunking.sha256(Data("different".utf8))

    let assembler = SignalASIMqttChunkAssembler()
    _ = try assembler.accept(scope: "topic", wire: object)

    XCTAssertThrowsError(try assembler.accept(scope: "topic", wire: conflicting))
  }

  func testCiphertextDigestIsStableAndFieldBounded() {
    let digest = SignalASILinkCiphertextReplayPolicy.digest(wire: [
      "scheme": "signal",
      "from": "desktop",
      "to": "ios",
      "body": "encrypted",
      "ignored": UUID().uuidString
    ])
    let sameDigest = SignalASILinkCiphertextReplayPolicy.digest(wire: [
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
      throw SignalASIError.invalidPayload("max in-flight")
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

  private func makeDeliveryStore() -> SignalASILinkDeliveryStore {
    let suite = "SignalASILinkReliabilityTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return SignalASILinkDeliveryStore(defaults: defaults)
  }

  private func temporaryOutboxPayloadRoot() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("SignalASILinkOutboxPayloadTests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("signalasi-link-outbox-v1", isDirectory: true)
  }

  private func jsonObject(_ text: String) -> [String: Any] {
    let data = Data(text.utf8)
    return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
  }
}
