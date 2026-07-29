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
    let body = String(repeating: "x", count: 80 * 1024)
    let wire = #"{"scheme":"signalasi-link-ios-preview","from":"ios","to":"desktop","body":""# +
      body +
      #""}"#

    let packets = try SignalASIMqttWireChunking.encode(wirePayload: wire)
    XCTAssertGreaterThan(packets.count, 1)

    let assembler = SignalASIMqttChunkAssembler()
    var assembled: String?
    for packet in packets {
      assembled = try assembler.accept(scope: "topic", wire: jsonObject(packet))
    }

    XCTAssertEqual(assembled, wire)
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

  private func jsonObject(_ text: String) -> [String: Any] {
    let data = Data(text.utf8)
    return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
  }
}
