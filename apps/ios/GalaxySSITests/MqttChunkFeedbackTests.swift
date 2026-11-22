import XCTest
@testable import GalaxySSI

final class MqttChunkFeedbackTests: XCTestCase {
  private let transfer = String(repeating: "a", count: 64)
  private let request = String(repeating: "b", count: 32)

  func testLatestRevisionKeepsFirstDeadlineAndRetriesBackpressure() async {
    let feedback = MqttChunkFeedback()
    var values: [Int] = []
    var accepted = false
    _ = feedback.offer(scope: "pair", transfer: transfer, request: request, revision: 1, now: 1000) { values.append(1); return true }
    _ = feedback.offer(scope: "pair", transfer: transfer, request: request, revision: 2, now: 1199) { values.append(2); return accepted }
    XCTAssertTrue(feedback.drain(now: 1199).isEmpty)
    for send in feedback.drain(now: 1200) { await send() }
    XCTAssertEqual(values, [2])
    XCTAssertEqual(feedback.count, 1)
    XCTAssertTrue(feedback.drain(now: 1699).isEmpty)
    accepted = true
    for send in feedback.drain(now: 1700) { await send() }
    XCTAssertEqual(values, [2, 2])
    XCTAssertEqual(feedback.count, 0)
  }

  func testOlderUrgentRevisionCannotReplaceAndLateSuccessCannotEraseNewerBitmap() async {
    let feedback = MqttChunkFeedback()
    var values: [Int] = []
    _ = feedback.offer(scope: "pair", transfer: transfer, request: request, revision: 3, now: 0) {
      _ = feedback.offer(scope: "pair", transfer: self.transfer, request: self.request, revision: 4, now: 201) {
        values.append(4); return true
      }
      values.append(3)
      return true
    }
    XCTAssertNil(feedback.offer(scope: "pair", transfer: transfer, request: request, revision: 2, now: 10, urgent: true) { true })
    for send in feedback.drain(now: 200) { await send() }
    XCTAssertEqual(feedback.count, 1)
    for send in feedback.drain(now: 700) { await send() }
    XCTAssertEqual(values, [3, 4])
    XCTAssertEqual(feedback.count, 0)
  }

  func testClaimIsNotDuplicatedAndRetirementCancelsSelectedCallback() async {
    let feedback = MqttChunkFeedback()
    var sent = false
    let urgent = feedback.offer(scope: "pair", transfer: transfer, request: request, revision: 0, now: 0, urgent: true) {
      sent = true; return true
    }
    XCTAssertNotNil(urgent)
    XCTAssertTrue(feedback.drain(now: 500).isEmpty)
    feedback.forget(scope: "pair")
    await urgent?()
    XCTAssertFalse(sent)
    XCTAssertEqual(feedback.count, 0)
  }

  func testExpiryAndDrainLimitBoundRetainedFailures() async {
    let feedback = MqttChunkFeedback()
    var values: [Int] = []
    for index in 0..<20 {
      _ = feedback.offer(scope: "pair-\(index)", transfer: transfer, request: request, revision: 0, now: 0) {
        values.append(index); return false
      }
    }
    XCTAssertTrue(feedback.drain(now: 200, limit: 0).isEmpty)
    for send in feedback.drain(now: 200, limit: 100) { await send() }
    XCTAssertEqual(values, Array(0..<16))
    for send in feedback.drain(now: 200) { await send() }
    XCTAssertEqual(values, Array(0..<20))
    XCTAssertTrue(feedback.drain(now: 30_000).isEmpty)
    XCTAssertEqual(feedback.count, 0)
  }

  func testUrgentFeedbackSharesPeerAndGlobalCapacity() {
    let feedback = MqttChunkFeedback()
    for index in 0..<65 {
      _ = feedback.offer(scope: "pair", transfer: String(format: "%064x", index), request: request, revision: 0, now: 0) { false }
    }
    XCTAssertEqual(feedback.count, 64)
    XCTAssertNil(feedback.offer(scope: "pair", transfer: transfer, request: request, revision: 0, now: 0, urgent: true) { false })
    feedback.clear()
    for index in 0..<1025 {
      _ = feedback.offer(scope: "pair-\(index)", transfer: transfer, request: request, revision: 0, now: 0) { false }
    }
    XCTAssertEqual(feedback.count, 1024)
    XCTAssertNil(feedback.offer(scope: "urgent", transfer: transfer, request: request, revision: 0, now: 0, urgent: true) { false })
  }

  func testInvalidTimeIdentityAndRevisionDoNotConsumeCapacity() {
    let feedback = MqttChunkFeedback()
    for time in [-1, Int64.max] {
      XCTAssertNil(feedback.offer(scope: "pair", transfer: transfer, request: request, revision: 0, now: time) { true })
    }
    XCTAssertNil(feedback.offer(scope: "", transfer: transfer, request: request, revision: 0, now: 0) { true })
    XCTAssertNil(feedback.offer(scope: "pair", transfer: "invalid", request: request, revision: 0, now: 0) { true })
    XCTAssertNil(feedback.offer(scope: "pair", transfer: transfer, request: "invalid", revision: 0, now: 0) { true })
    XCTAssertNil(feedback.offer(scope: "pair", transfer: transfer, request: request, revision: -1, now: 0) { true })
    XCTAssertEqual(feedback.count, 0)
  }
}
