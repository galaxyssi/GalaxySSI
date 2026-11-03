import XCTest
@testable import GalaxySSI

final class MqttReceiptRetryTests: XCTestCase {
  func testRejectedEnqueueRetriesAfter500MillisecondsAndSuccessRemovesEntry() async {
    let retries = MqttReceiptRetry()
    let probe = ReceiptRetryProbe()
    let admitted = await retries.offer(scope: "pair", message: "message", attempt: "attempt", now: 1000) {
      await probe.send("message", successAt: 2)
    }
    XCTAssertTrue(admitted)
    await retries.drain(now: 1499)
    let early = await probe.count("message")
    XCTAssertEqual(early, 1)
    await retries.drain(now: 1500)
    let sent = await probe.count("message")
    let pending = await retries.count
    XCTAssertEqual(sent, 2)
    XCTAssertEqual(pending, 0)
    await retries.drain(now: 2000)
    let final = await probe.count("message")
    XCTAssertEqual(final, 2)
  }

  func testDuplicateOfferCannotExtendRetryLifetimeOrReplaceSender() async {
    let retries = MqttReceiptRetry()
    let probe = ReceiptRetryProbe()
    _ = await retries.offer(scope: "pair", message: "message", attempt: "attempt", now: 1000) { await probe.send("original") }
    let duplicate = await retries.offer(scope: "pair", message: "message", attempt: "attempt", now: 30999) { await probe.send("replacement") }
    XCTAssertFalse(duplicate)
    await retries.drain(now: 31000)
    let pending = await retries.count
    let replacements = await probe.count("replacement")
    XCTAssertEqual(pending, 0)
    XCTAssertEqual(replacements, 0)
  }

  func testThrownSendFailureRemainsEligibleForRetry() async {
    let retries = MqttReceiptRetry()
    let probe = ReceiptRetryProbe()
    _ = await retries.offer(scope: "pair", message: "message", attempt: "attempt", now: 1000) { try await probe.throwingSend() }
    await retries.drain(now: 1500)
    let attempts = await probe.count("throwing")
    let pending = await retries.count
    XCTAssertEqual(attempts, 2)
    XCTAssertEqual(pending, 1)
  }

  func testDrainIsBoundedAndMakesProgressAcrossMessages() async {
    let retries = MqttReceiptRetry()
    let probe = ReceiptRetryProbe()
    for index in 0..<20 {
      let id = String(index)
      _ = await retries.offer(scope: "pair", message: id, attempt: "attempt", now: 1000) { await probe.send(id) }
    }
    await retries.drain(now: 1500, limit: 100)
    let firstPass = await probe.allCounts()
    XCTAssertEqual(firstPass.values.filter { $0 == 2 }.count, 16)
    XCTAssertEqual(firstPass.values.filter { $0 == 1 }.count, 4)
    await retries.drain(now: 1500)
    let secondPass = await probe.allCounts()
    XCTAssertTrue(secondPass.values.allSatisfy { $0 == 2 })
    await retries.drain(now: 2000, limit: 0)
    let noOp = await probe.allCounts()
    XCTAssertEqual(noOp, secondPass)
  }

  func testPerPeerAndGlobalAdmissionBounds() async {
    let retries = MqttReceiptRetry()
    for index in 0..<64 {
      let admitted = await retries.offer(scope: "one", message: String(index), attempt: "a", now: 1000) { false }
      XCTAssertTrue(admitted)
    }
    let overPeer = await retries.offer(scope: "one", message: "extra", attempt: "a", now: 1000) { false }
    XCTAssertFalse(overPeer)
    await retries.clear()
    for index in 0..<1025 {
      let admitted = await retries.offer(scope: "peer-\(index / 64)", message: String(index), attempt: "a", now: 1000) { false }
      XCTAssertEqual(admitted, index < 1024)
    }
    let count = await retries.count
    XCTAssertEqual(count, 1024)
    await retries.drain(now: 31000)
    let expired = await retries.count
    XCTAssertEqual(expired, 0)
  }

  func testForgetDuringSendDoesNotReinsertRetiredPeer() async {
    let retries = MqttReceiptRetry()
    _ = await retries.offer(scope: "other", message: "m", attempt: "a", now: 1000) { false }
    _ = await retries.offer(scope: "retired", message: "m", attempt: "a", now: 1000) {
      await retries.forget(scope: "retired")
      return false
    }
    let remaining = await retries.count
    XCTAssertEqual(remaining, 1)
    await retries.forget(scope: "other")
    let cleared = await retries.count
    XCTAssertEqual(cleared, 0)
  }

  func testCompletionOfOldSendCannotRemoveReplacementEntry() async {
    let retries = MqttReceiptRetry()
    let probe = ReceiptRetryProbe()
    _ = await retries.offer(scope: "pair", message: "m", attempt: "a", now: 1000) {
      await retries.clear()
      _ = await retries.offer(scope: "pair", message: "m", attempt: "a", now: 1000) { await probe.send("new") }
      return true
    }
    let pending = await retries.count
    XCTAssertEqual(pending, 1)
    await retries.drain(now: 1500)
    let calls = await probe.count("new")
    XCTAssertEqual(calls, 2)
  }

  func testReentrantDuplicateDoesNotRunAnotherSender() async {
    let retries = MqttReceiptRetry()
    let probe = ReceiptRetryProbe()
    _ = await retries.offer(scope: "pair", message: "m", attempt: "a", now: 1000) {
      _ = await retries.offer(scope: "pair", message: "m", attempt: "a", now: 1000) { await probe.send("duplicate") }
      return false
    }
    let count = await probe.count("duplicate")
    XCTAssertEqual(count, 0)
  }

  func testInvalidBoundsCannotOverflowExpiryOrConsumeCapacity() async {
    let retries = MqttReceiptRetry()
    let overflow = await retries.offer(scope: "pair", message: "m", attempt: "a", now: Int64.max) { false }
    let negative = await retries.offer(scope: "pair", message: "m", attempt: "a", now: -1) { false }
    let oversized = await retries.offer(scope: String(repeating: "x", count: 513), message: "m", attempt: "a", now: 1000) { false }
    XCTAssertFalse(overflow)
    XCTAssertFalse(negative)
    XCTAssertFalse(oversized)
    let count = await retries.count
    XCTAssertEqual(count, 0)
  }
}

private actor ReceiptRetryProbe {
  private var calls: [String: Int] = [:]
  func send(_ id: String, successAt: Int = Int.max) -> Bool {
    calls[id, default: 0] += 1
    return calls[id, default: 0] >= successAt
  }
  func throwingSend() throws -> Bool {
    calls["throwing", default: 0] += 1
    throw MqttChunkStorageError.databaseFailure
  }
  func count(_ id: String) -> Int { calls[id, default: 0] }
  func allCounts() -> [String: Int] { calls }
}
