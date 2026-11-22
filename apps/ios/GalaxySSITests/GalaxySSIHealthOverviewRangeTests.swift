import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthOverviewRangeTests: XCTestCase {
  typealias Range = GalaxySSIHealthOverviewRange
  let now = Date(timeIntervalSince1970: 1_800_000_000)

  func testRecordedReferencesHonorInclusiveAndExclusiveBoundaries() throws {
    for (value, reference, expected) in [
      ("3.8", "3.9-6.1", Range.Position.below), ("6.1", "3.9-6.1", .within),
      ("6.2", "3.9-6.1", .above), ("6.1", "<6.1", .above), ("6.1", "<=6.1", .within),
      ("3.9", ">3.9", .below), ("3.9", ">=3.9", .within)] {
      let reading = GalaxySSIHealthReading(metric: .glucose, measuredAt: now,
        value: try XCTUnwrap(Decimal(string: value)), referenceInterval: reference)
      let range = try XCTUnwrap(Range.report(reading))
      XCTAssertEqual(range.position, expected); XCTAssertEqual(range.bounds, reference)
      XCTAssertEqual(range.unit, "mmol/L"); XCTAssertEqual(range.source, .record)
    }
  }

  func testNonExactResultsAreNotColoredAsExactNumbers() throws {
    let reading = GalaxySSIHealthReading(metric: .glucose, measuredAt: now,
      reported: try XCTUnwrap(GalaxySSIHealthReportedResult.parse("<6.2", metric: .glucose)), referenceInterval: "3.9-6.1")
    XCTAssertTrue(reading.isValid)
    XCTAssertEqual(Range.report(reading)?.position, .notComparable)
    XCTAssertFalse(try XCTUnwrap(Range.report(reading)).outside)
  }

  func testUnsupportedReferencesAndUnitsNeverInventARange() {
    for reference in ["", "normal", "70-110 mg/dL", "-3-6", "4-2"] {
      XCTAssertNil(Range.report(.init(metric: .glucose, measuredAt: now, value: 7, referenceInterval: reference)), reference)
    }
    XCTAssertNil(Range.report(.init(metric: .glucose, measuredAt: now, value: 7, unitOverride: "invented", referenceInterval: "3-6")))
    XCTAssertNil(Range.report(.init(metric: .bloodPressure, measuredAt: now, value: 127, diastolic: 78, referenceInterval: "100-125")))
    XCTAssertNil(Range.report(.init(metric: .urineProtein, measuredAt: now,
      reported: GalaxySSIHealthReportedResult.parse("negative", metric: .urineProtein), referenceInterval: "0-1")))
  }

  func testOnlyConfirmedReportReadingsUseReportReferenceLabel() throws {
    var reading = GalaxySSIHealthReading(metric: .glucose, measuredAt: now, value: 7, referenceInterval: "3-6")
    XCTAssertEqual(Range.report(reading)?.source, .record)
    reading.reportSource = .init(original: UUID(), sha256: String(repeating: "a", count: 64), page: 0, region: 0, fromOCR: true)
    XCTAssertEqual(Range.report(reading)?.source, .report)
  }

  func testConfirmedTargetBindsComponentUnitsBasisAndExactRecordRevision() throws {
    let reading = GalaxySSIHealthReading(metric: .bloodPressure, measuredAt: now, value: 127, diastolic: 78)
    var concern = try targetConcern(reading, component: .systolic, low: "100", high: "125")
    let range = try XCTUnwrap(Range.target(reading, concern: concern))
    XCTAssertEqual(range.component, .systolic); XCTAssertEqual(range.position, .above)
    XCTAssertEqual(range.bounds, "100\u{2013}125"); XCTAssertEqual(range.source, .confirmedTarget)
    var revised = reading; revised.revision = 2
    XCTAssertNil(Range.target(revised, concern: concern))
    concern.stage = .paused; XCTAssertNil(Range.target(reading, concern: concern))
    concern.stage = .closed; XCTAssertNil(Range.target(reading, concern: concern))
    concern = try targetConcern(reading, component: .diastolic, low: "70", high: "80")
    XCTAssertEqual(Range.target(reading, concern: concern)?.component, .diastolic)
    XCTAssertEqual(Range.target(reading, concern: concern)?.position, .within)
    let numeric = try XCTUnwrap(concern.target?.numeric)
    concern.target?.numeric = .init(component: numeric.component, bounds: numeric.bounds, unit: "kPa", basis: numeric.basis)
    XCTAssertNil(Range.target(reading, concern: concern))
    concern.target?.numeric = .init(component: numeric.component, bounds: numeric.bounds, unit: numeric.unit, basis: "changed")
    XCTAssertNil(Range.target(reading, concern: concern))
  }

  func testOnlyOutsideNonKeyMetricsAreAddedAndSortedBeforeBaseMetrics() {
    let glucose = GalaxySSIHealthReading(metric: .glucose, measuredAt: now.addingTimeInterval(-10), value: 7)
    let weight = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 70)
    let alt = GalaxySSIHealthReading(metric: .alt, measuredAt: now, value: 30)
    let temperature = GalaxySSIHealthReading(metric: .temperature, measuredAt: now, value: 37)
    let oxygen = GalaxySSIHealthReading(metric: .oxygenSaturation, measuredAt: now, value: 98)
    let outside = Range(component: .value, source: .record, bounds: "1-2", unit: "fixture", position: .above)
    let neutral = Range(component: .value, source: .record, bounds: "1-2", unit: "fixture", position: .notComparable)
    let result = GalaxySSIHealthOverview(current: [glucose, weight, alt, temperature, oxygen], now: now, calendar: .current,
      ranges: [.glucose: [outside], .weight: [outside], .alt: [neutral], .temperature: [outside], .oxygenSaturation: [outside]])
    XCTAssertEqual(result.metrics.map(\.metric), [.weight, .glucose, .bloodPressure, .sleepDuration, .restingHeartRate, .steps])
    XCTAssertEqual(result.metrics.prefix(2).map(\.outsideRange), [true, true])
  }

  func testTargetDisplayKeepsExclusiveBoundsAndRejectsInvalidComponents() throws {
    let reading = GalaxySSIHealthReading(metric: .bloodPressure, measuredAt: now, value: 125, diastolic: 78)
    var concern = try targetConcern(reading, component: .systolic, low: "100", high: "125")
    let numeric = try XCTUnwrap(concern.target?.numeric)
    concern.target?.numeric = .init(component: .systolic,
      bounds: try .init(low: "100", high: "125", lowInclusive: false, highInclusive: false),
      unit: "mmHg", basis: numeric.basis)
    XCTAssertEqual(Range.target(reading, concern: concern)?.bounds, "> 100 / < 125")
    XCTAssertEqual(Range.target(reading, concern: concern)?.position, .above)
    concern.target?.numeric = .init(component: .value, bounds: numeric.bounds, unit: "mmHg", basis: numeric.basis)
    XCTAssertNil(Range.target(reading, concern: concern))
  }

  func testCurrentOverviewComparisonIsReadOnlyAndPermissionGated() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "overview-range", secrets: InMemorySecretStore(), isolatedFile: file)
    try records.write(.init(metric: .glucose, measuredAt: now, value: 7, referenceInterval: "3-6"))
    var archive = try records.load()
    XCTAssertTrue(try records.overviewRanges(expected: archive, now: now).isEmpty)
    try records.setPrivacy(.overview, enabled: true)
    archive = try records.load()
    let before = try Data(contentsOf: file)
    XCTAssertEqual(try records.overviewRanges(expected: archive, now: now)[.glucose]?.first?.position, .above)
    XCTAssertEqual(try Data(contentsOf: file), before)
    var stale = archive; stale.revisions = []
    XCTAssertTrue(try records.overviewRanges(expected: stale, now: now).isEmpty)
    try records.setPrivacy(.overview, enabled: false)
    XCTAssertTrue(try records.overviewRanges(expected: archive, now: now).isEmpty)
  }

  func testTargetsRequireCurrentCareAndProfilePermissionButRecordedRangeDoesNot() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "overview-target", secrets: InMemorySecretStore(), isolatedFile: file)
    try records.write(.init(metric: .glucose, measuredAt: now, value: 7, referenceInterval: "3-6"))
    try records.setPrivacy(.overview, enabled: true)
    try records.setPrivacy(.localCare, enabled: true)
    try records.reconcileLocalCare(now: now)
    let concern = try XCTUnwrap(records.load().localCare?.current[GalaxySSIHealthMetric.glucose.rawValue])
    try records.confirmLocalCareNumericTarget(concern, component: .value,
      bounds: .init(low: "4", high: "6", lowInclusive: true, highInclusive: true),
      source: "Synthetic", rationale: "Fixture", confirmedBy: "User", now: now)
    @MainActor func sources() throws -> [Range.Source] {
      try records.overviewRanges(expected: records.load(), now: now)[.glucose]?.map(\.source) ?? []
    }
    XCTAssertEqual(try sources(), [.record])
    try records.setPrivacy(.profileAnalysis, enabled: true)
    XCTAssertEqual(try sources(), [.record, .confirmedTarget])
    try records.setPrivacy(.profileAnalysis, enabled: false)
    XCTAssertEqual(try sources(), [.record])
    try records.setPrivacy(.localCare, enabled: false)
    XCTAssertEqual(try sources(), [.record])
  }

  private func targetConcern(_ reading: GalaxySSIHealthReading, component: GalaxySSIHealthCareTarget.Component,
      low: String, high: String) throws -> GalaxySSIHealthCare.Concern {
    var concern = GalaxySSIHealthCare.Concern(id: UUID(), metric: reading.metric, revision: 1, updatedAt: now,
      assessment: try XCTUnwrap(GalaxySSIHealthCare.assess([reading], context: nil)), stage: .verify)
    concern.target = try .init(value: "Fixture", source: "Synthetic", rationale: "Fixture", confirmedBy: "User", confirmedAt: now,
      numeric: .init(component: component, bounds: .init(low: low, high: high, lowInclusive: true, highInclusive: true),
        unit: reading.unit, basis: GalaxySSIHealthCareTarget.basis(concern)))
    return concern
  }
}
