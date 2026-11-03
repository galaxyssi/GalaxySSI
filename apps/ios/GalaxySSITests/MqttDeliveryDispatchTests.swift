import XCTest
@testable import GalaxySSI

final class MqttDeliveryDispatchTests: XCTestCase {
  func testCommittedReceiptStopsCopiesEvenAfterPolicyObservationReset() async throws {
    let fixture = DispatchFixture()
    _ = try await fixture.dispatch.submit(topic: "outbox", delivery: fixture.delivery())
    let first = try XCTUnwrap(fixture.publications.first)
    fixture.policy.forgetPeer("pair")
    var committed = false
    let accepted = try await fixture.dispatch.acceptVerifiedReceipt(peer: "pair", frame: first.frame) { committed = true }
    XCTAssertTrue(accepted)
    XCTAssertTrue(committed)
    let state = await fixture.dispatch.diagnostics()
    XCTAssertEqual(state.queuedCopies, 0)
    fixture.time = 5000
    await fixture.dispatch.tick()
    XCTAssertEqual(fixture.publications.count, 1)
  }

  func testBrokerAckDoesNotStopDelayedCopiesOrCreateRTTSamples() async throws {
    let fixture = DispatchFixture()
    let token = try await fixture.dispatch.submit(topic: "outbox", delivery: fixture.delivery())
    let first = try XCTUnwrap(fixture.publications.first)
    XCTAssertEqual(fixture.publications.count, 1)
    _ = await fixture.ack(first)
    XCTAssertEqual(fixture.completions.map(\.0), [token])
    XCTAssertEqual(fixture.completions.map(\.1), [true])
    XCTAssertTrue(fixture.policy.pending(peer: "pair", messageID: "message"))
    XCTAssertEqual(fixture.policy.diagnostics(now: 0).verifiedDelivery[first.frame.attempt.brokerID]?.samples, 0)
    fixture.time = 1999
    await fixture.dispatch.tick()
    XCTAssertEqual(fixture.publications.count, 1)
    fixture.time = 2000
    await fixture.dispatch.tick()
    fixture.time = 4000
    await fixture.dispatch.tick()
    XCTAssertEqual(fixture.publications.count, 3)
    XCTAssertEqual(Set(fixture.publications.map { $0.frame.attempt.brokerID }), MqttRouteProtocol.brokerIDs)
    XCTAssertEqual(Set(fixture.publications.map { $0.frame.attempt.attemptID }).count, 3)
  }

  func testVerifiedReceiptCommitsBeforeCancellingCopiesAndRetainsPhysicalSlot() async throws {
    let fixture = DispatchFixture()
    _ = try await fixture.dispatch.submit(topic: "outbox", delivery: fixture.delivery())
    let first = try XCTUnwrap(fixture.publications.first)
    fixture.time = 100
    var commits = 0
    let accepted = try await fixture.dispatch.acceptVerifiedReceipt(peer: "pair", frame: first.frame) { commits += 1 }
    XCTAssertTrue(accepted)
    XCTAssertEqual(commits, 1)
    var state = await fixture.dispatch.diagnostics()
    XCTAssertEqual(state.queuedCopies, 0)
    XCTAssertEqual(state.trackedAttempts, 1)
    XCTAssertEqual(fixture.policy.diagnostics(now: 100).inflightPackets, 1)
    XCTAssertFalse(fixture.policy.pending(peer: "pair", messageID: "message"))
    fixture.time = 5000
    await fixture.dispatch.tick()
    XCTAssertEqual(fixture.publications.count, 1)
    _ = await fixture.ack(first)
    state = await fixture.dispatch.diagnostics()
    XCTAssertEqual(state.messages, 0)
    XCTAssertEqual(state.trackedAttempts, 0)
    XCTAssertEqual(fixture.policy.diagnostics(now: 5000).inflightPackets, 0)
  }

  func testFailedDurableCommitLeavesHedgesAndObservationsUntouched() async throws {
    let fixture = DispatchFixture()
    _ = try await fixture.dispatch.submit(topic: "outbox", delivery: fixture.delivery())
    let first = try XCTUnwrap(fixture.publications.first)
    do {
      _ = try await fixture.dispatch.acceptVerifiedReceipt(peer: "pair", frame: first.frame) { throw DispatchFixture.Fault.commit }
      XCTFail("A failed commit must propagate")
    } catch DispatchFixture.Fault.commit { }
    let state = await fixture.dispatch.diagnostics()
    XCTAssertEqual(state.queuedCopies, 2)
    XCTAssertTrue(fixture.policy.pending(peer: "pair", messageID: "message"))
    fixture.time = 2000
    await fixture.dispatch.tick()
    XCTAssertEqual(fixture.publications.count, 2)
  }

  func testWrongPeerOrAttemptCannotCommitReceipt() async throws {
    let fixture = DispatchFixture()
    _ = try await fixture.dispatch.submit(topic: "outbox", delivery: fixture.delivery())
    let first = try XCTUnwrap(fixture.publications.first)
    var commits = 0
    let wrongPeer = try await fixture.dispatch.acceptVerifiedReceipt(peer: "other", frame: first.frame) { commits += 1 }
    let different = try MqttDeliveryEnvelope.Frame(message: first.frame.message,
      attempt: .init(attemptID: first.frame.attempt.attemptID, brokerID: first.frame.attempt.brokerID, generation: 2))
    let wrongGeneration = try await fixture.dispatch.acceptVerifiedReceipt(peer: "pair", frame: different) { commits += 1 }
    XCTAssertFalse(wrongPeer)
    XCTAssertFalse(wrongGeneration)
    XCTAssertEqual(commits, 0)
  }

  func testStoredMessageAckStopsCopiesWithoutRTTSample() async throws {
    let fixture = DispatchFixture()
    let delivery = try fixture.delivery()
    _ = try await fixture.dispatch.submit(topic: "outbox", delivery: delivery)
    _ = await fixture.ack(try XCTUnwrap(fixture.publications.first))
    let accepted = try await fixture.dispatch.acceptVerifiedMessage(peer: "pair", messageID: delivery.message.messageID,
      contentHash: delivery.message.contentHash) { }
    XCTAssertTrue(accepted)
    let state = await fixture.dispatch.diagnostics()
    XCTAssertEqual(state.messages, 0)
    XCTAssertTrue(fixture.policy.diagnostics(now: 100).verifiedDelivery.values.allSatisfy { $0.samples == 0 })
  }

  func testDuplicateSubmitReusesTokenButCannotChangeLogicalContents() async throws {
    let fixture = DispatchFixture()
    let first = try await fixture.dispatch.submit(topic: "outbox", delivery: fixture.delivery())
    let duplicate = try await fixture.dispatch.submit(topic: "outbox", delivery: fixture.delivery())
    XCTAssertEqual(first, duplicate)
    XCTAssertEqual(fixture.publications.count, 1)
    do {
      _ = try await fixture.dispatch.submit(topic: "outbox", delivery: fixture.delivery(hash: String(repeating: "d", count: 64)))
      XCTFail("Conflicting contents must not share a message ID")
    } catch MqttDeliveryDispatch.Failure.invalidPacket { }
  }

  func testRejectedEnqueueImmediatelyTriesAnotherPath() async throws {
    let fixture = DispatchFixture()
    fixture.onPublish = { [weak fixture] publication in publication.frame.attempt.brokerID != fixture?.publications.first?.frame.attempt.brokerID }
    _ = try await fixture.dispatch.submit(topic: "outbox", delivery: fixture.delivery())
    XCTAssertEqual(fixture.publications.count, 3)
    XCTAssertEqual(fixture.policy.diagnostics(now: 0).inflightPackets, 2)
    let state = await fixture.dispatch.diagnostics()
    XCTAssertEqual(state.trackedAttempts, 2)
  }

  func testAllRejectedEnqueuesReleaseCapacityAndCompleteOnce() async throws {
    let fixture = DispatchFixture()
    fixture.onPublish = { _ in false }
    do {
      _ = try await fixture.dispatch.submit(topic: "outbox", delivery: fixture.delivery())
      XCTFail("All physical sends were rejected")
    } catch MqttDeliveryDispatch.Failure.unavailable { }
    let state = await fixture.dispatch.diagnostics()
    XCTAssertEqual(state.messages, 0)
    XCTAssertEqual(state.trackedAttempts, 0)
    XCTAssertEqual(fixture.policy.diagnostics(now: 0).inflightPackets, 0)
    XCTAssertEqual(fixture.completions.map(\.1), [false])
  }

  func testAuthorizationIsRecheckedForEveryDelayedCopy() async throws {
    let fixture = DispatchFixture()
    _ = try await fixture.dispatch.submit(topic: "outbox", delivery: fixture.delivery())
    fixture.authorized = false
    fixture.time = 4000
    await fixture.dispatch.tick()
    XCTAssertEqual(fixture.publications.count, 1)
    let state = await fixture.dispatch.diagnostics()
    XCTAssertEqual(state.queuedCopies, 0)
  }

  func testStalePhysicalCompletionsCannotReleaseCurrentSlot() async throws {
    let fixture = DispatchFixture()
    _ = try await fixture.dispatch.submit(topic: "outbox", delivery: fixture.delivery())
    let first = try XCTUnwrap(fixture.publications.first)
    let result = await fixture.dispatch.published(attemptID: first.frame.attempt.attemptID,
      broker: first.frame.attempt.brokerID, generation: 2, acknowledged: true)
    XCTAssertFalse(result)
    XCTAssertEqual(fixture.policy.diagnostics(now: 0).inflightPackets, 1)
    XCTAssertTrue(fixture.completions.isEmpty)
  }

  func testFailedPhysicalCompletionExpeditesRemainingCopies() async throws {
    let fixture = DispatchFixture()
    _ = try await fixture.dispatch.submit(topic: "outbox", delivery: fixture.delivery())
    let first = try XCTUnwrap(fixture.publications.first)
    _ = await fixture.ack(first, acknowledged: false)
    await fixture.dispatch.tick()
    XCTAssertEqual(fixture.publications.count, 3)
    XCTAssertEqual(fixture.policy.diagnostics(now: 0).inflightPackets, 2)
  }

  func testEncodedPacketBoundIncludesTopicAndMqttFraming() async throws {
    XCTAssertEqual(try MqttDeliveryDispatch.packetBytes(topic: "outbox", payloadBytes: 100), 112)
    XCTAssertEqual(try MqttDeliveryDispatch.packetBytes(topic: "outbox", payloadBytes: 118), 131)
    for topic in ["", "a\0b", "a/+", "a/#"] {
      XCTAssertThrowsError(try MqttDeliveryDispatch.packetBytes(topic: topic, payloadBytes: 1))
    }
    XCTAssertThrowsError(try MqttDeliveryDispatch.packetBytes(topic: "outbox", payloadBytes: 1_048_576))
    let fixture = DispatchFixture()
    do {
      _ = try await fixture.dispatch.submit(topic: "outbox", delivery: fixture.delivery(bytes: 1000, bound: 1000))
      XCTFail("The MQTT overhead exceeds the bound")
    } catch MqttDeliveryDispatch.Failure.invalidPacket { }
    XCTAssertTrue(fixture.publications.isEmpty)
    XCTAssertEqual(fixture.policy.diagnostics(now: 0).inflightPackets, 0)
  }

  func testGenerationChangeCancelsOldScheduledCopies() async throws {
    let fixture = DispatchFixture()
    _ = try await fixture.dispatch.submit(topic: "outbox", delivery: fixture.delivery())
    fixture.policy.synchronize(Dictionary(uniqueKeysWithValues: MqttRouteProtocol.brokerIDs.map {
      ($0, MqttBrokerPathSnapshot(brokerID: $0, generation: 2, connected: true, subscriptions: ["inbox"]))
    }))
    fixture.time = 4000
    await fixture.dispatch.tick()
    XCTAssertEqual(fixture.publications.count, 1)
  }

  func testCloseDuringAwaitCannotResurrectJobOrCompleteTwice() async throws {
    let fixture = DispatchFixture()
    let dispatch = fixture.dispatch
    fixture.onPublish = { [weak dispatch] _ in await dispatch?.close(); return true }
    do {
      _ = try await dispatch.submit(topic: "outbox", delivery: fixture.delivery())
      XCTFail("Closed dispatch must reject the submission")
    } catch MqttDeliveryDispatch.Failure.unavailable { }
    let first = try XCTUnwrap(fixture.publications.first)
    let late = await fixture.ack(first)
    XCTAssertFalse(late)
    XCTAssertEqual(fixture.completions.map(\.1), [false])
    XCTAssertEqual(fixture.policy.diagnostics(now: 0).inflightPackets, 0)
    let state = await dispatch.diagnostics()
    XCTAssertEqual(state.messages, 0)
  }

  func testAckDuringEnqueueIsNotOverwrittenByLateEnqueueFailure() async throws {
    let fixture = DispatchFixture()
    let dispatch = fixture.dispatch
    fixture.onPublish = { [weak dispatch] publication in
      _ = await dispatch?.published(attemptID: publication.frame.attempt.attemptID,
        broker: publication.frame.attempt.brokerID, generation: 1, acknowledged: true)
      return false
    }
    _ = try await dispatch.submit(topic: "outbox", delivery: fixture.delivery())
    XCTAssertEqual(fixture.publications.count, 1)
    XCTAssertEqual(fixture.completions.map(\.1), [true])
    XCTAssertTrue(fixture.policy.pending(peer: "pair", messageID: "message"))
  }

  func testObservationExpiryAllowsDurableOutboxToRetryWithNewToken() async throws {
    let fixture = DispatchFixture()
    let firstToken = try await fixture.dispatch.submit(topic: "outbox", delivery: fixture.delivery())
    _ = await fixture.ack(try XCTUnwrap(fixture.publications.first))
    fixture.time = 30_000
    await fixture.dispatch.tick()
    let state = await fixture.dispatch.diagnostics()
    XCTAssertEqual(state.messages, 0)
    let retryToken = try await fixture.dispatch.submit(topic: "outbox", delivery: fixture.delivery())
    XCTAssertNotEqual(firstToken, retryToken)
    XCTAssertEqual(fixture.publications.count, 2)
  }

  func testReceiptAndPubackDuringEnqueueReturnSuccessfulSubmissionToken() async throws {
    let fixture = DispatchFixture()
    let dispatch = fixture.dispatch
    fixture.onPublish = { [weak dispatch] publication in
      guard let dispatch else { return false }
      _ = await dispatch.published(attemptID: publication.frame.attempt.attemptID,
        broker: publication.frame.attempt.brokerID, generation: 1, acknowledged: true)
      _ = try? await dispatch.acceptVerifiedReceipt(peer: "pair", frame: publication.frame) { }
      return true
    }
    let token = try await dispatch.submit(topic: "outbox", delivery: fixture.delivery())
    XCTAssertEqual(fixture.completions.map(\.0), [token])
    XCTAssertEqual(fixture.completions.map(\.1), [true])
    let state = await dispatch.diagnostics()
    XCTAssertEqual(state.messages, 0)
    XCTAssertEqual(state.trackedAttempts, 0)
  }
}

private final class DispatchFixture {
  enum Fault: Error { case commit }
  let policy = MqttMultipathPolicy(tieSeed: Data("dispatch-tests".utf8))
  private let lock = NSLock()
  private var clock: Int64 = 0
  private var permission = true
  private var sends: [MqttDeliveryDispatch.Publication] = []
  private var finishes: [(String, Bool)] = []
  var onPublish: ((MqttDeliveryDispatch.Publication) async -> Bool)?
  var time: Int64 { get { locked { clock } } set { locked { clock = newValue } } }
  var authorized: Bool { get { locked { permission } } set { locked { permission = newValue } } }
  var publications: [MqttDeliveryDispatch.Publication] { locked { sends } }
  var completions: [(String, Bool)] { locked { finishes } }
  lazy var dispatch = MqttDeliveryDispatch(policy: policy, publish: { [weak self] publication in
    guard let self else { return false }
    self.locked { self.sends.append(publication) }
    return await self.onPublish?(publication) ?? true
  }, brokerCompleted: { [weak self] token, accepted in
    self?.locked { self?.finishes.append((token, accepted)) }
  }, now: { [weak self] in self?.time ?? 0 })

  init() {
    policy.synchronize(Dictionary(uniqueKeysWithValues: MqttRouteProtocol.brokerIDs.map {
      ($0, MqttBrokerPathSnapshot(brokerID: $0, generation: 1, connected: true, subscriptions: ["inbox"]))
    }))
    _ = policy.acceptVerifiedResume(peer: "pair", route: .init(epoch: 1, receiveBrokers: MqttRouteProtocol.brokerIDs,
      packetBytes: 1_048_576, chunkACKs: true, expiresAt: 300_000), now: 0)
  }
  func delivery(hash: String = String(repeating: "a", count: 64), bytes: Int = 100, bound: Int = 512) throws -> MqttDeliveryDispatch.Delivery {
    try .init(peer: "pair", message: .init(messageID: "message", contentHash: hash,
      sender: String(repeating: "b", count: 64), receiver: String(repeating: "c", count: 64), traffic: "message"),
      receiveTopics: ["inbox"], secretFingerprint: String(repeating: "e", count: 64),
      sizeBound: bound, encodeAttempt: { _ in Data(repeating: 1, count: bytes) },
      authorized: { [weak self] _, _ in self?.authorized ?? false })
  }
  func ack(_ publication: MqttDeliveryDispatch.Publication, acknowledged: Bool = true) async -> Bool {
    await dispatch.published(attemptID: publication.frame.attempt.attemptID, broker: publication.frame.attempt.brokerID,
                             generation: publication.frame.attempt.generation, acknowledged: acknowledged)
  }
  private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
}
