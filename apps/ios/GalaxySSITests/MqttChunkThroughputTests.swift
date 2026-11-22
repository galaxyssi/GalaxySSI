import XCTest
@testable import GalaxySSI

final class MqttChunkThroughputTests: XCTestCase {
  func testThreeCommittedSamplesAreRequiredAndOldRatesExpire() {
    let throughput = MqttChunkThroughput()
    for index in 0..<3 {
      throughput.track(peer: "peer", chunk: chunk(index), broker: "emqx", generation: 1, bytes: 1024, now: Int64(index) * 1000)
      XCTAssertEqual(throughput.pendingBytes(broker: "emqx"), 1024)
      throughput.confirmed(peer: "peer", transfer: "transfer", request: "request", indices: [index], generations: ["emqx": 1], now: Int64(index) * 1000 + 100)
      XCTAssertEqual(throughput.rate(peer: "peer", broker: "emqx"), index == 2 ? 10_240 : 262_144)
      XCTAssertEqual(throughput.pendingBytes(broker: "emqx"), 0)
    }
    throughput.expire(now: 302_101)
    XCTAssertEqual(throughput.rate(peer: "peer", broker: "emqx"), 262_144)
  }

  func testRetransmissionsCannotCreateAmbiguousThroughputSamples() {
    let throughput = MqttChunkThroughput()
    for index in 0..<3 {
      throughput.track(peer: "peer", chunk: chunk(index), broker: "emqx", generation: 1, bytes: 1024, now: 0)
      throughput.track(peer: "peer", chunk: chunk(index), broker: "hivemq", generation: 1, bytes: 1024, now: 10)
      throughput.confirmed(peer: "peer", transfer: "transfer", request: "request", indices: [index], generations: ["emqx": 1, "hivemq": 1], now: 100)
    }
    XCTAssertEqual(throughput.rate(peer: "peer", broker: "emqx"), 262_144)
    XCTAssertEqual(throughput.rate(peer: "peer", broker: "hivemq"), 262_144)
  }

  func testStaleGenerationAndWrongPeerCannotProduceMeasurements() {
    let throughput = MqttChunkThroughput()
    for index in 0..<3 {
      throughput.track(peer: "peer", chunk: chunk(index), broker: "emqx", generation: 1, bytes: 1024, now: 0)
      throughput.confirmed(peer: "other", transfer: "transfer", request: "request", indices: [index], generations: ["emqx": 1], now: 100)
      XCTAssertEqual(throughput.pendingBytes(broker: "emqx"), 1024)
      throughput.confirmed(peer: "peer", transfer: "transfer", request: "request", indices: [index], generations: ["emqx": 2], now: 100)
    }
    XCTAssertEqual(throughput.rate(peer: "peer", broker: "emqx"), 262_144)
  }

  func testNewRequestDiscardsOnlyOlderObservationsForSamePeerAndTransfer() {
    let throughput = MqttChunkThroughput()
    throughput.track(peer: "peer", chunk: chunk(0), broker: "emqx", generation: 1, bytes: 1024, now: 0)
    throughput.track(peer: "other", chunk: chunk(0), broker: "emqx", generation: 1, bytes: 512, now: 0)
    let newer = MqttChunkThroughput.Chunk(transfer: "transfer", request: "new", index: 0, sampleEligible: true)
    throughput.track(peer: "peer", chunk: newer, broker: "hivemq", generation: 1, bytes: 2048, now: 10)
    XCTAssertEqual(throughput.pendingBytes(broker: "emqx"), 512)
    XCTAssertEqual(throughput.pendingBytes(broker: "hivemq"), 2048)
    throughput.forget(peer: "peer")
    XCTAssertEqual(throughput.pendingBytes(broker: "emqx"), 512)
    XCTAssertEqual(throughput.pendingBytes(broker: "hivemq"), 0)
    throughput.reset()
    XCTAssertEqual(throughput.pendingBytes(broker: "emqx"), 0)
  }

  func testExpiredUncertainAndZeroTimeSamplesDoNotTrainRate() {
    let throughput = MqttChunkThroughput()
    for index in 0..<3 {
      let uncertain = MqttChunkThroughput.Chunk(transfer: "transfer", request: "request", index: index, sampleEligible: false)
      throughput.track(peer: "peer", chunk: uncertain, broker: "emqx", generation: 1, bytes: 1024, now: 0)
      throughput.confirmed(peer: "peer", transfer: "transfer", request: "request", indices: [index], generations: ["emqx": 1], now: 100)
    }
    throughput.track(peer: "peer", chunk: chunk(0), broker: "emqx", generation: 1, bytes: 1024, now: 1000)
    throughput.confirmed(peer: "peer", transfer: "transfer", request: "request", indices: [0], generations: ["emqx": 1], now: 1000)
    throughput.track(peer: "peer", chunk: chunk(1), broker: "emqx", generation: 1, bytes: 1024, now: 1000)
    throughput.expire(now: 31_001)
    XCTAssertEqual(throughput.pendingBytes(broker: "emqx"), 0)
    XCTAssertEqual(throughput.rate(peer: "peer", broker: "emqx"), 262_144)
  }

  func testInitialWindowIsSharedAcrossPeersOnOneBroker() {
    let throughput = MqttChunkThroughput()
    throughput.track(peer: "peer", chunk: chunk(0), broker: "emqx", generation: 1, bytes: 256 * 1024, now: 0)
    XCTAssertFalse(throughput.canSend(peer: "peer", broker: "emqx", bytes: 1))
    XCTAssertFalse(throughput.canSend(peer: "other", broker: "emqx", bytes: 1))
    XCTAssertTrue(throughput.canSend(peer: "peer", broker: "hivemq", bytes: 256 * 1024))
    throughput.confirmed(peer: "other", transfer: "transfer", request: "request", indices: [0], generations: ["emqx": 1], now: 100)
    XCTAssertFalse(throughput.canSend(peer: "peer", broker: "emqx", bytes: 1))
    throughput.confirmed(peer: "peer", transfer: "transfer", request: "request", indices: [0], generations: ["emqx": 1], now: 100)
    throughput.track(peer: "peer", chunk: chunk(1), broker: "emqx", generation: 1, bytes: 256 * 1024, now: 101)
    XCTAssertTrue(throughput.canSend(peer: "peer", broker: "emqx", bytes: 256 * 1024))
    XCTAssertFalse(throughput.canSend(peer: "peer", broker: "emqx", bytes: 256 * 1024 + 1))
  }

  func testExpiryHalvesWindowOncePerPathAndLegacyOversizeCanProgressAlone() {
    let throughput = MqttChunkThroughput()
    for index in 0..<2 {
      throughput.track(peer: "peer", chunk: chunk(index), broker: "emqx", generation: 1, bytes: 128 * 1024, now: 0)
    }
    throughput.expire(now: 30_001)
    throughput.expire(now: 30_002)
    XCTAssertTrue(throughput.canSend(peer: "peer", broker: "emqx", bytes: 380 * 1024))
    throughput.track(peer: "peer", chunk: chunk(2), broker: "emqx", generation: 1, bytes: 64 * 1024, now: 30_002)
    XCTAssertTrue(throughput.canSend(peer: "peer", broker: "emqx", bytes: 64 * 1024))
    XCTAssertFalse(throughput.canSend(peer: "peer", broker: "emqx", bytes: 64 * 1024 + 1))
    XCTAssertFalse(throughput.canSend(peer: "peer", broker: "emqx", bytes: 0))
  }

  private func chunk(_ index: Int) -> MqttChunkThroughput.Chunk {
    .init(transfer: "transfer", request: "request", index: index, sampleEligible: true)
  }
}
