import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthMeasurementComparisonTests: XCTestCase {
  func testReportAssociationsUseExactCurrentRevisionsAndSamplingDates() throws {
    let original = report()
    let primary = reading(original: original, at: 100, value: 5)
    var secondary = GalaxySSIHealthReading(revision: 1, metric: .glucose,
      measuredAt: Date(timeIntervalSince1970: 200), value: 6, conditions: "fasting")
    let source = try XCTUnwrap(primary.reportSource)
    var archive = GalaxySSIHealthRecords.Archive()
    archive.originalIndex = .init(originals: [original.id: original])
    archive.revisions = [primary, secondary]
    archive.reportEvidence = [.init(target: .init(record: secondary.id, revision: 1), source: source, excerpt: "fixture")]
    let group = try XCTUnwrap(GalaxySSIHealthMeasurementBatches.groups(archive).first)
    let snapshot = try GalaxySSIHealthMeasurementBatches.snapshot(group, archive: archive, now: Date(timeIntervalSince1970: 500))
    XCTAssertEqual(snapshot.latest[.glucose]?.id, secondary.id)
    XCTAssertEqual(snapshot.latest[.glucose]?.measuredAt, Date(timeIntervalSince1970: 200))
    XCTAssertNotEqual(snapshot.latest[.glucose]?.measuredAt, group.importedAt)
    XCTAssertTrue(snapshot.requiresMethodReview(secondary))
    let spec = GalaxySSIHealthTrendAnalysis.Spec(metric: .glucose, component: .value, unit: secondary.unit,
      source: .manual, device: nil, origin: .all, aggregation: .latest,
      through: Date(timeIntervalSince1970: 500), days: 7, calendar: .current,
      comparisonAnchor: secondary, unverifiedComparison: snapshot.requiresMethodReview(secondary))
    XCTAssertNil(spec.chart([primary, secondary]).mean)
    XCTAssertTrue(spec.chart([primary, secondary]).unverifiedMethods)
    XCTAssertEqual(spec.chart([primary, secondary]).chartData(.latest, component: .value).map(\.value), [6])
    secondary.revision = 2; secondary.value = 8
    archive.revisions.append(secondary)
    let edited = try GalaxySSIHealthMeasurementBatches.snapshot(group, archive: archive, now: Date(timeIntervalSince1970: 500))
    XCTAssertEqual(edited.latest[.glucose]?.id, primary.id)
    XCTAssertThrowsError(try GalaxySSIHealthMeasurementBatches.snapshot(group, archive: archive, report: UUID(), now: Date()))
    archive.originalIndex?.removals.pending.insert(original.id)
    XCTAssertThrowsError(try GalaxySSIHealthMeasurementBatches.snapshot(group, archive: archive, now: Date()))
  }

  func testWrongDigestAndFutureResultsDoNotEnterReportSnapshot() throws {
    let original = report()
    var wrong = reading(original: original, at: 100, value: 4)
    wrong.reportSource = .init(original: original.id, sha256: String(repeating: "b", count: 64), page: 0, region: 0, fromOCR: false)
    let future = reading(original: original, at: 600, value: 9)
    var archive = GalaxySSIHealthRecords.Archive()
    archive.originalIndex = .init(originals: [original.id: original])
    archive.revisions = [wrong, future]
    let group = try XCTUnwrap(GalaxySSIHealthMeasurementBatches.groups(archive).first)
    XCTAssertTrue(try GalaxySSIHealthMeasurementBatches.snapshot(group, archive: archive, now: Date(timeIntervalSince1970: 500)).latest.isEmpty)
  }

  func testImportIdentityDoesNotCollapseDifferentReportsOnTheSameDate() throws {
    let a = report(), b = report()
    var archive = GalaxySSIHealthRecords.Archive()
    archive.originalIndex = .init(originals: [a.id: a, b.id: b])
    XCTAssertEqual(GalaxySSIHealthMeasurementBatches.groups(archive).count, 2)
    let batch = UUID()
    archive.recognitionJobs = [a, b].map { original in
      GalaxySSIHealthRecognitionJobs.Job(original: original,
        captureSource: .init(batchID: batch, mode: .report, order: original.id == a.id ? 0 : 1, cropRevision: nil),
        addedAt: original.importedAt, pageCount: 1)
    }
    let groups = GalaxySSIHealthMeasurementBatches.groups(archive)
    XCTAssertEqual(groups.count, 1)
    XCTAssertEqual(groups.first?.reportCount, 2)
    archive.revisions = [reading(original: a, at: 100, value: 5), reading(original: b, at: 200, value: 6)]
    let group = try XCTUnwrap(groups.first)
    let selectedReport = try GalaxySSIHealthMeasurementBatches.snapshot(group, archive: archive, report: a.id, now: Date())
    XCTAssertEqual(selectedReport.latest[.glucose]?.reportSource?.original, a.id)
    let allReports = try GalaxySSIHealthMeasurementBatches.snapshot(group, archive: archive, now: Date())
    XCTAssertEqual(allReports.latest[.glucose]?.reportSource?.original, b.id)
  }

  func testComparisonRequiresCompatibleConditionsUnitsAndSide() {
    let a = GalaxySSIHealthReading(metric: .bloodPressure, value: 120, diastolic: 80,
      conditions: "resting", measurementSide: "left")
    var b = a; b.id = UUID(); b.value = 125
    XCTAssertEqual(GalaxySSIHealthMeasurementComparison.delta(a, b), 5)
    b.measurementSide = "right"
    XCTAssertNil(GalaxySSIHealthMeasurementComparison.delta(a, b))
    b = a; b.conditions = "after_exercise"
    XCTAssertNil(GalaxySSIHealthMeasurementComparison.delta(a, b))
    b = a; b.unitOverride = "kPa"
    XCTAssertNil(GalaxySSIHealthMeasurementComparison.delta(a, b))
    var unspecified = a; unspecified.measurementSide = nil
    XCTAssertNil(GalaxySSIHealthMeasurementComparison.delta(unspecified, unspecified))
    var explicitUnspecified = unspecified; explicitUnspecified.measurementSide = "unspecified"
    XCTAssertTrue(unspecified.sameMeasurement(as: explicitUnspecified))
    XCTAssertTrue(GalaxySSIHealthMeasurementComparison.accepts(explicitUnspecified, anchor: unspecified))
    let reportReading = reading(original: report(), at: 100, value: 5)
    XCTAssertNil(GalaxySSIHealthMeasurementComparison.delta(reportReading, reportReading))
    XCTAssertFalse(a.sameMeasurement(as: b))
    b = a; b.measurementSide = "right"
    XCTAssertFalse(a.sameMeasurement(as: b))
  }

  func testAnchoredTrendPinsCurrentSourceAndCollectionContext() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let a = GalaxySSIHealthReading(revision: 1, metric: .glucose, measuredAt: now, value: 5, conditions: "fasting")
    var other = a; other.id = UUID(); other.conditions = "after_meal"
    let spec = GalaxySSIHealthTrendAnalysis.Spec(metric: .glucose, component: .value, unit: a.unit,
      source: .manual, device: nil, origin: .all, aggregation: .latest, through: now, days: 7,
      calendar: .current, comparisonAnchor: a)
    XCTAssertEqual(spec.cohort([a, other]).map(\.id), [a.id])
    var corrected = a; corrected.revision += 1
    XCTAssertTrue(spec.cohort([corrected, other]).isEmpty)
  }

  func testUnverifiedReportTrendsRetainLatestActualReadingWithoutMeanOrDelta() throws {
    let original = report()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let a = reading(original: original, at: now.addingTimeInterval(-2 * 86_400).timeIntervalSince1970, value: 5)
    let b = reading(original: original, at: now.addingTimeInterval(-86_400).timeIntervalSince1970, value: 7)
    let c = reading(original: original, at: now.addingTimeInterval(-86_400 + 1).timeIntervalSince1970, value: 8)
    let current = [a, b, c]
    let spec = GalaxySSIHealthTrendAnalysis.Spec(metric: .glucose, component: .value, unit: a.unit, source: .report,
      device: nil, origin: .all, aggregation: .latest, through: now, days: 7, calendar: .current)
    let trend = spec.chart(current)
    XCTAssertTrue(trend.unverifiedMethods)
    XCTAssertNil(trend.mean)
    XCTAssertTrue(trend.chartData(.mean, component: .value).isEmpty)
    XCTAssertEqual(trend.chartData(.latest, component: .value).map(\.value), [5, 8])
    let scope = GalaxySSIHealthTrendAnalysis(spec: spec, versions: spec.versions(current), sourceTitle: "Fixture")
    let result = try XCTUnwrap(scope.result(current))
    XCTAssertNil(result.fact.delta)
    XCTAssertNil(result.evidence.aggregate.mean)
    XCTAssertEqual(result.fact.last?.value, "8")
  }

  func testLegacySideRemainsOptionalWhenDecoding() throws {
    let original = GalaxySSIHealthReading(metric: .weight, value: 60)
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(GalaxySSIHealthReading.self, from: encoded)
    XCTAssertNil(decoded.measurementSide)
    XCTAssertEqual(decoded, original)
  }

  func testTableComparisonRequiresAuthenticatedDataAndRejectsUndoneImports() throws {
    let data = Data("value,date\n5,2026-01-01\n".utf8)
    let id = UUID()
    let table = GalaxySSIHealthTableImport.Batch(id: id, name: "fixture.csv", at: Date(), data: data, inserted: 1)
    let saved = GalaxySSIHealthReading(revision: 1, metric: .glucose, measuredAt: Date(timeIntervalSince1970: 100), value: 5,
      conditions: "fasting", tableSource: .init(batch: id, row: 2, sha256: GalaxySSIHealthTableImport.digest(data)))
    var archive = GalaxySSIHealthRecords.Archive()
    archive.tableBatches = [table]; archive.revisions = [saved]
    let group = try XCTUnwrap(GalaxySSIHealthMeasurementBatches.groups(archive).first)
    XCTAssertEqual(try GalaxySSIHealthMeasurementBatches.snapshot(group, archive: archive, now: Date()).latest[.glucose], saved)
    XCTAssertNil(GalaxySSIHealthMeasurementComparison.delta(saved, saved))
    archive.tableBatches?[0].undone = 1
    XCTAssertThrowsError(try GalaxySSIHealthMeasurementBatches.snapshot(group, archive: archive, now: Date()))
  }
  private func report() -> GalaxySSIHealthOriginalStore.Original {
    .init(id: UUID(), name: "report.pdf", kind: .pdf, fileExtension: "pdf", importedAt: Date(timeIntervalSince1970: 400),
      bytes: 10, sha256: String(repeating: "a", count: 64))
  }
  private func reading(original: GalaxySSIHealthOriginalStore.Original, at: TimeInterval, value: Decimal) -> GalaxySSIHealthReading {
    .init(revision: 1, metric: .glucose, measuredAt: Date(timeIntervalSince1970: at), value: value, conditions: "fasting",
      reportSource: .init(original: original.id, sha256: original.sha256, page: 0, region: 0, fromOCR: false))
  }
}
