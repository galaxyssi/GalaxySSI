import XCTest
@testable import GalaxySSI

final class AgentPlanningContextTimingTests: XCTestCase {
  func testPlanningContextTimingSeparatesReadAndAssemblyPhases() {
    let sample = AgentPlanningContextTiming.sample(turnId: "turn", started: 100, metadataRead: 103,
      historyRead: 110, globalRead: 130, finished: 132)
    XCTAssertEqual(sample.metadataMillis, 3)
    XCTAssertEqual(sample.historyMillis, 7)
    XCTAssertEqual(sample.globalMillis, 20)
    XCTAssertEqual(sample.assemblyMillis, 2)
    XCTAssertEqual(sample.totalMillis, 32)
    XCTAssertTrue(sample.clockValid)
    XCTAssertEqual(sample.metadataMillis + sample.historyMillis + sample.globalMillis + sample.assemblyMillis, sample.totalMillis)
  }

  func testPlanningContextTimingInvalidClockDoesNotInventPhaseDurations() {
    let cases: [[Int64]] = [[-1, 0, 1, 2, 3], [10, 9, 11, 12, 13], [10, 11, 9, 12, 13],
      [10, 11, 12, 9, 13], [10, 11, 12, 13, 9], [Int64.min, 0, 0, 0, Int64.max]]
    for values in cases {
      let sample = AgentPlanningContextTiming.sample(turnId: "turn", started: values[0], metadataRead: values[1],
        historyRead: values[2], globalRead: values[3], finished: values[4])
      XCTAssertFalse(sample.clockValid)
      XCTAssertEqual([sample.metadataMillis, sample.historyMillis, sample.globalMillis, sample.assemblyMillis, sample.totalMillis], [0, 0, 0, 0, 0])
    }
  }

  func testPlanningContextTimingEqualBoundariesAndMaximumElapsedAreRepresentable() {
    let equal = AgentPlanningContextTiming.sample(turnId: "turn", started: 1, metadataRead: 1,
      historyRead: 1, globalRead: 1, finished: 1)
    XCTAssertTrue(equal.clockValid)
    XCTAssertEqual(equal.totalMillis, 0)
    let maximum = AgentPlanningContextTiming.sample(turnId: "turn", started: 0, metadataRead: 0,
      historyRead: 0, globalRead: 0, finished: Int64.max)
    XCTAssertTrue(maximum.clockValid)
    XCTAssertEqual(maximum.totalMillis, Int64.max)
    XCTAssertEqual(maximum.assemblyMillis, Int64.max)
  }

  func testPlanningContextTimingCorrelationIsBoundedAndContainsNoRawIdentifier() {
    let first = AgentPlanningContextTiming.sample(turnId: "private-turn-identity", started: 0, metadataRead: 0,
      historyRead: 0, globalRead: 0, finished: 0)
    let again = AgentPlanningContextTiming.sample(turnId: "private-turn-identity", started: 0, metadataRead: 0,
      historyRead: 0, globalRead: 0, finished: 0)
    let other = AgentPlanningContextTiming.sample(turnId: "another-turn", started: 0, metadataRead: 0,
      historyRead: 0, globalRead: 0, finished: 0)
    XCTAssertEqual(first.turnHash.count, 24)
    XCTAssertTrue(first.turnHash.allSatisfy { "0123456789abcdef".contains($0) })
    XCTAssertEqual(first.turnHash, again.turnHash)
    XCTAssertNotEqual(first.turnHash, other.turnHash)
    XCTAssertFalse(String(describing: first).contains("private-turn-identity"))
  }
}
