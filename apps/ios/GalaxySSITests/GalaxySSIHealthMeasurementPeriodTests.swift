import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthMeasurementPeriodTests: XCTestCase {
  typealias Period = GalaxySSIHealthMeasurementPeriod
  typealias Model = GalaxySSIHealthMeasurementPeriods
  private let zone = TimeZone(secondsFromGMT: 0)!
  private func date(_ key: String) -> Date { ISO8601DateFormatter().date(from: key + "T12:00:00Z")! }
  private func reading(_ key: String, value: Decimal = 5) -> GalaxySSIHealthReading {
    .init(revision: 1, metric: .glucose, measuredAt: date(key), value: value, conditions: "fasting")
  }

  func testCanonicalCalendarPeriodsAndStrictKeys() throws {
    let sunday = try Period(kind: .week, on: date("2026-01-04"), zone: zone)
    XCTAssertEqual(sunday.id, "WEEK:2025-12-29")
    XCTAssertEqual(try sunday.previous().first, "2025-12-22")
    XCTAssertEqual(try Period(key: sunday.id), sunday)
    for key in ["WEEK:2026-01-04", "MONTH:2026-02-02", "MONTH:2026-02-30", "DAY:2026-01-01", "WEEK:"] {
      XCTAssertThrowsError(try Period(key: key))
    }
    let february = try Period(kind: .month, on: date("2024-02-29"), zone: zone)
    XCTAssertEqual(try february.interval(zone: zone).duration, 29 * 86400)
    XCTAssertEqual(try february.previous().first, "2024-01-01")
    let first = try Period(key: "WEEK:1969-12-29")
    XCTAssertEqual(try first.interval(zone: zone).start.timeIntervalSince1970, 0)
    XCTAssertThrowsError(try first.previous())
  }

  func testWeeksFollowLocalDSTNotFixedSeconds() throws {
    let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let spring = try Period(kind: .week, on: date("2026-03-08"), zone: zone)
    let autumn = try Period(kind: .week, on: date("2026-11-01"), zone: zone)
    XCTAssertEqual(try spring.interval(zone: zone).duration, 167 * 3600)
    XCTAssertEqual(try autumn.interval(zone: zone).duration, 169 * 3600)
  }

  func testSamplingTimeExclusiveEndAndSeriesContext() throws {
    let period = try Period(key: "WEEK:2026-11-02")
    let early = reading("2026-11-02"), latest = reading("2026-11-08", value: 6)
    var otherCondition = latest; otherCondition.id = UUID(); otherCondition.conditions = "after_meal"
    var otherUnit = latest; otherUnit.id = UUID(); otherUnit.unitOverride = "mg/dL"
    var otherSide = latest; otherSide.id = UUID(); otherSide.measurementSide = "left"
    var excluded = latest; excluded.id = UUID(); excluded.measuredAt = try period.interval(zone: zone).end
    var deleted = latest; deleted.id = UUID(); deleted.deleted = true
    let rows = [early, latest, otherCondition, otherUnit, otherSide, excluded, deleted]
    let summary = try Model.summary(rows, period: period, now: date("2026-11-20"), zone: zone)
    XCTAssertEqual(summary.series.count, 4)
    let matching = try XCTUnwrap(summary.series.first { $0.key == Model.Key(latest) })
    XCTAssertEqual(matching.count, 2)
    XCTAssertEqual(matching.latest.id, latest.id)
    let empty = try Model.summary(rows, period: period.previous(), now: date("2026-11-20"), zone: zone)
    XCTAssertTrue(empty.series.isEmpty)
    let current = try Model.summary(rows, period: nil, now: date("2026-11-08"), zone: zone)
    XCTAssertEqual(current.series.count, 1)
    XCTAssertEqual(current.series.first?.count, 1)
  }

  func testEarlierOutlierSurvivesHealthyLatestWithoutAveraging() throws {
    var earlier = reading("2026-11-02", value: 12); earlier.referenceInterval = "3.9-6.1"
    var latest = reading("2026-11-04", value: 5); latest.referenceInterval = "3.9-6.1"
    let period = try Period(key: "WEEK:2026-11-02")
    let summary = try Model.summary([earlier, latest], period: period, now: date("2026-11-20"), zone: zone)
    let series = try XCTUnwrap(summary.series.first)
    XCTAssertEqual(series.latest.value, 5)
    XCTAssertEqual(series.count, 2)
    XCTAssertEqual(series.outsideCount, 1)
    XCTAssertTrue(Model.highlighted(series))
    var unverified = series; unverified.unverifiedMethods = true
    XCTAssertNil(Model.delta(series, unverified))
    XCTAssertNil(Model.delta(nil, series))
    var different = latest; different.conditions = "after_meal"
    let other = try XCTUnwrap(Model.summary([different], period: period, now: date("2026-11-20"), zone: zone).series.first)
    XCTAssertNil(Model.delta(series, other))
  }

  func testThirtyRowCursorPagesAreStableAcrossTiesAndNewInsertions() throws {
    let rows = (1...65).map { index -> GalaxySSIHealthReading in
      var row = reading("2026-11-02")
      row.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
      return row
    }
    let now = date("2026-11-20")
    let first = try Model.records(rows, period: nil, now: now, zone: zone)
    XCTAssertEqual(first.readings.count, 30)
    let next = try XCTUnwrap(first.next)
    let second = try Model.records(rows + [reading("2026-11-03")], period: nil, now: now, zone: zone, after: next)
    XCTAssertEqual(second.readings.count, 30)
    XCTAssertTrue(Set(first.readings.map(\.id)).isDisjoint(with: second.readings.map(\.id)))
    let third = try Model.records(rows, period: nil, now: now, zone: zone, after: second.next)
    XCTAssertEqual(third.readings.count, 5)
    XCTAssertNil(third.next)
    XCTAssertEqual(Set((first.readings + second.readings + third.readings).map(\.id)).count, 65)
    let back = try Model.records(rows, period: nil, now: now, zone: zone, after: next)
    XCTAssertEqual(back.readings.map(\.id), second.readings.map(\.id))
    let sparse = Set(rows.enumerated().filter { $0.offset % 10 == 0 }.map { $0.element.id })
    let filtered = try Model.records(rows, period: nil, now: now, zone: zone, abnormal: true, outsideIDs: sparse)
    XCTAssertEqual(Set(filtered.readings.map(\.id)), sparse)
    XCTAssertNil(filtered.next)
  }

  func testPeriodPickerPagesOnlyOccupiedSamplingPeriods() throws {
    let calendar = Period.calendar(zone)
    let rows = (0..<26).map { offset -> GalaxySSIHealthReading in
      var row = reading("2026-11-20")
      row.measuredAt = calendar.date(byAdding: .day, value: -offset * 14, to: row.measuredAt)!
      return row
    }
    let first = try Model.page(rows, kind: .week, now: date("2026-11-21"), zone: zone)
    XCTAssertEqual(first.periods.count, 12)
    let second = try Model.page(rows, kind: .week, now: date("2026-11-21"), zone: zone, before: first.next)
    XCTAssertEqual(second.periods.count, 12)
    XCTAssertTrue(Set(first.periods).isDisjoint(with: second.periods))
    let third = try Model.page(rows, kind: .week, now: date("2026-11-21"), zone: zone, before: second.next)
    XCTAssertEqual(third.periods.count, 2)
    XCTAssertNil(third.next)
    XCTAssertEqual(Set(first.periods + second.periods + third.periods).count, rows.count)
    XCTAssertThrowsError(try Model.page(rows, kind: .week, now: date("2026-11-21"), zone: zone, before: "2026-11-20"))
  }

  func testAuthenticatedSecondaryProvenanceDoesNotUseImportTimeOrStaleRevisions() throws {
    let original = GalaxySSIHealthOriginalStore.Original(id: UUID(), name: "fixture.pdf", kind: .pdf,
      fileExtension: "pdf", importedAt: date("2026-11-20"), bytes: 10, sha256: String(repeating: "a", count: 64))
    let row = reading("2026-11-02")
    let source = GalaxySSIHealthReportReview.Source(original: original.id, sha256: original.sha256,
      page: 0, region: 0, fromOCR: false)
    var archive = GalaxySSIHealthRecords.Archive()
    archive.derivesOverview = true
    archive.originalIndex = .init(originals: [original.id: original])
    archive.revisions = [row]
    archive.reportEvidence = [.init(target: .init(record: row.id, revision: row.revision), source: source, excerpt: "fixture")]
    let input = GalaxySSIHealthMeasurementInput(archive)
    XCTAssertEqual(try input.unverifiedSources(), [row.id])
    let summary = try Model.summary(input.readings, period: Period(key: "WEEK:2026-11-02"),
      now: date("2026-11-21"), zone: zone, unverified: input.unverifiedSources())
    XCTAssertEqual(summary.series.first?.latest.id, row.id)
    XCTAssertTrue(summary.series.first?.unverifiedMethods == true)
    let uploadWeek = try Model.summary(input.readings, period: Period(key: "WEEK:2026-11-16"), now: date("2026-11-21"), zone: zone)
    XCTAssertTrue(uploadWeek.series.isEmpty)
    archive.revisions[0].revision += 1
    XCTAssertTrue(try GalaxySSIHealthMeasurementInput(archive).unverifiedSources().isEmpty)
    archive.revisions = [row]
    archive.originalIndex?.removals.pending.insert(original.id)
    XCTAssertTrue(try GalaxySSIHealthMeasurementInput(archive).unverifiedSources().isEmpty)
    XCTAssertFalse(input.matches(archive))
  }

  func testLegacyUnknownConditionsHaveTheSameSeriesKey() {
    var legacy = reading("2026-11-02"); legacy.conditions = ""
    var explicit = legacy; explicit.conditions = "unspecified"
    XCTAssertEqual(Model.Key(legacy), Model.Key(explicit))
    XCTAssertTrue(legacy.sameMeasurement(as: explicit))
    XCTAssertNil(GalaxySSIHealthMeasurementComparison.delta(legacy, explicit))
  }

  func testSecondaryTableAliasesRequireAuthenticatedLiveBytes() throws {
    let data = Data("date,value\n2026-11-02,5\n".utf8)
    let original = GalaxySSIHealthTableImport.Batch(id: UUID(), name: "fixture.csv", at: date("2026-11-20"), data: data, inserted: 1)
    let digest = GalaxySSIHealthTableImport.digest(data)
    let alias = GalaxySSIHealthTableImport.Batch(id: UUID(), name: "fixture.csv", at: date("2026-11-21"),
      data: Data(), inserted: 0, sourceDigest: digest)
    let row = reading("2026-11-02")
    var archive = GalaxySSIHealthRecords.Archive()
    archive.revisions = [row]; archive.tableBatches = [original, alias]
    archive.tableEvidence = [.init(target: .init(record: row.id, revision: row.revision),
      source: .init(batch: alias.id, row: 2, sha256: digest))]
    let input = GalaxySSIHealthMeasurementInput(archive)
    XCTAssertEqual(try input.unverifiedSources(), [row.id])
    archive.tableBatches?[1].undone = 1
    XCTAssertFalse(input.matches(archive))
    XCTAssertTrue(try GalaxySSIHealthMeasurementInput(archive).unverifiedSources().isEmpty)
    archive.tableBatches = [alias]
    XCTAssertTrue(try GalaxySSIHealthMeasurementInput(archive).unverifiedSources().isEmpty)
  }

  func testSnapshotInvalidationAndPermissionScope() throws {
    var archive = GalaxySSIHealthRecords.Archive()
    archive.revisions = [reading("2026-11-02")]
    let input = GalaxySSIHealthMeasurementInput(archive)
    XCTAssertTrue(input.matches(archive))
    let latest = GalaxySSIHealthMeasurementQuery.Scope.overview(period: nil, abnormal: false, after: nil, expanded: true, outsideIDs: [])
    XCTAssertNoThrow(try GalaxySSIHealthMeasurementQuery.run(input, scope: latest, now: date("2026-11-20"), zone: zone))
    let denied: [GalaxySSIHealthMeasurementQuery.Scope] = [
      .picker(kind: .week, before: nil), .comparison(kind: .month, first: nil, second: nil),
      .overview(period: nil, abnormal: true, after: nil, expanded: true, outsideIDs: [])
    ]
    for scope in denied {
      XCTAssertThrowsError(try GalaxySSIHealthMeasurementQuery.run(input, scope: scope, now: date("2026-11-20"), zone: zone))
    }
    archive.privacyEvents = [.init(at: date("2026-11-20"), scope: .overview, enabled: false)]
    XCTAssertFalse(input.matches(archive))
    archive.derivesOverview = true
    let permitted = GalaxySSIHealthMeasurementInput(archive)
    let comparison = try GalaxySSIHealthMeasurementQuery.run(permitted, scope: denied[1], now: date("2026-11-20"), zone: zone)
    XCTAssertEqual(comparison.first?.period?.id, "MONTH:2026-11-01")
    XCTAssertEqual(comparison.second?.period?.id, "MONTH:2026-10-01")
    XCTAssertTrue(comparison.second?.series.isEmpty == true)
    archive.privacyEvents?.append(.init(at: date("2026-11-21"), scope: .overview, enabled: true))
    XCTAssertFalse(permitted.matches(archive))
    archive.revisions[0].revision += 1
    XCTAssertFalse(permitted.matches(archive))
  }

  func testCancelledWorkerDoesNotProduceResults() async {
    let input = GalaxySSIHealthMeasurementInput(GalaxySSIHealthRecords.Archive())
    let work = Task.detached {
      while !Task.isCancelled { await Task.yield() }
      return try GalaxySSIHealthMeasurementQuery.run(input,
        scope: .overview(period: nil, abnormal: false, after: nil, expanded: true, outsideIDs: []),
        now: Date(), zone: TimeZone(secondsFromGMT: 0)!)
    }
    work.cancel()
    do { _ = try await work.value; XCTFail("Cancelled worker returned a projection") }
    catch is CancellationError { }
    catch { XCTFail("Unexpected error: \(error)") }
  }
}
