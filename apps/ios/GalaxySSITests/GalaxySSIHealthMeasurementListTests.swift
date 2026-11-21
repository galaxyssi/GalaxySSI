import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthMeasurementListTests: XCTestCase {
  func testSelectionIsNoOpForSamePeriodAndRollsBackByKeepingDisplayedSnapshot() throws {
    let week = try GalaxySSIHealthMeasurementPeriod(key: "WEEK:2026-11-02")
    var state = GalaxySSIHealthMeasurementSelection()
    XCTAssertNil(state.choose(nil))
    let request = try XCTUnwrap(state.choose(week))
    XCTAssertNil(state.displayed)
    XCTAssertEqual(state.selected, week)
    XCTAssertNil(state.choose(week))
    XCTAssertEqual(state.pending, request)
    XCTAssertTrue(state.commit(request))
    XCTAssertEqual(state.displayed, week)
    XCTAssertNil(state.choose(week))
    let latest = try XCTUnwrap(state.choose(nil))
    XCTAssertNil(state.selected)
    XCTAssertEqual(state.displayed, week)
    state.cancel()
    XCTAssertEqual(state.selected, week)
    XCTAssertFalse(state.commit(latest))
  }

  func testSupersededSelectionCannotPublishAndReselectingDisplayedCancelsPending() throws {
    let week = try GalaxySSIHealthMeasurementPeriod(key: "WEEK:2026-11-02")
    let month = try GalaxySSIHealthMeasurementPeriod(key: "MONTH:2026-11-01")
    var state = GalaxySSIHealthMeasurementSelection()
    let a = try XCTUnwrap(state.choose(week)), b = try XCTUnwrap(state.choose(month))
    XCTAssertFalse(state.commit(a))
    XCTAssertEqual(state.pending, b)
    XCTAssertTrue(state.commit(b))
    let old = try XCTUnwrap(state.choose(week))
    XCTAssertNil(state.choose(month))
    XCTAssertNil(state.pending)
    XCTAssertFalse(state.commit(old))
    XCTAssertEqual(state.displayed, month)
  }
  typealias List = GalaxySSIHealthMeasurementList
  private func item(_ metric: GalaxySSIHealthMetric, position: GalaxySSIHealthOverviewRange.Position? = nil,
                    recorded: Bool = true) -> List.Item {
    let reading = recorded ? GalaxySSIHealthReading(metric: metric, value: metric == .bloodPressure ? 120 : 5,
      diastolic: metric == .bloodPressure ? 80 : nil) : nil
    let ranges: [GalaxySSIHealthOverviewRange] = position.map {
      [.init(component: .value, source: .record, bounds: "4-6", unit: metric.unit, position: $0)]
    } ?? []
    return .init(metric: .init(metric: metric, reading: reading, freshness: recorded ? .recent : .missing, ranges: ranges), series: nil)
  }

  func testEmptyAndStepOnlyListsHaveNoHiddenRows() {
    XCTAssertTrue(List.rows([], abnormal: false).isEmpty)
    XCTAssertEqual(List.previewSize([]), 0)
    XCTAssertTrue(List.rows([item(.steps)], abnormal: false).isEmpty)
    XCTAssertEqual(List.rows([item(.steps), item(.weight)], abnormal: false).map { $0.metric.metric }, [.weight])
  }

  func testOnlyActuallyOutsideDisplayedResultsMatchAbnormalFilter() {
    let input = [item(.glucose, position: .within), item(.ldl, position: .above), item(.hdl, position: .below),
      item(.weight), item(.cholesterol, position: .notComparable), item(.sleepDuration, recorded: false)]
    XCTAssertEqual(List.rows(input, abnormal: true).map { $0.metric.metric }, [.ldl, .hdl])
    XCTAssertTrue(List.rows([item(.glucose, position: .within)], abnormal: true).isEmpty)
  }

  func testPreviousOutlierDoesNotMakeNormalLatestAbnormal() {
    let reading = GalaxySSIHealthReading(metric: .glucose, value: 5, conditions: "fasting", referenceInterval: "4-6")
    let series = GalaxySSIHealthMeasurementPeriods.Series(key: .init(reading), latest: reading,
      count: 2, outsideCount: 1, unverifiedMethods: false)
    let row = List.Item(metric: .init(metric: .glucose, reading: reading, freshness: .recent,
      ranges: [.init(component: .value, source: .record, bounds: "4-6", unit: reading.unit, position: .within)]), series: series)
    XCTAssertTrue(List.rows([row], abnormal: true).isEmpty)
    XCTAssertEqual(List.rows([row], abnormal: false).first?.series?.outsideCount, 1)
  }

  func testEveryAbnormalRowRemainsInCollapsedPreview() {
    let metrics = Array(GalaxySSIHealthMetric.allCases.filter { $0 != .steps }.prefix(8))
    let input = metrics.map { item($0, position: .above) }
    let rows = List.rows(input, abnormal: false)
    XCTAssertEqual(rows.count, 8)
    XCTAssertEqual(List.previewSize(rows), 8)
  }

  func testExpansionContinuesSameOrderedRowsAndPreservesIdentities() {
    let input = [item(.glucose, position: .above), item(.ldl, position: .within), item(.hdl),
      item(.triglycerides), item(.cholesterol), item(.weight), item(.sleepDuration, recorded: false)]
    let rows = List.rows(input, abnormal: false), count = List.previewSize(List.rows(input, abnormal: false))
    XCTAssertEqual(count, 5)
    XCTAssertEqual((Array(rows.prefix(count)) + Array(rows.dropFirst(count))).map(\.id), rows.map(\.id))
    XCTAssertEqual(rows.map(\.id), input.map(\.id))
    XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
    for _ in 0..<20 {
      XCTAssertEqual(List.rows(input, abnormal: true).map(\.id), [input[0].id])
      XCTAssertEqual(List.rows(input, abnormal: false).map(\.id), rows.map(\.id))
    }
  }

  func testRecordedNormalValuesPrecedeMissingWithoutReorderingPeers() {
    let missing = item(.sleepDuration, recorded: false), weight = item(.weight), hdl = item(.hdl)
    let above = item(.glucose, position: .above)
    XCTAssertEqual(List.rows([missing, weight, hdl, above], abnormal: false).map(\.id), [above.id, weight.id, hdl.id, missing.id])
  }
}
