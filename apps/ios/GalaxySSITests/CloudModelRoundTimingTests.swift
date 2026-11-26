import Foundation
import XCTest
@testable import GalaxySSI

final class CloudModelRoundTimingTests: XCTestCase {
  func testTimingRecordsFirstActivityAndTerminalOutcomeOnlyOnce() {
    let recorder = CloudModelRoundTimingRecorder()
    var now: Int64 = 100
    let timing = CloudModelRoundTiming(requestId: "request", round: 2, route: .streaming, finalRound: false,
      clock: { now }, sink: recorder.append)
    timing.activity(.text)
    now = 110
    timing.request(inputCharacters: 42)
    timing.request(inputCharacters: 99)
    now = 125
    timing.activity(.tool)
    timing.activity(.text)
    now = 140
    timing.finish(completed: true, failed: false, cancelled: false)
    timing.finish(completed: false, failed: true, cancelled: true)
    timing.activity(.text)
    let samples = recorder.samples
    XCTAssertEqual(samples.map(\.stage), [.request, .firstActivity, .finished])
    XCTAssertEqual(samples.map(\.elapsedMillis), [10, 25, 40])
    XCTAssertEqual(samples.first?.inputCharacters, 42)
    XCTAssertEqual(samples[1].activity, .tool)
    XCTAssertEqual(samples.last?.completion, .completed)
    XCTAssertTrue(samples.allSatisfy { $0.round == 2 && $0.route == .streaming && !$0.finalRound })
  }

  func testCitationDurationIsIndependentOfTheFinishedProviderSpan() {
    let recorder = CloudModelRoundTimingRecorder()
    var now: Int64 = 100
    let timing = CloudModelRoundTiming(requestId: "request", round: 0, route: .compatibility, finalRound: true,
      clock: { now }, sink: recorder.append)
    timing.request(inputCharacters: 3)
    now = 800
    timing.finish(completed: true, failed: false, cancelled: false)
    now = 920
    timing.citationValidation(startedAtMillis: 900, requiresRepair: true)
    XCTAssertEqual(recorder.samples.last?.stage, .citationValidation)
    XCTAssertEqual(recorder.samples.last?.elapsedMillis, 20)
    XCTAssertEqual(recorder.samples.last?.requiresRepair, true)
    XCTAssertNil(recorder.samples.last?.completion)
    XCTAssertEqual(recorder.samples.filter { $0.stage == .finished }.count, 1)
  }

  func testTimingClampsReversedClockAndSaturatesOverflowWithoutLoggingIdentifiers() {
    let recorder = CloudModelRoundTimingRecorder()
    var now = Int64.min
    let timing = CloudModelRoundTiming(requestId: "private request body and api key", round: -1,
      route: .streaming, finalRound: false, clock: { now }, sink: recorder.append)
    now = Int64.max
    timing.request(inputCharacters: -1)
    XCTAssertEqual(recorder.samples.first?.elapsedMillis, Int64.max)
    XCTAssertEqual(recorder.samples.first?.inputCharacters, 0)
    XCTAssertEqual(recorder.samples.first?.round, 0)
    now = Int64.min
    timing.citationValidation(startedAtMillis: 1, requiresRepair: false)
    XCTAssertEqual(recorder.samples.last?.elapsedMillis, 0)
    let hash = recorder.samples[0].requestHash
    XCTAssertEqual(hash.count, 24)
    XCTAssertTrue(hash.allSatisfy(\.isHexDigit))
    XCTAssertFalse(String(describing: recorder.samples).contains("private request body and api key"))
  }

  func testTimingDistinguishesFailureCancellationAndIncompleteTransport() {
    for (completed, failed, cancelled, expected) in [
      (true, true, true, CloudModelRoundTiming.Completion.cancelled),
      (true, true, false, .failed), (false, false, false, .interrupted), (true, false, false, .completed)
    ] {
      let recorder = CloudModelRoundTimingRecorder()
      let timing = CloudModelRoundTiming(requestId: "request", round: 0, route: .streaming, finalRound: false,
        clock: { 1 }, sink: recorder.append)
      timing.request(inputCharacters: 0)
      timing.finish(completed: completed, failed: failed, cancelled: cancelled)
      XCTAssertEqual(recorder.samples.last?.completion, expected)
      XCTAssertFalse(recorder.samples.contains { $0.stage == .firstActivity })
    }
  }
}

final class CloudModelRoundTimingRecorder {
  private let lock = NSLock()
  private var records: [CloudModelRoundTiming.Sample] = []
  var samples: [CloudModelRoundTiming.Sample] {
    lock.lock()
    defer { lock.unlock() }
    return records
  }
  func append(_ sample: CloudModelRoundTiming.Sample) {
    lock.lock()
    records.append(sample)
    lock.unlock()
  }
}
