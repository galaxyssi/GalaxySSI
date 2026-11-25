import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthAtlasReadingsTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private func spec(_ metric: GalaxySSIHealthMetric, days: Int = 30) -> GalaxySSIHealthTrendAnalysis.Spec {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return .init(metric: metric, component: .value, unit: metric.unit, source: .all, device: nil, origin: .all,
      aggregation: .latest, through: now, days: days, calendar: calendar)
  }

  func testMappedLatestValuesStayIndependentOfTheSelectedTrendWindow() throws {
    let pressure = GalaxySSIHealthReading(metric: .bloodPressure, measuredAt: now, value: 119, diastolic: 77)
    let ldl = GalaxySSIHealthReading(metric: .ldl, measuredAt: now.addingTimeInterval(-45 * 86_400), value: Decimal(string: "2.7"))
    let unrelated = GalaxySSIHealthReading(metric: .alt, measuredAt: now, value: 55)
    let rows = [pressure, ldl, unrelated]
    let month = GalaxySSIHealthAtlasReadings.snapshot(rows, entryID: "heart", spec: spec(.ldl), now: now)
    XCTAssertEqual(month.latest[.bloodPressure], pressure); XCTAssertEqual(month.latest[.ldl], ldl)
    XCTAssertNil(month.latest[.alt]); XCTAssertTrue(month.trend.isEmpty)
    XCTAssertNil(spec(.ldl).chart(month.trend).minimum)
    let year = GalaxySSIHealthAtlasReadings.snapshot(rows, entryID: "heart", spec: spec(.ldl, days: 366), now: now)
    XCTAssertEqual(year.trend, [ldl]); XCTAssertEqual(year.latest, month.latest)
    XCTAssertEqual(spec(.ldl, days: 366).chart(year.trend).minimum, Decimal(string: "2.7"))
    let missing = GalaxySSIHealthAtlasReadings.snapshot(rows, entryID: "heart", spec: spec(.restingHeartRate), now: now)
    XCTAssertTrue(missing.trend.isEmpty); XCTAssertNil(missing.latest[.restingHeartRate])
    typealias Action = GalaxySSIHealthAtlasTrendAction
    let monthSpec = spec(.ldl), yearSpec = spec(.ldl, days: 366)
    let monthIdentity = Action.Identity(spec: monthSpec, environmentCalendar: monthSpec.calendar,
      timeZone: monthSpec.calendar.timeZone, selection: "heart:ldl:month")
    let yearIdentity = Action.Identity(spec: yearSpec, environmentCalendar: yearSpec.calendar,
      timeZone: yearSpec.calendar.timeZone, selection: "heart:ldl:year")
    XCTAssertFalse(Action.ready(captured: monthIdentity, current: monthIdentity, foreground: true, protectedData: true,
      permitted: true, changed: false, hasChartData: !monthSpec.chart(month.trend).chartData(.latest, component: .value).isEmpty))
    XCTAssertFalse(Action.ready(captured: monthIdentity, current: yearIdentity, foreground: true, protectedData: true,
      permitted: true, changed: false, hasChartData: true))
    XCTAssertTrue(Action.ready(captured: yearIdentity, current: yearIdentity, foreground: true, protectedData: true,
      permitted: true, changed: false, hasChartData: !yearSpec.chart(year.trend).chartData(.latest, component: .value).isEmpty))
    XCTAssertFalse(Action.ready(captured: yearIdentity, current: yearIdentity, foreground: true, protectedData: true,
      permitted: false, changed: false, hasChartData: true))
    for locale in ["en", "zh-Hans"] {
      XCTAssertFalse(GalaxySSIHealthOverviewMetricRow.origin(pressure, language: locale).isEmpty)
      XCTAssertFalse(GalaxySSIHealthOverviewHistoryView.amount(pressure).isEmpty)
      for key in ["related_metrics", "metric_trend_title", "reading_source", "no_reading"] {
        let resource = "health_atlas_" + key
        XCTAssertNotEqual(GalaxySSIHealthAtlasText.get(resource, locale), resource)
      }
    }
  }

  func testLatestExcludesFutureDeletedInvalidAndUnrelatedReadingsAndBreaksTiesStably() throws {
    let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let high = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let a = GalaxySSIHealthReading(id: low, metric: .restingHeartRate, measuredAt: now, value: 60)
    let b = GalaxySSIHealthReading(id: high, metric: .restingHeartRate, measuredAt: now, value: 65)
    var deleted = GalaxySSIHealthReading(metric: .restingHeartRate, measuredAt: now, value: 90); deleted.deleted = true
    let future = GalaxySSIHealthReading(metric: .restingHeartRate, measuredAt: now.addingTimeInterval(1), value: 120)
    let invalid = GalaxySSIHealthReading(metric: .hdl, measuredAt: now, value: -1)
    let unrelated = GalaxySSIHealthReading(metric: .alt, measuredAt: now, value: 55)
    for input in [[a, b, deleted, future, invalid, unrelated], [unrelated, invalid, future, deleted, b, a]] {
      let latest = GalaxySSIHealthAtlasReadings.latest(input, entryID: "heart", now: now)
      XCTAssertEqual(latest, [.restingHeartRate: b])
    }
    XCTAssertTrue(GalaxySSIHealthAtlasReadings.latest([a, b], entryID: "brain", now: now).isEmpty)
    let report = GalaxySSIHealthReading(metric: .ldl, measuredAt: now,
      reported: try XCTUnwrap(GalaxySSIHealthReportedResult.parse("<2.5", metric: .ldl)))
    XCTAssertTrue(report.isValid)
    XCTAssertEqual(GalaxySSIHealthAtlasReadings.latest([report], entryID: "heart", now: now)[.ldl], report)
    XCTAssertTrue(GalaxySSIHealthOverviewHistoryView.amount(report).contains("<2.5"))
  }

  func testEncryptedStoreAuditsBothScopesAndPermissionDenialBeforeReturningValues() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let secrets = InMemorySecretStore()
    let records = GalaxySSIHealthRecords(owner: "atlas-readings", secrets: secrets, isolatedFile: file)
    try records.write(.init(metric: .bloodPressure, measuredAt: now, value: 119, diastolic: 77))
    try records.write(.init(metric: .ldl, measuredAt: now.addingTimeInterval(-45 * 86_400), value: Decimal(string: "2.7")))
    try records.write(.init(metric: .alt, measuredAt: now, value: 55))
    try records.setPrivacy(.overview, enabled: true)
    let before = try records.load().current
    let result = try records.atlasMeasurements(entryID: "heart", spec: spec(.ldl), now: now)
    XCTAssertNotNil(result.latest[.bloodPressure]); XCTAssertNotNil(result.latest[.ldl]); XCTAssertNil(result.latest[.alt])
    XCTAssertTrue(result.trend.isEmpty)
    let reopened = GalaxySSIHealthRecords(owner: records.owner, secrets: secrets, isolatedFile: file)
    let archive = try reopened.load(), audit = try XCTUnwrap(archive.atlasReadAudit)
    XCTAssertEqual(archive.current, before); XCTAssertEqual(audit.count, 2)
    XCTAssertEqual(audit[0].purpose, .overview); XCTAssertEqual(Set(audit[0].metrics), Set(GalaxySSIHealthAtlasMetrics.forEntry("heart")))
    XCTAssertNil(audit[0].from); XCTAssertEqual(audit[0].through, now)
    XCTAssertEqual(audit[1].purpose, .trend); XCTAssertEqual(audit[1].metrics, [.ldl])
    XCTAssertEqual(audit[1].from, spec(.ldl).interval.start)
    XCTAssertTrue(audit.allSatisfy { $0.outcome == .complete && $0.consentEvent != nil && !$0.metrics.contains(.alt) })
    try records.setPrivacy(.overview, enabled: false)
    XCTAssertThrowsError(try records.atlasMeasurements(entryID: "heart", spec: spec(.ldl), now: now)) { error in
      guard let failure = error as? GalaxySSIHealthRecords.Failure, case .permission = failure else { return XCTFail("Expected permission denial") }
    }
    let denied = try XCTUnwrap(records.load().atlasReadAudit).suffix(2)
    XCTAssertTrue(denied.allSatisfy { $0.outcome == .blocked })
    XCTAssertEqual(try records.load().current, before)
    XCTAssertThrowsError(try records.atlasMeasurements(entryID: "heart", spec: spec(.alt), now: now))
    XCTAssertThrowsError(try records.atlasMeasurements(entryID: "brain", spec: spec(.ldl), now: now))
  }
}
