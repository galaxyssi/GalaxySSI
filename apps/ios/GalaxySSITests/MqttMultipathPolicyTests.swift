import XCTest
@testable import GalaxySSI

final class MqttMultipathPolicyTests: XCTestCase {
  func testInteractiveDesktopRequestsHedgeOnlyAcrossAuthorizedGenerations() {
    let policy = ready()
    for traffic in [MqttMultipathPolicy.Traffic.final, .message] {
      let result = policy.plan(peer: "peer", messageID: "interactive", traffic: traffic, wireBytes: 87_500,
        receiveTopics: ["inbox"], now: 1_000, eligible: ["emqx": 1, "mosquitto": 1, "hivemq": 2], interactiveFinal: true)
      XCTAssertEqual(result.map(\.delayMillis), [0, 250])
      XCTAssertFalse(result.contains { $0.brokerID == "hivemq" })
    }
    XCTAssertTrue(policy.plan(peer: "peer", messageID: "interactive", traffic: .final, wireBytes: 87_500,
      receiveTopics: ["inbox"], now: 1_000, eligible: [:], interactiveFinal: true).isEmpty)
  }

  func testInteractiveBudgetDoesNotChangeDefaultHedgesChunksOrLargePackets() {
    let policy = ready()
    func choose(_ bytes: Int, _ traffic: MqttMultipathPolicy.Traffic = .final, interactive: Bool = true) -> [MqttMultipathPolicy.Dispatch] {
      policy.plan(peer: "peer", messageID: "interactive", traffic: traffic, wireBytes: bytes,
        receiveTopics: ["inbox"], now: 1_000, interactiveFinal: interactive)
    }
    XCTAssertEqual(choose(256 * 1024).map(\.delayMillis), [0, 250, 500])
    XCTAssertEqual(choose(256 * 1024 + 1).count, 1)
    XCTAssertEqual(choose(87_500, .chunk).count, 1)
    XCTAssertEqual(choose(87_500, .progress).count, 1)
    XCTAssertEqual(choose(87_500, interactive: false).count, 1)
    XCTAssertEqual(choose(100, interactive: false).map(\.delayMillis), [0, 2_000, 4_000])
  }

  func testInteractiveFlagCannotBypassSubscriptionResumeOrPacketAdmission() {
    let policy = ready()
    policy.synchronize(["emqx": path("emqx", topics: [])])
    XCTAssertTrue(policy.plan(peer: "peer", messageID: "interactive", traffic: .final, wireBytes: 87_500,
      receiveTopics: ["inbox"], now: 1_000, interactiveFinal: true).isEmpty)
    policy.synchronize(snapshots())
    XCTAssertTrue(policy.plan(peer: "unknown", messageID: "interactive", traffic: .final, wireBytes: 87_500,
      receiveTopics: ["inbox"], now: 1_000, interactiveFinal: true).isEmpty)
    XCTAssertTrue(policy.plan(peer: "peer", messageID: "interactive", traffic: .final, wireBytes: 87_500,
      receiveTopics: ["inbox"], now: 300_000, interactiveFinal: true).isEmpty)
  }

  private let brokers = MqttRouteProtocol.brokerIDs
  private let hash = String(repeating: "a", count: 64)

  func testFirstCommonSubscribedPathWorksInEveryStartupOrder() {
    for first in brokers {
      for second in brokers.subtracting([first]) {
        let order = [first, second] + brokers.subtracting([first, second]).sorted()
        let policy = MqttMultipathPolicy()
        XCTAssertTrue(policy.acceptVerifiedResume(peer: "peer", route: route(), now: 0))
        var snapshots: [String: MqttBrokerPathSnapshot] = [:]
        for (index, broker) in order.enumerated() {
          snapshots[broker] = path(broker, topics: [])
          policy.synchronize(snapshots)
          XCTAssertEqual(plan(policy, traffic: .control).count, index)
          snapshots[broker] = path(broker)
          policy.synchronize(snapshots)
          XCTAssertEqual(Set(plan(policy, traffic: .control).map(\.brokerID)), Set(order.prefix(index + 1)))
        }
      }
    }
  }

  func testNoUnverifiedPathOrDefaultBrokerPreference() {
    let policy = ready()
    XCTAssertTrue(plan(policy, peer: "unknown").isEmpty)
    let winners = Set((0..<100).compactMap { plan(policy, message: String($0)).first?.brokerID })
    XCTAssertEqual(winners, brokers)
  }

  func testMessageHedgesControlRacesAndProgressOrLargePacketsStaySinglePath() {
    let policy = ready()
    XCTAssertEqual(plan(policy).map(\.delayMillis), [0, 2000, 4000])
    XCTAssertEqual(plan(policy, traffic: .control).map(\.delayMillis), [0, 0, 0])
    for traffic in [MqttMultipathPolicy.Traffic.progress, .chunk] {
      XCTAssertEqual(plan(policy, traffic: traffic).count, 1)
    }
    for traffic in [MqttMultipathPolicy.Traffic.message, .final, .control] {
      XCTAssertEqual(plan(policy, traffic: traffic, size: 65_537).count, 1)
    }
    for broker in brokers {
      XCTAssertEqual(plan(policy, traffic: .receipt, ingress: broker).first?.brokerID, broker)
      XCTAssertEqual(Set(plan(policy, traffic: .receipt, ingress: broker).map(\.brokerID)), brokers)
    }
  }

  func testDisconnectedOrUnsubscribedPathsCannotBeSelected() {
    let policy = ready()
    var paths = snapshots()
    paths["emqx"] = nil
    policy.synchronize(paths)
    XCTAssertEqual(Set(plan(policy).map(\.brokerID)), brokers.subtracting(["emqx"]))
    policy.synchronize([:])
    XCTAssertTrue(plan(policy).isEmpty)
    policy.synchronize(["mosquitto": path("mosquitto", generation: 2)])
    XCTAssertEqual(plan(policy).map(\.brokerID), ["mosquitto"])
    XCTAssertTrue(policy.readyBrokers(receiveTopics: ["inbox", "unsubscribed"]).isEmpty)
  }

  func testAuthorizationFiltersBeforeSinglePathRanking() {
    let policy = ready()
    for traffic in [MqttMultipathPolicy.Traffic.receipt, .message] {
      let ranked = policy.plan(peer: "peer", messageID: "message", traffic: traffic,
        wireBytes: 100_000, receiveTopics: ["inbox"], now: 0, ingress: "emqx", eligible: ["hivemq": 1])
      XCTAssertEqual(ranked.map(\.brokerID), ["hivemq"])
      XCTAssertTrue(policy.plan(peer: "peer", messageID: "message", traffic: traffic,
        wireBytes: 100_000, receiveTopics: ["inbox"], now: 0, eligible: ["hivemq": 2]).isEmpty)
    }
  }

  func testStaleGenerationCannotRestoreSubscriptionsOrReleaseNewAttempt() {
    let policy = ready()
    var paths = snapshots()
    paths["emqx"] = path("emqx", generation: 2, topics: [])
    policy.synchronize(paths)
    XCTAssertFalse(plan(policy).contains { $0.brokerID == "emqx" })
    paths["emqx"] = path("emqx")
    policy.synchronize(paths)
    XCTAssertFalse(plan(policy).contains { $0.brokerID == "emqx" })
    paths["emqx"] = path("emqx", generation: 2)
    policy.synchronize(paths)
    XCTAssertTrue(policy.reserve(attemptID: "new", attempt: attempt(generation: 2)))
    XCTAssertFalse(policy.brokerAck(attemptID: "new", broker: "emqx", generation: 1))
    XCTAssertEqual(policy.diagnostics(now: 1000).inflightPackets, 1)
  }

  func testConfigurationReplacementReleasesOldSlotsAndUsesExactSubscriptions() {
    let policy = ready()
    XCTAssertTrue(policy.reserve(attemptID: "old", attempt: attempt()))
    var paths = snapshots()
    paths["emqx"] = path("emqx", topics: [])
    paths["emqx"]?.configurationID = "new-configuration"
    policy.synchronize(paths)
    XCTAssertEqual(policy.diagnostics(now: 1000).inflightPackets, 0)
    XCTAssertTrue(policy.pending(peer: "peer", messageID: "m"))
    XCTAssertFalse(plan(policy).contains { $0.brokerID == "emqx" })
  }

  func testRemoteReceiveSetExpiryAndEpochReplayLimitRoutes() {
    let policy = ready()
    XCTAssertTrue(policy.acceptVerifiedResume(peer: "peer", route: route(epoch: 2, paths: ["hivemq"], expiry: 200_000), now: 0))
    XCTAssertEqual(plan(policy).map(\.brokerID), ["hivemq"])
    XCTAssertFalse(policy.acceptVerifiedResume(peer: "peer", route: route(), now: 0))
    XCTAssertFalse(policy.acceptVerifiedResume(peer: "peer", route: route(epoch: 2, paths: ["hivemq"], expiry: 250_000), now: 0))
    XCTAssertTrue(plan(policy, now: 200_000).isEmpty)
  }

  func testPacketSizeAndChunkReceiptCapabilitiesAreEnforced() {
    let policy = ready()
    XCTAssertFalse(policy.acceptVerifiedResume(peer: "peer", route: route(epoch: 2, paths: ["unknown"]), now: 0))
    XCTAssertFalse(policy.acceptVerifiedResume(peer: "peer", route: route(epoch: 0), now: 0))
    XCTAssertFalse(policy.acceptVerifiedResume(peer: "peer", route: route(epoch: 2, expiry: 300_001), now: 0))
    XCTAssertTrue(policy.acceptVerifiedResume(peer: "peer", route: route(epoch: 2, size: 1024, chunkACKs: false), now: 0))
    XCTAssertTrue(plan(policy, size: 1025).isEmpty)
    XCTAssertTrue(plan(policy, traffic: .chunk).isEmpty)
    XCTAssertFalse(plan(policy, size: 1024).isEmpty)
  }

  func testBrokerAckIsNeitherPeerReceiptNorDeliveryLatencySample() {
    let policy = ready()
    XCTAssertTrue(policy.reserve(attemptID: "attempt", attempt: attempt()))
    XCTAssertFalse(policy.brokerAck(attemptID: "attempt", broker: "hivemq", generation: 1))
    XCTAssertTrue(policy.brokerAck(attemptID: "attempt", broker: "emqx", generation: 1))
    XCTAssertTrue(policy.pending(peer: "peer", messageID: "m"))
    XCTAssertEqual(policy.diagnostics(now: 1000).inflightPackets, 0)
    XCTAssertEqual(policy.diagnostics(now: 1000).verifiedDelivery["emqx"]?.samples, 0)
    XCTAssertTrue(policy.acceptVerifiedReceipt(peer: "other", messageID: "m", contentHash: hash, attemptID: "attempt", now: 1000).isEmpty)
    XCTAssertEqual(policy.acceptVerifiedReceipt(peer: "peer", messageID: "m", contentHash: hash, attemptID: "attempt", now: 1000), ["attempt"])
    XCTAssertEqual(policy.diagnostics(now: 1000).verifiedDelivery["emqx"], .init(samples: 1, p50: 1000, p95: nil, latest: 1000))
    XCTAssertTrue(policy.acceptVerifiedReceipt(peer: "peer", messageID: "m", contentHash: hash, attemptID: "attempt", now: 1000).isEmpty)
  }

  func testReceiptRetiresOnlyMatchingCopiesAndCannotReuseIDWithNewHash() {
    let policy = ready()
    for broker in brokers { XCTAssertTrue(policy.reserve(attemptID: broker, attempt: attempt(broker: broker))) }
    XCTAssertTrue(policy.reserve(attemptID: "another", attempt: attempt(message: "another")))
    XCTAssertFalse(policy.reserve(attemptID: "changed", attempt: attempt(digest: String(repeating: "b", count: 64))))
    XCTAssertEqual(policy.acceptVerifiedReceipt(peer: "peer", messageID: "m", contentHash: hash, attemptID: "emqx", now: 100), brokers)
    XCTAssertFalse(policy.pending(peer: "peer", messageID: "m"))
    XCTAssertTrue(policy.pending(peer: "peer", messageID: "another"))
    XCTAssertEqual(policy.diagnostics(now: 100).inflightPackets, 4)
  }

  func testReservationRefusalDoesNotConsumeCapacity() {
    let policy = ready()
    XCTAssertEqual(policy.reserveReason(attemptID: "", attempt: attempt()), .invalidAttempt)
    XCTAssertEqual(policy.reserveReason(attemptID: "old", attempt: attempt(generation: 2)), .pathUnavailable)
    XCTAssertNil(policy.reserveReason(attemptID: "valid", attempt: attempt()))
    XCTAssertEqual(policy.reserveReason(attemptID: "valid", attempt: attempt()), .duplicateAttempt)
    XCTAssertEqual(policy.reserveReason(attemptID: "changed",
      attempt: attempt(digest: String(repeating: "b", count: 64))), .messageContentConflict)
    XCTAssertEqual(policy.diagnostics(now: 1_000).inflightPackets, 1)
  }

  func testControlAndFinalMessagesKeepReservedPacketSlots() {
    let policy = ready()
    let paths = brokers.sorted()
    for index in 0..<10 {
      XCTAssertTrue(policy.reserve(attemptID: String(index), attempt: attempt(broker: paths[index % paths.count], message: String(index))))
    }
    XCTAssertEqual(policy.reserveReason(attemptID: "ordinary", attempt: attempt(message: "ordinary")), .inflightPacketLimit)
    XCTAssertTrue(policy.reserve(attemptID: "control", attempt: attempt(message: "control", traffic: .control)))
    XCTAssertTrue(policy.reserve(attemptID: "final", attempt: attempt(message: "final", traffic: .final)))
    XCTAssertFalse(policy.reserve(attemptID: "over", attempt: attempt(message: "over", traffic: .receipt)))
    XCTAssertEqual(policy.diagnostics(now: 1000).inflightPackets, 12)
  }

  func testGlobalAndPeerByteBudgetsPreserveControlCapacity() {
    let policy = ready()
    for index in 0..<7 {
      XCTAssertTrue(policy.reserve(attemptID: String(index), attempt: attempt(peer: "peer-\(index)", size: 1_048_576)))
    }
    XCTAssertEqual(policy.reserveReason(attemptID: "eighth", attempt: attempt(peer: "peer-8", size: 1_048_576)), .inflightByteLimit)
    XCTAssertTrue(policy.reserve(attemptID: "urgent", attempt: attempt(peer: "peer-8", size: 1_048_576, traffic: .control)))
    XCTAssertFalse(policy.reserve(attemptID: "too-large", attempt: attempt(peer: "peer-9", size: 1, traffic: .receipt)))
    let isolated = ready()
    XCTAssertTrue(isolated.reserve(attemptID: "one", attempt: attempt(size: 1_048_576)))
    XCTAssertEqual(isolated.reserveReason(attemptID: "two", attempt: attempt(size: 1_048_576)), .peerByteLimit)
    XCTAssertTrue(isolated.reserve(attemptID: "urgent", attempt: attempt(size: 1_048_576, traffic: .control)))
  }

  func testHedgeDelayRequiresTwentyVerifiedSamplesAndNetworkResetClearsMetrics() {
    let policy = ready()
    for index in 0..<20 {
      let id = String(index)
      XCTAssertTrue(policy.reserve(attemptID: id, attempt: attempt(broker: "mosquitto", message: id)))
      XCTAssertTrue(policy.brokerAck(attemptID: id, broker: "mosquitto", generation: 1))
      policy.acceptVerifiedReceipt(peer: "peer", messageID: id, contentHash: hash, attemptID: id, now: 20)
      XCTAssertEqual(plan(policy)[1].delayMillis, index < 19 ? 2000 : 100)
    }
    XCTAssertEqual(plan(policy).first?.brokerID, "mosquitto")
    policy.setNetwork("cellular")
    XCTAssertEqual(plan(policy)[1].delayMillis, 2000)
    XCTAssertEqual(policy.diagnostics(now: 1000).verifiedDelivery["mosquitto"]?.samples, 0)
  }

  func testDiagnosticsBoundSamplesExpireAndHideInsufficientP95() {
    let policy = ready()
    for index in 0..<40 {
      let id = String(index)
      XCTAssertTrue(policy.reserve(attemptID: id, attempt: attempt(message: id)))
      policy.brokerAck(attemptID: id, broker: "emqx", generation: 1)
      policy.acceptVerifiedReceipt(peer: "peer", messageID: id, contentHash: hash, attemptID: id, now: Int64(index + 1) * 1000)
      if index == 28 { XCTAssertNil(policy.diagnostics(now: 29_000).verifiedDelivery["emqx"]?.p95) }
    }
    XCTAssertEqual(policy.diagnostics(now: 40_000).verifiedDelivery["emqx"], .init(samples: 32, p50: 24_000, p95: 39_000, latest: 40_000))
    XCTAssertEqual(policy.diagnostics(now: 341_000).verifiedDelivery["emqx"]?.samples, 0)
  }

  func testUnattributedAndNegativeTimeReceiptsDoNotCreateSamples() {
    let policy = ready()
    policy.reserve(attemptID: "unattributed", attempt: attempt())
    policy.acceptVerifiedMessage(peer: "peer", messageID: "m", contentHash: hash)
    policy.reserve(attemptID: "negative", attempt: attempt(message: "negative"))
    policy.acceptVerifiedReceipt(peer: "peer", messageID: "negative", contentHash: hash, attemptID: "negative", now: -1)
    XCTAssertEqual(policy.diagnostics(now: 1000).verifiedDelivery["emqx"]?.samples, 0)
    policy.forgetPeer("peer")
    XCTAssertTrue(plan(policy).isEmpty)
    XCTAssertEqual(policy.diagnostics(now: 1000).pendingAttempts, 0)
  }

  func testChunkRetryAvoidsPreviouslyAttemptedPath() throws {
    let policy = ready()
    let first = try XCTUnwrap(plan(policy, traffic: .chunk).first?.brokerID)
    XCTAssertNotEqual(plan(policy, traffic: .chunk, attempted: [first]).first?.brokerID, first)
    XCTAssertFalse(plan(policy, traffic: .chunk, attempted: brokers).isEmpty)
  }

  func testVerifiedChunkThroughputChangesSelectionOnlyAfterThreeSamples() {
    let policy = ready()
    for index in 0..<3 {
      let chunk = MqttChunkThroughput.Chunk(transfer: "transfer", request: "request", index: index, sampleEligible: true)
      policy.trackChunk(peer: "peer", chunk: chunk, broker: "emqx", generation: 1, bytes: 1024, now: Int64(index) * 1000)
      policy.confirmChunkState(peer: "peer", transfer: "transfer", request: "request", indices: [index], now: Int64(index) * 1000 + 100)
    }
    XCTAssertNotEqual(plan(policy, traffic: .chunk, size: 400_000, now: 3000).first?.brokerID, "emqx")
  }

  func testBrokerACKDoesNotReleasePeerWindowAndControlCanStillPass() {
    let policy = ready()
    let chunk = MqttChunkThroughput.Chunk(transfer: "transfer", request: "request", index: 0, sampleEligible: true)
    XCTAssertTrue(policy.reserveChunk(attemptID: "chunk", attempt: attempt(size: 256 * 1024, traffic: .chunk), chunk: chunk))
    XCTAssertTrue(policy.brokerAck(attemptID: "chunk", broker: "emqx", generation: 1))
    XCTAssertEqual(policy.reserveReason(attemptID: "blocked", attempt: attempt(size: 1, traffic: .chunk)), .chunkWindowLimit)
    XCTAssertFalse(plan(policy, traffic: .chunk).contains { $0.brokerID == "emqx" })
    XCTAssertTrue(policy.reserve(attemptID: "control", attempt: attempt(message: "control", traffic: .control)))
    policy.confirmChunkState(peer: "other", transfer: "transfer", request: "request", indices: [0], now: 100)
    XCTAssertEqual(policy.reserveReason(attemptID: "still-blocked", attempt: attempt(size: 1, traffic: .chunk)), .chunkWindowLimit)
    policy.confirmChunkState(peer: "peer", transfer: "transfer", request: "request", indices: [0], now: 100)
    XCTAssertTrue(policy.reserve(attemptID: "released", attempt: attempt(size: 1, traffic: .chunk)))
  }

  func testSmallMessagesAndReceiptsAvoidUnconfirmedImageBacklog() {
    let policy = ready()
    let chunk = MqttChunkThroughput.Chunk(transfer: "transfer", request: "request", index: 0, sampleEligible: true)
    XCTAssertTrue(policy.reserveChunk(attemptID: "chunk", attempt: attempt(size: 256 * 1024, traffic: .chunk), chunk: chunk))
    policy.brokerAck(attemptID: "chunk", broker: "emqx", generation: 1)
    XCTAssertNotEqual(plan(policy).first?.brokerID, "emqx")
    XCTAssertNotEqual(plan(policy, traffic: .receipt, ingress: "emqx").first?.brokerID, "emqx")
  }

  func testAttemptExpirationAndDisconnectReleaseCapacity() {
    let policy = ready()
    policy.reserve(attemptID: "expired", attempt: attempt())
    XCTAssertEqual(policy.expireAttempts(before: 1), ["expired"])
    XCTAssertEqual(policy.diagnostics(now: 1000).pendingAttempts, 0)
    policy.reserve(attemptID: "disconnected", attempt: attempt())
    policy.synchronize([:])
    XCTAssertEqual(policy.diagnostics(now: 1000).inflightPackets, 0)
    XCTAssertTrue(policy.pending(peer: "peer", messageID: "m"))
  }

  private func route(epoch: Int64 = 1, paths: Set<String>? = nil, expiry: Int64 = 300_000,
                     size: Int = MqttRouteProtocol.packetBytes, chunkACKs: Bool = true) -> MqttMultipathPolicy.PeerRoute {
    .init(epoch: epoch, receiveBrokers: paths ?? brokers, packetBytes: size, chunkACKs: chunkACKs, expiresAt: expiry)
  }
  private func path(_ broker: String, generation: Int64 = 1, topics: Set<String> = ["inbox"]) -> MqttBrokerPathSnapshot {
    .init(brokerID: broker, generation: generation, connected: true, subscriptions: topics)
  }
  private func snapshots() -> [String: MqttBrokerPathSnapshot] { Dictionary(uniqueKeysWithValues: brokers.map { ($0, path($0)) }) }
  private func ready() -> MqttMultipathPolicy {
    let policy = MqttMultipathPolicy(tieSeed: Data("deterministic-test".utf8))
    policy.synchronize(snapshots())
    XCTAssertTrue(policy.acceptVerifiedResume(peer: "peer", route: route(), now: 0))
    return policy
  }
  private func plan(_ policy: MqttMultipathPolicy, traffic: MqttMultipathPolicy.Traffic = .message,
                    message: String = "m", peer: String = "peer", size: Int = 100, now: Int64 = 1000,
                    ingress: String? = nil, attempted: Set<String> = []) -> [MqttMultipathPolicy.Dispatch] {
    policy.plan(peer: peer, messageID: message, traffic: traffic, wireBytes: size, receiveTopics: ["inbox"], now: now,
                ingress: ingress, attempted: attempted)
  }
  private func attempt(broker: String = "emqx", generation: Int64 = 1, message: String = "m", peer: String = "peer",
                       size: Int = 100, traffic: MqttMultipathPolicy.Traffic = .message, digest: String? = nil) -> MqttMultipathPolicy.Attempt {
    .init(peer: peer, messageID: message, contentHash: digest ?? hash, brokerID: broker, generation: generation,
          wireBytes: size, traffic: traffic, startedAt: 0)
  }
}

// Network-epoch sampling fixtures; authored only unless executed by XCTest.
extension MqttMultipathPolicyTests {
  func testOldNetworkReceiptCompletesMessageWithoutTrainingNewNetworkRTT() {
    let policy = ready()
    policy.setNetwork("first")
    XCTAssertTrue(policy.reserve(attemptID: "old", attempt: attempt()))
    policy.setNetwork("second")
    XCTAssertTrue(policy.pending(peer: "peer", messageID: "m"))
    XCTAssertEqual(policy.diagnostics(now: 50).inflightPackets, 1)
    XCTAssertEqual(policy.acceptVerifiedReceipt(peer: "peer", messageID: "m", contentHash: hash, attemptID: "old", now: 100), ["old"])
    XCTAssertEqual(policy.diagnostics(now: 100).verifiedDelivery["emqx"]?.samples, 0)
    XCTAssertEqual(policy.diagnostics(now: 100).inflightPackets, 1)
    XCTAssertTrue(policy.brokerAck(attemptID: "old", broker: "emqx", generation: 1))
    XCTAssertEqual(policy.diagnostics(now: 100).pendingAttempts, 0)
  }

  func testSameNetworkKeyKeepsSamplesAndPendingAttemptEligibility() {
    let policy = ready()
    policy.setNetwork("first")
    XCTAssertTrue(policy.reserve(attemptID: "first", attempt: attempt(message: "first")))
    policy.acceptVerifiedReceipt(peer: "peer", messageID: "first", contentHash: hash, attemptID: "first", now: 10)
    policy.brokerAck(attemptID: "first", broker: "emqx", generation: 1)
    XCTAssertTrue(policy.reserve(attemptID: "next", attempt: attempt(message: "next")))
    policy.setNetwork("first")
    XCTAssertEqual(policy.diagnostics(now: 20).verifiedDelivery["emqx"]?.samples, 1)
    policy.acceptVerifiedReceipt(peer: "peer", messageID: "next", contentHash: hash, attemptID: "next", now: 20)
    XCTAssertEqual(policy.diagnostics(now: 20).verifiedDelivery["emqx"]?.samples, 2)
  }

  func testReturningToAnEarlierNetworkKeyDoesNotReviveOldAttemptSamples() {
    let policy = ready()
    policy.setNetwork("first")
    XCTAssertTrue(policy.reserve(attemptID: "old", attempt: attempt()))
    policy.setNetwork("second"); policy.setNetwork("first")
    XCTAssertEqual(policy.acceptVerifiedReceipt(peer: "peer", messageID: "m", contentHash: hash, attemptID: "old", now: 100), ["old"])
    XCTAssertEqual(policy.diagnostics(now: 100).verifiedDelivery["emqx"]?.samples, 0)
  }

  func testNewNetworkAttemptsStillTrainOnlyOnceAfterVerifiedReceipt() {
    let policy = ready()
    policy.setNetwork("first"); policy.setNetwork("second")
    XCTAssertTrue(policy.reserve(attemptID: "new", attempt: attempt()))
    XCTAssertTrue(policy.brokerAck(attemptID: "new", broker: "emqx", generation: 1))
    XCTAssertEqual(policy.diagnostics(now: 100).verifiedDelivery["emqx"]?.samples, 0)
    XCTAssertEqual(policy.acceptVerifiedReceipt(peer: "peer", messageID: "m", contentHash: hash, attemptID: "new", now: 100), ["new"])
    XCTAssertTrue(policy.acceptVerifiedReceipt(peer: "peer", messageID: "m", contentHash: hash, attemptID: "new", now: 200).isEmpty)
    XCTAssertEqual(policy.diagnostics(now: 200).verifiedDelivery["emqx"], .init(samples: 1, p50: 100, p95: nil, latest: 100))
  }

  func testOldNetworkWinnerCompletesNewHedgeWithoutCreatingAnAttributedSample() {
    let policy = ready()
    policy.setNetwork("first")
    XCTAssertTrue(policy.reserve(attemptID: "old", attempt: attempt()))
    policy.setNetwork("second")
    XCTAssertTrue(policy.reserve(attemptID: "new", attempt: attempt(broker: "hivemq")))
    XCTAssertEqual(policy.acceptVerifiedReceipt(peer: "peer", messageID: "m", contentHash: hash, attemptID: "old", now: 100), ["old", "new"])
    XCTAssertTrue(policy.acceptVerifiedReceipt(peer: "peer", messageID: "m", contentHash: hash, attemptID: "new", now: 110).isEmpty)
    XCTAssertTrue(policy.diagnostics(now: 200).verifiedDelivery.values.allSatisfy { $0.samples == 0 })
    XCTAssertTrue(policy.brokerAck(attemptID: "old", broker: "emqx", generation: 1))
    XCTAssertTrue(policy.brokerAck(attemptID: "new", broker: "hivemq", generation: 1))
    XCTAssertEqual(policy.diagnostics(now: 200).pendingAttempts, 0)
  }

  func testNetworkResetDiscardsOldChunkMetricFlightsWithoutChangingReadyRoutes() {
    let policy = ready(), chunk = MqttChunkThroughput.Chunk(transfer: "transfer", request: "request", index: 0, sampleEligible: true)
    policy.trackChunk(peer: "peer", chunk: chunk, broker: "emqx", generation: 1, bytes: 100, now: 0)
    XCTAssertTrue(policy.chunkPending(peer: "peer", chunk: chunk, now: 0))
    policy.setNetwork("next")
    XCTAssertFalse(policy.chunkPending(peer: "peer", chunk: chunk, now: 1))
    let before = plan(policy, traffic: .chunk)
    policy.confirmChunkState(peer: "peer", transfer: "transfer", request: "request", indices: [0], now: 100)
    XCTAssertEqual(plan(policy, traffic: .chunk), before)
    XCTAssertEqual(policy.readyBrokers(receiveTopics: ["inbox"]), brokers)
  }
}
