import XCTest
@testable import GalaxySSI

final class MqttChunkFeedbackTests: XCTestCase {
  private let transfer = String(repeating: "a", count: 64)
  private let request = String(repeating: "b", count: 32)

  func testLatestRevisionReplacesCallbackWithoutExtendingFirstDeadline() {
    let feedback = MqttChunkFeedback()
    var values: [Int] = []
    _ = feedback.offer(scope: "pair", transfer: transfer, request: request, revision: 1, now: 1000) { values.append(1) }
    _ = feedback.offer(scope: "pair", transfer: transfer, request: request, revision: 2, now: 1199) { values.append(2) }
    XCTAssertTrue(feedback.drain(now: 1199).isEmpty)
    feedback.drain(now: 1200).forEach { $0() }
    XCTAssertEqual(values, [2])
    XCTAssertEqual(feedback.count, 0)
  }

  func testOlderNormalAndUrgentRevisionsCannotReplacePendingState() {
    let feedback = MqttChunkFeedback()
    var values: [Int] = []
    _ = feedback.offer(scope: "pair", transfer: transfer, request: request, revision: 3, now: 0) { values.append(3) }
    _ = feedback.offer(scope: "pair", transfer: transfer, request: request, revision: 2, now: 10) { values.append(2) }
    let stale = feedback.offer(scope: "pair", transfer: transfer, request: request, revision: 1, now: 20, urgent: true) { values.append(1) }
    XCTAssertNil(stale)
    feedback.drain(now: 200).forEach { $0() }
    XCTAssertEqual(values, [3])
  }

  func testUrgentCallbackIsReturnedWithoutRunningUnderLockOrDuplicatingAtDrain() {
    let feedback = MqttChunkFeedback()
    var values: [Int] = []
    _ = feedback.offer(scope: "pair", transfer: transfer, request: request, revision: 1, now: 0) { values.append(1) }
    let immediate = feedback.offer(scope: "pair", transfer: transfer, request: request, revision: 2, now: 10, urgent: true) {
      feedback.forget(scope: "pair")
      values.append(2)
    }
    XCTAssertTrue(values.isEmpty)
    immediate?()
    XCTAssertEqual(values, [2])
    XCTAssertTrue(feedback.drain(now: 200).isEmpty)
  }

  func testScopeAndRequestIsolationWithRetirementAndClear() {
    let feedback = MqttChunkFeedback()
    let nextRequest = String(repeating: "c", count: 32)
    var values: [String] = []
    _ = feedback.offer(scope: "old-pair", transfer: transfer, request: request, revision: 1, now: 0) { values.append("old") }
    _ = feedback.offer(scope: "new-pair", transfer: transfer, request: request, revision: 0, now: 0) { values.append("new") }
    _ = feedback.offer(scope: "new-pair", transfer: transfer, request: nextRequest, revision: 0, now: 0) { values.append("next") }
    feedback.forget(scope: "old-pair")
    feedback.drain(now: 200).forEach { $0() }
    XCTAssertEqual(values, ["new", "next"])
    _ = feedback.offer(scope: "new-pair", transfer: transfer, request: request, revision: 0, now: 1000) { values.append("cleared") }
    feedback.clear()
    XCTAssertTrue(feedback.drain(now: 1200).isEmpty)
  }

  func testDrainLimitIsBoundedAndPreservesInsertionOrder() {
    let feedback = MqttChunkFeedback()
    var values: [Int] = []
    for index in 0..<20 {
      _ = feedback.offer(scope: "pair-\(index)", transfer: transfer, request: request, revision: 0, now: 0) { values.append(index) }
    }
    XCTAssertTrue(feedback.drain(now: 200, limit: 0).isEmpty)
    feedback.drain(now: 200, limit: 100).forEach { $0() }
    XCTAssertEqual(values, Array(0..<16))
    feedback.drain(now: 200).forEach { $0() }
    XCTAssertEqual(values, Array(0..<20))
  }

  func testPerPeerAndGlobalCapacityStillAllowReplacingExistingEntries() {
    let feedback = MqttChunkFeedback()
    for index in 0..<65 {
      let id = String(format: "%064x", index)
      _ = feedback.offer(scope: "pair", transfer: id, request: request, revision: 0, now: 0) { }
    }
    XCTAssertEqual(feedback.count, 64)
    var replaced = false
    _ = feedback.offer(scope: "pair", transfer: String(repeating: "0", count: 64), request: request, revision: 1, now: 10) { replaced = true }
    feedback.drain(now: 200, limit: 1).forEach { $0() }
    XCTAssertTrue(replaced)
    feedback.clear()
    for index in 0..<1025 {
      _ = feedback.offer(scope: "pair-\(index)", transfer: transfer, request: request, revision: 0, now: 0) { }
    }
    XCTAssertEqual(feedback.count, 1024)
    let urgent = feedback.offer(scope: "urgent", transfer: transfer, request: request, revision: 0, now: 0, urgent: true) { }
    XCTAssertNotNil(urgent)
    XCTAssertEqual(feedback.count, 1024)
  }

  func testInvalidTimeIdentityAndRevisionDoNotConsumeCapacity() {
    let feedback = MqttChunkFeedback()
    for time in [-1, Int64.max] {
      XCTAssertNil(feedback.offer(scope: "pair", transfer: transfer, request: request, revision: 0, now: time) { })
    }
    XCTAssertNil(feedback.offer(scope: "", transfer: transfer, request: request, revision: 0, now: 0) { })
    XCTAssertNil(feedback.offer(scope: "pair", transfer: "invalid", request: request, revision: 0, now: 0) { })
    XCTAssertNil(feedback.offer(scope: "pair", transfer: transfer, request: "invalid", revision: 0, now: 0) { })
    XCTAssertNil(feedback.offer(scope: "pair", transfer: transfer, request: request, revision: -1, now: 0) { })
    XCTAssertEqual(feedback.count, 0)
  }
}
