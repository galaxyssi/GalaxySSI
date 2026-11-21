import XCTest
import UIKit
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthReportQuickImportTests: XCTestCase {
  typealias Quick = GalaxySSIHealthReportQuickImport

  func testSupportedResultsSaveTogetherWithoutInventingClinicalFacts() throws {
    let f = try Fixture()
    try f.recognize(rows: [row("glucose", "5.7", "mmol/L"), row("weight", "70", "kg")])
    let plan = try f.plan()
    XCTAssertFalse(plan.needsSupplement)
    let outcome = try f.save(plan)
    XCTAssertEqual(outcome.saved, 2); XCTAssertEqual(outcome.pending, 0)
    let readings = try f.records.load().current
    XCTAssertEqual(readings.count, 2)
    let glucose = try XCTUnwrap(readings.first { $0.metric == .glucose })
    XCTAssertEqual(glucose.value, Decimal(string: "5.7")); XCTAssertEqual(glucose.conditions, "fasting")
    XCTAssertEqual(glucose.reportedNotation, "5.7"); XCTAssertNil(glucose.reported)
    XCTAssertEqual(glucose.reportSource?.recognition, .model)
    XCTAssertNil(try f.records.load().localCarePlans)
    XCTAssertNil(try f.records.load().localCareResearch)
    XCTAssertFalse(try f.records.load().localCareFollowUps?.isEmpty == false)
  }

  func testDeviceModeDoesNotBecomeAReportImport() throws {
    let f = try Fixture()
    try f.recognize(rows: [row()])
    var job = try f.job()
    job.captureSource = .init(batchID: UUID(), mode: .device, order: 1, cropRevision: nil)
    XCTAssertThrowsError(try Quick.plan(job: job, archive: f.records.load(), now: f.now))
    job.reportVision = nil
    XCTAssertFalse(GalaxySSIHealthReportVision.eligible(job))
  }

  func testMissingDateAndFastingAreCollectedInOneSupplement() throws {
    let f = try Fixture()
    try f.recognize(rows: [row()], collected: "", fasting: "")
    let plan = try f.plan()
    XCTAssertTrue(plan.needsDate); XCTAssertTrue(plan.needsFasting)
    XCTAssertThrowsError(try f.save(plan))
    XCTAssertTrue(try f.records.load().current.isEmpty)
    let date = try stamp("2020-01-02T08:30:00Z")
    let outcome = try f.save(plan, supplement: .init(measuredAt: date, fasting: "unspecified"))
    XCTAssertEqual(outcome.saved, 1)
    let reading = try XCTUnwrap(f.records.load().current.first)
    XCTAssertEqual(reading.measuredAt, date); XCTAssertEqual(reading.conditions, "unspecified")
    XCTAssertEqual(Quick.conditionKey(reading.conditions), "")
  }

  func testDateOnlyReportRequiresTimeOnThatDateAndRejectsDSTFold() throws {
    let f = try Fixture()
    try f.recognize(rows: [row()], collected: "2020-01-02")
    let plan = try f.plan()
    XCTAssertNotNil(plan.collectedDate); XCTAssertTrue(plan.needsDate)
    XCTAssertThrowsError(try f.save(plan, supplement: .init(measuredAt: stamp("2020-01-03T08:00:00Z"))))
    XCTAssertEqual(try f.save(plan, supplement: .init(measuredAt: stamp("2020-01-02T08:00:00Z"))).saved, 1)
    let fold = try Fixture()
    try fold.recognize(rows: [row()], collected: "2020-11-01", zone: "America/New_York")
    let ambiguous = try fold.plan()
    XCTAssertFalse(Quick.validSupplementDate(try stamp("2020-11-01T05:30:00Z"), plan: ambiguous, now: fold.now))
    XCTAssertThrowsError(try fold.save(ambiguous, supplement: .init(measuredAt: stamp("2020-11-01T05:30:00Z"))))
  }

  func testUnknownUnitAndConflictingSameMetricRemainDrafts() throws {
    let f = try Fixture(retain: false)
    try f.recognize(rows: [row("glucose", "5.7", ""), row("weight", "70", "kg"), row("weight", "72", "kg")])
    let outcome = try f.save(f.plan())
    XCTAssertEqual(outcome.saved, 0); XCTAssertEqual(outcome.pending, 3)
    XCTAssertTrue(try f.records.load().current.isEmpty)
    XCTAssertEqual(try f.records.load().reportReview?.count, 3)
    f.originals.releaseCompletedQuickReportOriginals()
    XCTAssertEqual(try f.originals.list().originals.count, 1)
  }

  func testDuplicateLinksSourceWithoutOverwritingExistingRecord() throws {
    let f = try Fixture()
    try f.recognize(rows: [row()])
    let date = try stamp("2020-01-02T08:30:00Z")
    let existing = GalaxySSIHealthReading(metric: .glucose, measuredAt: date, value: Decimal(string: "5.7"),
      conditions: "fasting", notes: "Keep the user's note", unitOverride: "mmol/L")
    try f.records.write(existing)
    let original = try XCTUnwrap(f.records.load().current.first)
    let outcome = try f.save(f.plan())
    XCTAssertEqual(outcome.saved, 0); XCTAssertEqual(outcome.duplicates, 1)
    XCTAssertEqual(try f.records.load().current, [original])
    XCTAssertEqual(try f.records.load().reportEvidence?.first?.target.record, original.id)
    XCTAssertEqual(try f.records.load().reportEvidence?.first?.target.revision, original.revision)
  }

  func testIdenticalRowsWithDifferentSourceTextLinkOneMeasurement() throws {
    let f = try Fixture()
    var second = row(); second["source"] = "Repeated visible GLU row"
    try f.recognize(rows: [row(), second])
    let result = try f.save(f.plan())
    XCTAssertEqual(result.saved, 1); XCTAssertEqual(result.duplicates, 1)
    XCTAssertEqual(try f.records.load().current.count, 1)
  }

  func testChangedDraftInvalidatesOldPlanAndFreshPlanPreservesUserEdit() throws {
    let f = try Fixture()
    try f.recognize(rows: [row()])
    let old = try f.plan()
    let item = try XCTUnwrap(old.items.first)
    var reading = item.reading; reading.value = 6; reading.reportedNotation = "6"
    try f.records.stageReportItem(.init(version: UUID(), source: item.source, excerpt: item.excerpt, reading: reading), replacing: nil)
    XCTAssertThrowsError(try f.save(old))
    XCTAssertEqual(try f.save(f.plan()).saved, 1)
    XCTAssertEqual(try f.records.load().current.first?.value, Decimal(6))
  }

  func testCancellationBetweenRowsCommitsNothing() throws {
    let f = try Fixture()
    try f.recognize(rows: [row(), row("weight", "70", "kg")])
    let plan = try f.plan()
    let before = try Data(contentsOf: f.file)
    var checks = 0
    XCTAssertThrowsError(try f.records.saveQuickReport(plan, supplement: .init(), originals: f.originals, now: f.now, active: {
      checks += 1; return checks <= 2
    }))
    XCTAssertTrue(try f.records.load().current.isEmpty)
    XCTAssertNil(try f.records.load().reportReview)
    XCTAssertEqual(try Data(contentsOf: f.file), before)
  }

  func testReplayedPlanAndDeletedImportedMeasurementDoNotCreateMoreRecords() throws {
    let f = try Fixture()
    try f.recognize(rows: [row()])
    let plan = try f.plan()
    _ = try f.save(plan)
    XCTAssertThrowsError(try f.save(plan))
    var saved = try XCTUnwrap(f.records.load().current.first)
    saved.deleted = true; try f.records.write(saved)
    XCTAssertTrue(try f.plan().items.isEmpty)
    XCTAssertEqual(try f.save(f.plan()).saved, 0)
    XCTAssertTrue(try f.records.load().current.isEmpty)
  }

  func testRemovedOriginalBlocksAtomicImport() throws {
    let f = try Fixture()
    try f.recognize(rows: [row()])
    let plan = try f.plan()
    _ = try f.originals.remove(f.originals.previewRemoval(plan.job.original))
    XCTAssertThrowsError(try f.save(plan))
    XCTAssertTrue(try f.records.load().current.isEmpty)
  }

  func testTemporaryOriginalReleasedOnlyAfterCompleteImport() throws {
    let f = try Fixture(retain: false)
    try f.recognize(rows: [row()])
    let original = try f.job().original
    XCTAssertTrue(try f.records.load().reviewOnlyReportOriginals?.contains(original.id) == true)
    XCTAssertTrue(try f.save(f.plan()).releaseOriginal)
    f.originals.releaseCompletedQuickReportOriginals()
    XCTAssertTrue(try f.originals.list().originals.isEmpty)
    XCTAssertThrowsError(try f.originals.read(original))
    XCTAssertEqual(try f.records.load().current.count, 1)
    XCTAssertTrue(try f.records.load().recognitionJobs?.first?.reportImportOutcome?.releaseOriginal == true)
  }

  func testPartialResultKeepsTemporaryOriginalEvenIfSupportedRowsSaved() throws {
    let f = try Fixture(retain: false)
    try f.recognize(rows: [row()], partial: true)
    let outcome = try f.save(f.plan())
    XCTAssertEqual(outcome.saved, 1); XCTAssertTrue(outcome.partial); XCTAssertFalse(outcome.releaseOriginal)
    f.originals.releaseCompletedQuickReportOriginals()
    XCTAssertEqual(try f.originals.list().originals.count, 1)
  }

  func testKeepChoicePromotesTemporaryOriginalAndReviewChoiceNeverDeletesRetainedCopy() throws {
    let temporary = try Fixture(retain: false)
    try temporary.recognize(rows: [row()]); _ = try temporary.save(temporary.plan())
    try temporary.originals.store(temporary.image, name: "keep.png")
    temporary.originals.releaseCompletedQuickReportOriginals()
    XCTAssertEqual(try temporary.originals.list().originals.count, 1)
    let retained = try Fixture()
    try retained.recognize(rows: [row()]); _ = try retained.save(retained.plan())
    _ = try retained.originals.storeReportImage(retained.image, name: "review.png", retainOriginal: false)
    retained.originals.releaseCompletedQuickReportOriginals()
    XCTAssertEqual(try retained.originals.list().originals.count, 1)
    XCTAssertTrue(try retained.records.load().reviewOnlyReportOriginals?.isEmpty ?? true)
  }

  func testExplicitCancelledJobReleasesOnlyItsTemporaryOriginal() throws {
    let f = try Fixture(retain: false)
    let job = try f.job()
    try f.records.cancelRecognitionJob(id: job.id, expected: job.version)
    f.originals.releaseCompletedQuickReportOriginals()
    XCTAssertTrue(try f.originals.list().originals.isEmpty)
  }

  func testExplicitReimportCreatesNewJobAfterRetainedJobCancellation() throws {
    let f = try Fixture()
    let old = try f.job()
    try f.records.cancelRecognitionJob(id: old.id, expected: old.version)
    let next = try f.originals.storeReportImage(f.image, name: "again.png", retainOriginal: true)
    XCTAssertNotEqual(next.id, old.id)
    XCTAssertEqual(next.phase, .queued)
    XCTAssertEqual(try f.originals.list().originals.count, 1)
    XCTAssertEqual(try f.records.load().recognitionJobs?.first(where: { $0.id == old.id })?.phase, .cancelled)
  }

  func testExplicitReimportOfCompletedReportStartsFreshConsentFlow() throws {
    let f = try Fixture()
    try f.recognize(rows: [row()]); _ = try f.save(f.plan())
    let next = try f.originals.storeReportImage(f.image, name: "again.png", retainOriginal: true)
    XCTAssertNotEqual(next.id, f.id)
    XCTAssertNil(next.reportVision)
    XCTAssertEqual(next.phase, .queued)
    XCTAssertEqual(try f.records.load().current.count, 1)
  }

  func testExplicitFileReportImportDoesNotReuseDeviceModeJob() throws {
    let f = try Fixture()
    var archive = try f.records.load()
    archive.recognitionJobs?[0].captureSource = .init(batchID: UUID(), mode: .device, order: 1, cropRevision: nil)
    try f.records.persistQuickReport(archive)
    let next = try f.originals.storeReportImage(f.image, name: "report.png", retainOriginal: true)
    XCTAssertNotEqual(next.id, f.id)
    XCTAssertNil(next.captureSource)
    XCTAssertEqual(next.phase, .queued)
    XCTAssertEqual(try f.records.load().recognitionJobs?.first(where: { $0.id == f.id })?.captureSource?.mode, .device)
  }

  func testFastingSchemaIsOptionalForLegacyButInvalidLabelsAreRejected() throws {
    let object: [String: Any] = ["rows": [row()], "collected": "", "partial": false]
    let legacy = try GalaxySSIHealthReportVision.parse(String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self))
    XCTAssertNil(legacy.fasting)
    for fasting in ["fasting", "non_fasting", "after_meal", ""] {
      var changed = object; changed["fasting"] = fasting
      XCTAssertEqual(try GalaxySSIHealthReportVision.parse(String(decoding: JSONSerialization.data(withJSONObject: changed), as: UTF8.self)).fasting, fasting)
    }
    var invalid = object; invalid["fasting"] = "inferred_from_morning"
    XCTAssertThrowsError(try GalaxySSIHealthReportVision.parse(String(decoding: JSONSerialization.data(withJSONObject: invalid), as: UTF8.self)))
  }

  func testNonFastingLabelDoesNotBecomeFastingScreeningOrVerifiedHours() throws {
    let date = try stamp("2020-01-02T08:30:00Z")
    let reading = GalaxySSIHealthReading(metric: .glucose, measuredAt: date, value: 110, conditions: "non_fasting", unitOverride: "mg/dL")
    let assessment = try XCTUnwrap(GalaxySSIHealthCare.assess([reading], context: nil))
    XCTAssertFalse(assessment.signals.contains(.glucoseContext))
    XCTAssertFalse(assessment.signals.contains(.guidelineReview))
    var answers = GalaxySSIHealthCare.Context.Answers()
    answers.collection = .nonFasting
    XCTAssertTrue(answers.conflictsWithApplicable)
    XCTAssertNil(answers.fastingHours)
  }

  private func row(_ metric: String = "glucose", _ value: String = "5.7", _ unit: String = "mmol/L") -> [String: Any] {
    ["metric": metric, "values": ["value": value], "unit": unit, "reference": "", "source": metric + " " + value]
  }
  private func stamp(_ value: String) throws -> Date { try XCTUnwrap(ISO8601DateFormatter().date(from: value)) }

  func testAutomaticResultMeasurementsAndReceiptAreCommittedTogether() throws {
    let f = try Fixture()
    let outcome = try f.automatic(rows: [row(), row("weight", "70", "kg")])
    let archive = try f.records.load()
    XCTAssertEqual(outcome.saved, 2); XCTAssertEqual(outcome.skipped, 0); XCTAssertEqual(outcome.pending, 0)
    XCTAssertEqual(outcome.imageBytes, 1_000)
    XCTAssertEqual(Set(outcome.recordIDs ?? []), Set(archive.current.map(\.id)))
    XCTAssertEqual(try f.job().reportImportOutcome, outcome)
    XCTAssertEqual(try f.job().reportVision?.rows.count, 2)
    let bytes = try Data(contentsOf: f.file)
    XCTAssertEqual(try f.records.finishAutomaticReport(job: f.id, originals: f.originals, now: f.now, active: { true }), outcome)
    XCTAssertEqual(try Data(contentsOf: f.file), bytes)
  }

  func testAutomaticMissingFastingWaitsForOneLocalContextConfirmation() throws {
    let f = try Fixture()
    let outcome = try f.automatic(rows: [row()], fasting: "")
    XCTAssertEqual(outcome.saved, 0); XCTAssertEqual(outcome.skipped, 0)
    XCTAssertEqual(outcome.pendingConfirmation, true)
    XCTAssertTrue(try f.records.load().current.isEmpty)
    XCTAssertTrue(try f.records.load().reportReview?.isEmpty ?? true)
  }

  func testAutomaticUndatedResultsWaitWithoutDraftsAndRetainOriginal() throws {
    let f = try Fixture(retain: false)
    let outcome = try f.automatic(rows: [row()], collected: "")
    XCTAssertEqual(outcome.saved, 0); XCTAssertEqual(outcome.skipped, 0)
    XCTAssertEqual(outcome.pendingConfirmation, true)
    XCTAssertEqual(outcome.pending, 0)
    XCTAssertTrue(try f.records.load().current.isEmpty)
    XCTAssertTrue(try f.records.load().reportReview?.isEmpty ?? true)
    f.originals.releaseCompletedQuickReportOriginals()
    XCTAssertEqual(try f.originals.list().originals.count, 1)
    XCTAssertFalse(try XCTUnwrap(f.job().reportImportOutcome).releaseOriginal)
  }

  func testAutomaticUnknownUnitsAndConflictingRowsAreSkippedNotManuallyStaged() throws {
    let f = try Fixture(retain: false)
    let outcome = try f.automatic(rows: [row("glucose", "5.7", ""), row("weight", "70", "kg"), row("weight", "72", "kg")])
    XCTAssertEqual(outcome.skipped, 3); XCTAssertEqual(outcome.saved, 0)
    XCTAssertTrue(try f.records.load().reportReview?.isEmpty ?? true)
    f.originals.releaseCompletedQuickReportOriginals()
    XCTAssertEqual(try f.originals.list().originals.count, 1)
  }

  func testAutomaticCancellationBetweenRowsDoesNotCommitModelResultOrReceipt() throws {
    let f = try Fixture()
    let job = try f.ready()
    let before = try Data(contentsOf: f.file)
    let result = try f.result(rows: [row(), row("weight", "70", "kg")])
    var checks = 0
    XCTAssertThrowsError(try f.records.commitAutomaticReportVision(result, job: job, consent: .init(f.records.load()),
      zone: "UTC", imageBytes: 1_000, originals: f.originals, now: f.now, active: { checks += 1; return checks <= 3 }))
    XCTAssertEqual(try Data(contentsOf: f.file), before)
    XCTAssertNil(try f.job().reportVision)
    XCTAssertNil(try f.job().reportImportOutcome)
    XCTAssertTrue(try f.records.load().current.isEmpty)
  }

  func testAutomaticConsentRevocationInvalidatesResponseBeforeCommit() throws {
    let f = try Fixture()
    let job = try f.ready()
    let consent = try GalaxySSIHealthReportVision.Consent(f.records.load())
    try f.records.setHealthOnlinePermission(false)
    let before = try Data(contentsOf: f.file)
    XCTAssertThrowsError(try f.records.commitAutomaticReportVision(f.result(rows: [row()]), job: job, consent: consent,
      zone: "UTC", imageBytes: 1_000, originals: f.originals, now: f.now, active: { true }))
    XCTAssertEqual(try Data(contentsOf: f.file), before)
    XCTAssertNil(try f.job().reportVision)
  }

  func testAutomaticPayloadOver100000BytesCannotCreateAnyRecords() throws {
    let f = try Fixture()
    let job = try f.ready()
    let before = try Data(contentsOf: f.file)
    XCTAssertEqual(GalaxySSIHealthReportCodex.maximumImageBytes, 100_000)
    XCTAssertThrowsError(try f.records.commitAutomaticReportVision(f.result(rows: [row()]), job: job,
      consent: .init(f.records.load()), zone: "UTC", imageBytes: 100_001, originals: f.originals, now: f.now, active: { true }))
    XCTAssertEqual(try Data(contentsOf: f.file), before)
  }

  func testAutomaticDuplicateReceiptLinksExactExistingRecordWithoutOverwrite() throws {
    let f = try Fixture()
    try f.records.write(.init(metric: .glucose, measuredAt: stamp("2020-01-02T08:30:00Z"), value: Decimal(string: "5.7"),
      conditions: "fasting", notes: "Retain note", unitOverride: "mmol/L"))
    let existing = try XCTUnwrap(f.records.load().current.first)
    let outcome = try f.automatic(rows: [row()])
    XCTAssertEqual(outcome.saved, 0); XCTAssertEqual(outcome.duplicates, 1)
    XCTAssertEqual(outcome.recordIDs, [existing.id])
    XCTAssertEqual(try f.records.load().current, [existing])
    XCTAssertEqual(try f.records.load().reportEvidence?.first?.target.record, existing.id)
  }

  func testAutomaticEmptyReplyDoesNotCreateARecognitionReceiptOrMeasurements() throws {
    let f = try Fixture()
    XCTAssertThrowsError(try f.automatic(rows: [], partial: true))
    XCTAssertTrue(try f.records.load().current.isEmpty)
    XCTAssertNil(try f.job().reportVision)
    XCTAssertNil(try f.job().reportImportOutcome)
  }

  func testAcceptedRowsImportAndKeepOriginalWhenOtherRowsAreRejected() throws {
    let f = try Fixture(retain: false)
    let outcome = try f.automatic(rows: [row("weight", "70", "kg"), row("unsupported", "1", "kg")])
    XCTAssertEqual(outcome.saved, 1); XCTAssertTrue(outcome.partial)
    XCTAssertEqual(try f.records.load().current.first?.metric, .weight)
    XCTAssertEqual(try f.job().reportVision?.rejectedRows?["unsupported_metric"], 1)
    f.originals.releaseCompletedQuickReportOriginals()
    XCTAssertEqual(try f.originals.list().originals.count, 1)
  }

  func testAutomaticCompleteImportReleasesOnlyTemporaryOriginalAndKeepsReceipt() throws {
    let f = try Fixture(retain: false)
    let outcome = try f.automatic(rows: [row()])
    XCTAssertTrue(outcome.releaseOriginal)
    f.originals.releaseCompletedQuickReportOriginals()
    XCTAssertTrue(try f.originals.list().originals.isEmpty)
    XCTAssertEqual(try f.job().reportImportOutcome?.recordIDs, outcome.recordIDs)
    XCTAssertEqual(try f.records.load().current.count, 1)
  }

  func testLegacyRecognitionWaitsForLocalContextWithoutResending() throws {
    let f = try Fixture()
    try f.recognize(rows: [row()], collected: "")
    let before = try f.job().reportVision
    let outcome = try f.records.finishAutomaticReport(job: f.id, originals: f.originals, now: f.now, active: { true })
    XCTAssertEqual(outcome.skipped, 0); XCTAssertEqual(outcome.imageBytes, 0)
    XCTAssertEqual(outcome.pendingConfirmation, true)
    XCTAssertEqual(try f.job().reportVision, before)
    XCTAssertTrue(try f.records.load().reportReview?.isEmpty ?? true)
  }

  func testLegacyOutcomeDecodesWithoutAutomaticReceiptFields() throws {
    let data = Data(#"{"saved":1,"duplicates":0,"pending":2,"partial":true,"releaseOriginal":false}"#.utf8)
    let outcome = try JSONDecoder().decode(Quick.Outcome.self, from: data)
    XCTAssertEqual(outcome.pending, 2)
    XCTAssertNil(outcome.skipped); XCTAssertNil(outcome.imageBytes); XCTAssertNil(outcome.recordIDs)
  }

  func testLegacyCompleteReceiptMigratesAfterTemporaryOriginalWasReleased() throws {
    let f = try Fixture(retain: false)
    try f.recognize(rows: [row()])
    _ = try f.save(f.plan())
    f.originals.releaseCompletedQuickReportOriginals()
    XCTAssertTrue(try f.originals.list().originals.isEmpty)
    let readings = try f.records.load().current
    let receipt = try f.records.finishAutomaticReport(job: f.id, originals: f.originals, now: f.now, active: { true })
    XCTAssertEqual(receipt.saved, 1); XCTAssertEqual(receipt.skipped, 0)
    XCTAssertEqual(receipt.recordIDs, readings.map(\.id))
    XCTAssertEqual(try f.records.load().current, readings)
  }

  @MainActor private final class Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let file: URL
    let records: GalaxySSIHealthRecords
    let originals: GalaxySSIHealthOriginalStore
    let image: Data
    let id: UUID
    let now = Date()
    init(retain: Bool = true) throws {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      file = root.appendingPathComponent("records")
      let secrets = InMemorySecretStore()
      records = .init(owner: "quick-report", secrets: secrets, isolatedFile: file)
      originals = .init(owner: "quick-report", secrets: secrets, fixtureDirectory: root.appendingPathComponent("originals"), restoreRecordsFile: file)
      let format = UIGraphicsImageRendererFormat(); format.scale = 1
      image = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
        UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
      }.pngData())
      try records.setPrivacy(.overview, enabled: true)
      try records.setHealthOnlinePermission(true)
      id = try originals.storeReportImage(image, name: "fixture.png", retainOriginal: retain).id
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func job() throws -> GalaxySSIHealthRecognitionJobs.Job { try XCTUnwrap(records.load().recognitionJobs?.first { $0.id == id }) }
    func recognize(rows: [[String: Any]], collected: String = "2020-01-02 08:30:00Z", fasting: String = "fasting",
                   partial: Bool = false, zone: String = "UTC") throws {
      _ = try ready()
      try records.commitReportVision(result(rows: rows, collected: collected, fasting: fasting, partial: partial),
        job: job(), consent: .init(records.load()), zone: zone)
    }
    func ready() throws -> GalaxySSIHealthRecognitionJobs.Job {
      let original = try job()
      let run = try records.beginRecognitionJob(id: id, expected: original.version)
      try records.commitRecognitionPage(id: id, run: run, page: .init(index: 0, fromOCR: true, lines: []))
      return try job()
    }
    func result(rows: [[String: Any]], collected: String = "2020-01-02 08:30:00Z", fasting: String = "fasting",
        partial: Bool = false) throws -> GalaxySSIHealthReportVision.Result {
      let object: [String: Any] = ["rows": rows, "collected": collected, "fasting": fasting, "partial": partial]
      return try GalaxySSIHealthReportVision.parse(String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self))
    }
    func automatic(rows: [[String: Any]], collected: String = "2020-01-02 08:30:00Z", fasting: String = "fasting",
        partial: Bool = false) throws -> Quick.Outcome {
      let original = try ready()
      return try records.commitAutomaticReportVision(result(rows: rows, collected: collected, fasting: fasting, partial: partial),
        job: original, consent: .init(records.load()), zone: "UTC", imageBytes: 1_000, originals: originals, now: now, active: { true })
    }
    func plan() throws -> Quick.Plan { try records.quickReportPlan(job: id, originals: originals, now: now) }
    func save(_ plan: Quick.Plan, supplement: Quick.Supplement = .init()) throws -> Quick.Outcome {
      try records.saveQuickReport(plan, supplement: supplement, originals: originals, now: now, active: { true })
    }
  }
}
