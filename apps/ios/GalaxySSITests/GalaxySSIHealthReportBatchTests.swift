import XCTest
import UIKit
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthReportBatchTests: XCTestCase {
  typealias Batch = GalaxySSIHealthReportBatch

  func testBatchHoldsEvenCompleteMeasurementsUntilAllReportsAreReady() throws {
    let f = try Fixture()
    let first = try f.stage(value: "5.7")
    XCTAssertTrue(try f.records.load().current.isEmpty)
    XCTAssertEqual(try f.job(first).reportImportOutcome?.pendingConfirmation, true)
    let second = try f.stage(value: "70", metric: "weight", unit: "kg")
    let review = try f.review([first, second])
    XCTAssertFalse(review.scope.needed)
    let results = try f.complete(review)
    XCTAssertEqual(results.map(\.saved), [1, 1])
    XCTAssertEqual(try f.records.load().current.count, 2)
    XCTAssertTrue(results.allSatisfy { $0.contextConfirmed == true && $0.pendingConfirmation == false })
  }

  func testOneConfirmationPreservesEachPrintedDateAndPrintedFasting() throws {
    let f = try Fixture()
    let first = try f.stage(value: "5.7", collected: "2020-01-02", fasting: "fasting")
    let second = try f.stage(value: "6.0", collected: "2020-01-03", fasting: "")
    let review = try f.review([first, second])
    XCTAssertTrue(review.scope.needsTime); XCTAssertTrue(review.scope.needsCondition)
    XCTAssertFalse(review.scope.needsDate)
    _ = try f.complete(review, input: .init(day: stamp("1999-01-01T00:00:00Z"),
      clock: stamp("2020-01-01T08:30:00Z"), condition: "after_meal_1h"))
    let current = try f.records.load().current.sorted { $0.measuredAt < $1.measuredAt }
    XCTAssertEqual(current.map(\.measuredAt), try [stamp("2020-01-02T08:30:00Z"), stamp("2020-01-03T08:30:00Z")])
    XCTAssertEqual(current.map(\.conditions), ["fasting", "after_meal_1h"])
  }

  func testFullPrintedTimestampIsNotReplacedByBatchDateOrClock() throws {
    let f = try Fixture()
    let first = try f.stage(value: "5.7", collected: "2020-01-02 08:30:00Z")
    let second = try f.stage(value: "70", metric: "weight", unit: "kg", collected: "")
    let review = try f.review([first, second])
    XCTAssertTrue(review.scope.needsDate)
    _ = try f.complete(review, input: .init(day: stamp("2020-02-03T00:00:00Z"), clock: stamp("2020-01-01T12:20:00Z")))
    let current = try f.records.load().current
    XCTAssertEqual(current.first { $0.metric == .glucose }?.measuredAt, try stamp("2020-01-02T08:30:00Z"))
    XCTAssertEqual(current.first { $0.metric == .weight }?.measuredAt, try stamp("2020-02-03T12:20:00Z"))
  }

  func testAmbiguousDSTTimeInLastReportRollsBackWholeConfirmation() throws {
    let f = try Fixture(zone: "America/New_York")
    let first = try f.stage(value: "70", metric: "weight", unit: "kg", collected: "2020-10-31")
    let second = try f.stage(value: "5.7", collected: "2020-11-01")
    let review = try f.review([first, second])
    let bytes = try Data(contentsOf: f.file)
    XCTAssertThrowsError(try f.complete(review, input: .init(clock: stamp("2020-11-01T05:30:00Z"))))
    XCTAssertEqual(try Data(contentsOf: f.file), bytes)
    XCTAssertTrue(try f.records.load().current.isEmpty)
    XCTAssertEqual(try f.job(first).reportImportOutcome?.pendingConfirmation, true)
  }

  func testPendingSourcesAreNotReleasedAndCancelDoesNotSaveMeasurements() throws {
    let f = try Fixture(retain: false)
    let id = try f.stage(value: "5.7", collected: "")
    f.originals.releaseCompletedQuickReportOriginals()
    XCTAssertEqual(try f.originals.list().originals.count, 1)
    let review = try f.review([id])
    XCTAssertThrowsError(try f.records.completeReportBatch(review, supplement: .init(), originals: f.originals,
      confirmed: false, zone: f.zone, now: f.now))
    XCTAssertTrue(try f.records.load().current.isEmpty)
  }

  func testRevocationAndRenewalInvalidateOldConfirmationEpoch() throws {
    let f = try Fixture()
    let id = try f.stage(value: "5.7")
    let review = try f.review([id])
    try f.records.setPrivacy(.overview, enabled: false)
    try f.records.setPrivacy(.overview, enabled: true)
    let bytes = try Data(contentsOf: f.file)
    XCTAssertThrowsError(try f.complete(review))
    XCTAssertEqual(try Data(contentsOf: f.file), bytes)
  }

  func testInterveningMeasurementEditRejectsStaleBatchBeforeAnyMutation() throws {
    let f = try Fixture()
    let id = try f.stage(value: "5.7")
    let review = try f.review([id])
    try f.records.write(.init(metric: .weight, measuredAt: f.now, value: 70, unitOverride: "kg"))
    let bytes = try Data(contentsOf: f.file)
    XCTAssertThrowsError(try f.complete(review))
    XCTAssertEqual(try Data(contentsOf: f.file), bytes)
    XCTAssertEqual(try f.records.load().current.count, 1)
  }

  func testChangedJobOrExpiredReviewCannotBeConfirmed() throws {
    let f = try Fixture()
    let id = try f.stage(value: "5.7")
    let review = try f.review([id])
    XCTAssertThrowsError(try f.records.completeReportBatch(review, supplement: .init(), originals: f.originals,
      confirmed: true, zone: f.zone, now: review.expires))
    try f.records.attachSelectedReportJob(f.job(id), batch: UUID(), modelFirst: true)
    XCTAssertThrowsError(try f.complete(review))
    XCTAssertTrue(try f.records.load().current.isEmpty)
  }

  func testConfirmationReplaysCannotResurrectDeletedMeasurement() throws {
    let f = try Fixture()
    let id = try f.stage(value: "5.7")
    let review = try f.review([id])
    _ = try f.complete(review)
    var reading = try XCTUnwrap(f.records.load().current.first)
    reading.deleted = true; try f.records.write(reading)
    XCTAssertThrowsError(try f.complete(review))
    XCTAssertThrowsError(try f.review([id]))
    XCTAssertTrue(try f.records.load().current.isEmpty)
  }

  func testNearbyReportUpdateRetainsIDRevisionsNotesAndAllSourceLinks() throws {
    let f = try Fixture()
    let first = try f.stage(value: "5.7")
    _ = try f.complete(f.review([first]))
    var prior = try XCTUnwrap(f.records.load().current.first)
    let originalSource = try XCTUnwrap(prior.reportSource)
    prior.notes = "Retain user note"; try f.records.write(prior)
    prior = try XCTUnwrap(f.records.load().current.first)
    let second = try f.stage(value: "6.2", collected: "2020-01-02 09:20:00Z")
    _ = try f.complete(f.review([second]))
    let archive = try f.records.load(), updated = try XCTUnwrap(archive.current.first)
    XCTAssertEqual(archive.current.count, 1)
    XCTAssertEqual(updated.id, prior.id); XCTAssertEqual(updated.revision, prior.revision + 1)
    XCTAssertEqual(updated.value, Decimal(string: "6.2")); XCTAssertEqual(updated.notes, prior.notes)
    XCTAssertTrue(archive.revisions.contains(prior))
    XCTAssertTrue(archive.reportEvidence?.contains { $0.source == originalSource && $0.target.record == updated.id &&
      $0.target.revision == updated.revision } == true)
  }

  func testNearbyImportDoesNotOverwriteManualMeasurement() throws {
    let f = try Fixture()
    try f.records.write(.init(metric: .glucose, measuredAt: stamp("2020-01-02T08:00:00Z"), value: 4,
      conditions: "fasting", notes: "Manual", unitOverride: "mmol/L"))
    let manual = try XCTUnwrap(f.records.load().current.first)
    let id = try f.stage(value: "5.7")
    _ = try f.complete(f.review([id]))
    XCTAssertEqual(try f.records.load().current.count, 2)
    XCTAssertTrue(try f.records.load().current.contains(manual))
  }

  func testNearbyBoundaryAndConditionUnitAndDeletionFilters() throws {
    let at = try stamp("2020-01-02T08:30:00Z")
    var input = GalaxySSIHealthReading(metric: .glucose, measuredAt: at, value: 5, conditions: "after_meal_1h", unitOverride: "mmol/L")
    var prior = input; prior.id = UUID(); prior.revision = 1
    prior.reportSource = .init(original: UUID(), sha256: String(repeating: "a", count: 64), page: 0, region: 0, fromOCR: true)
    prior.measuredAt = at.addingTimeInterval(-3600)
    XCTAssertEqual(Batch.nearby(input, current: [prior])?.id, prior.id)
    prior.measuredAt = at.addingTimeInterval(-3601)
    XCTAssertNil(Batch.nearby(input, current: [prior]))
    prior.measuredAt = at; prior.conditions = "after_meal_2h"
    XCTAssertNil(Batch.nearby(input, current: [prior]))
    input.conditions = prior.conditions; prior.unitOverride = "mg/dL"
    XCTAssertNil(Batch.nearby(input, current: [prior]))
    prior.unitOverride = input.unit; prior.deleted = true
    XCTAssertNil(Batch.nearby(input, current: [prior]))
    prior.deleted = false; prior.reportSource = nil
    XCTAssertNil(Batch.nearby(input, current: [prior]))
  }

  func testPostMealHoursRemainDistinctAndAreNotFastingScreening() throws {
    let f = try Fixture()
    for condition in ["after_meal_1h", "after_meal_2h"] {
      let id = try f.stage(value: "6.2", fasting: condition)
      _ = try f.complete(f.review([id]))
    }
    let current = try f.records.load().current
    XCTAssertEqual(Set(current.map(\.conditions)), ["after_meal_1h", "after_meal_2h"])
    for reading in current {
      let assessment = try XCTUnwrap(GalaxySSIHealthCare.assess([reading], context: nil))
      XCTAssertFalse(assessment.signals.contains(.glucoseContext))
      XCTAssertFalse(assessment.signals.contains(.guidelineReview))
    }
    for collection in [GalaxySSIHealthCare.Context.Answers.Collection.afterMeal1h, .afterMeal2h] {
      var answers = GalaxySSIHealthCare.Context.Answers(); answers.collection = collection
      XCTAssertTrue(answers.conflictsWithApplicable)
      XCTAssertEqual(try JSONDecoder().decode(GalaxySSIHealthCare.Context.Answers.self, from: JSONEncoder().encode(answers)), answers)
    }
  }

  func testBatchRestorationDoesNotRestoreNetworkAuthorization() throws {
    let f = try Fixture()
    let id = try f.stage(value: "5.7")
    let selection = try GalaxySSIHealthSelectedFiles.restore(batch: f.batch, records: f.records)
    XCTAssertNil(selection.approval)
    XCTAssertEqual(selection.entries.map(\.id), [id])
    XCTAssertEqual(try f.job(id).reportImportOutcome?.pendingConfirmation, true)
  }

  func testSelectedTableParsesLocallyAndPersistsEncryptedReviewNotMeasurements() throws {
    let f = try Fixture()
    let url = f.root.appendingPathComponent("table.csv")
    let csv = "PrivateSyntheticColumn,Value\nweight,70\n"
    try Data(csv.utf8).write(to: url)
    let selection = try GalaxySSIHealthSelectedFiles.read([url, url], records: f.records, originals: f.originals,
      retainOriginal: false, approval: nil)
    XCTAssertEqual(selection.entries.count, 1)
    guard case .table(let table) = try XCTUnwrap(selection.entries.first).kind else { return XCTFail("Expected local table") }
    let draft = try XCTUnwrap(f.records.load().tableReviews?.first)
    XCTAssertEqual(draft.id, table.id); XCTAssertEqual(draft.reportBatchID, selection.id)
    XCTAssertEqual(draft.data, Data(csv.utf8)); XCTAssertFalse(draft.retainOriginal)
    XCTAssertTrue(try f.records.load().current.isEmpty)
    XCTAssertFalse(String(decoding: try Data(contentsOf: f.file), as: UTF8.self).contains("PrivateSyntheticColumn"))
  }

  func testEmptyAndOversizedFileSelectionAreRejectedWithoutImport() throws {
    let f = try Fixture()
    XCTAssertThrowsError(try GalaxySSIHealthSelectedFiles.read([], records: f.records, originals: f.originals, retainOriginal: false, approval: nil))
    let urls = (0...GalaxySSIHealthRecognitionJobs.maximumJobs).map { f.root.appendingPathComponent("\($0).png") }
    XCTAssertThrowsError(try GalaxySSIHealthSelectedFiles.read(urls, records: f.records, originals: f.originals, retainOriginal: false, approval: nil))
    XCTAssertTrue(try f.records.load().current.isEmpty)
  }

  func testReviewCannotSaveSubsetWhileAnotherBatchImageIsStillAwaitingRecognition() throws {
    let f = try Fixture()
    let first = try f.stage(value: "5.7")
    let pending = try f.prepare()
    XCTAssertThrowsError(try f.review([first]))
    XCTAssertTrue(try f.records.load().current.isEmpty)
    try f.records.failSelectedReportJob(id: pending, batch: f.batch)
    XCTAssertEqual(try f.complete(f.review([first])).first?.saved, 1)
  }

  func testTableAndHealthKitSourcesCannotBeNearbyReplacementTargets() throws {
    let at = try stamp("2020-01-02T08:30:00Z")
    let incoming = GalaxySSIHealthReading(metric: .glucose, measuredAt: at, value: 5, conditions: "fasting", unitOverride: "mmol/L")
    var previous = incoming; previous.id = UUID(); previous.revision = 1
    previous.reportSource = .init(original: UUID(), sha256: String(repeating: "a", count: 64), page: 0, region: 0, fromOCR: true)
    previous.tableSource = .init(batch: UUID(), row: 1, sha256: String(repeating: "b", count: 64))
    XCTAssertNil(Batch.nearby(incoming, current: [previous]))
    previous.tableSource = nil
    previous.healthKitSource = .init(key: "synthetic", origin: nil, name: nil)
    XCTAssertNil(Batch.nearby(incoming, current: [previous]))
  }

  func testPickerApprovalBindsOwnerDestinationEpochAndExpiry() throws {
    let f = try Fixture()
    let route = GalaxySSIHealthDesktopResearch.Route(connector: .init(contactId: "desktop:codex", desktopId: "desktop",
      clientRouteId: "route", modelId: "saved-model", reasoningEffort: .high), desktopFingerprint: "pinned")
    let target = GalaxySSIHealthReportCodex.Target(route: route, authority: "Fixture Desktop")
    let consent = try GalaxySSIHealthReportVision.Consent(f.records.load())
    let approval = GalaxySSIHealthReportPickerApproval(owner: f.records.owner, consent: consent, target: target,
      expires: f.now.addingTimeInterval(60))
    XCTAssertTrue(approval.matches(owner: f.records.owner, consent: consent, target: target, now: f.now))
    XCTAssertFalse(approval.matches(owner: "other", consent: consent, target: target, now: f.now))
    XCTAssertFalse(approval.matches(owner: f.records.owner, consent: consent, target: nil, now: f.now))
    XCTAssertFalse(approval.matches(owner: f.records.owner, consent: consent, target: target, now: approval.expires))
    try f.records.setHealthOnlinePermission(false); try f.records.setHealthOnlinePermission(true)
    XCTAssertFalse(approval.matches(owner: f.records.owner, consent: try .init(f.records.load()), target: target, now: f.now))
  }

  func testUnrepairableUnitFailureKeepsItsRowSpecificDeferredReason() throws {
    let f = try Fixture(retain: false)
    let id = try f.stage(value: "5.7", unit: "")
    let results = try f.complete(f.review([id]))
    XCTAssertEqual(results.first?.skipped, 1)
    XCTAssertEqual(Set(results.first?.deferred?.values.map { $0 } ?? []), Set([Batch.Deferred.unit]))
    XCTAssertTrue(try f.records.load().current.isEmpty)
    f.originals.releaseCompletedQuickReportOriginals()
    XCTAssertEqual(try f.originals.list().originals.count, 1)
  }

  func testExplicitSkipReleasesTheBatchBarrierWithoutSendingTheSkippedImage() throws {
    let f = try Fixture()
    let first = try f.stage(value: "5.7")
    let skipped = try f.prepare()
    let expected = try f.job(skipped)
    XCTAssertThrowsError(try f.review([first]))
    try f.records.skipSelectedReportImage(expected)
    XCTAssertEqual(try f.job(skipped).phase, .cancelled)
    XCTAssertNil(try f.job(skipped).reportVision)
    XCTAssertThrowsError(try f.records.skipSelectedReportImage(expected))
    XCTAssertEqual(try f.complete(f.review([first])).first?.saved, 1)
    XCTAssertEqual(try f.records.load().current.count, 1)
  }

  func testAsyncSelectionStopsBeforeWritingWhenTheImportIsNoLongerActive() async throws {
    let f = try Fixture()
    let bytes = try Data(contentsOf: f.file)
    do {
      _ = try await GalaxySSIHealthSelectedFiles.readAsync([f.root.appendingPathComponent("unused.png")],
        records: f.records, originals: f.originals, retainOriginal: false, approval: nil, active: { false })
      XCTFail("Expected cancellation")
    } catch is CancellationError { }
    XCTAssertEqual(try Data(contentsOf: f.file), bytes)
    XCTAssertTrue(try f.records.load().recognitionJobs?.isEmpty ?? true)
  }

  func testReceivedReportsCanBeConfirmedLocallyWithOnlineRequestsDisabled() throws {
    let f = try Fixture()
    let id = try f.stage(value: "5.7")
    let vision = try f.job(id).reportVision
    try f.records.setHealthOnlinePermission(false)
    let result = try f.complete(f.review([id]))
    XCTAssertEqual(result.first?.saved, 1)
    XCTAssertNil(try f.records.load().healthOnlinePermission)
    XCTAssertEqual(try f.job(id).reportVision, vision)
    XCTAssertEqual(try f.records.load().current.count, 1)
  }

  func testContinuingFailedImageRearmsBarrierAndPreservesOtherReceipt() throws {
    let f = try Fixture()
    let first = try f.stage(value: "5.7"), second = try f.prepare()
    try f.records.failSelectedReportJob(id: second, batch: f.batch, problem: .replyTimeout)
    let receipt = try f.job(first).reportImportOutcome
    let failed = try f.job(second)
    XCTAssertEqual(failed.reportFailure, .replyTimeout)
    XCTAssertTrue(GalaxySSIHealthSelectedFiles.canContinue(failed, batch: f.batch))
    let retried = try f.records.prepareReportContinuation(failed)
    XCTAssertNil(retried.reportFailure); XCTAssertEqual(retried.phase, .completed)
    XCTAssertThrowsError(try f.review([first]))
    XCTAssertEqual(try f.job(first).reportImportOutcome, receipt)
    let result = GalaxySSIHealthReportVision.Result(rows: [.init(metric: .weight, values: ["value": "70"], unit: "kg",
      reference: "", source: "Synthetic retry")], collected: "2020-01-02 08:30:00Z", partial: false, fasting: "fasting")
    _ = try f.records.commitAutomaticReportVision(result, job: retried, consent: .init(f.records.load()), zone: f.zone.identifier,
      imageBytes: 1_000, originals: f.originals, now: f.now, holdForBatch: true, active: { true })
    XCTAssertEqual(try f.job(first).reportImportOutcome, receipt)
    XCTAssertNil(try f.job(second).reportFailure)
    XCTAssertTrue(try f.records.load().current.isEmpty)
    _ = try f.complete(f.review([first, second]))
    XCTAssertEqual(try f.records.load().current.count, 2)
  }

  func testContinuationPolicyRejectsSuccessfulOtherGroupAndSkippedFiles() throws {
    let f = try Fixture()
    let completed = try f.stage(value: "5.7"), pending = try f.prepare()
    XCTAssertFalse(try GalaxySSIHealthSelectedFiles.canContinue(f.job(completed), batch: f.batch))
    let job = try f.job(pending)
    XCTAssertTrue(GalaxySSIHealthSelectedFiles.canContinue(job, batch: f.batch))
    XCTAssertFalse(GalaxySSIHealthSelectedFiles.canContinue(job, batch: UUID()))
    try f.records.skipSelectedReportImage(job)
    XCTAssertFalse(try GalaxySSIHealthSelectedFiles.canContinue(f.job(pending), batch: f.batch))
  }

  private func stamp(_ value: String) throws -> Date { try XCTUnwrap(ISO8601DateFormatter().date(from: value)) }

  @MainActor private final class Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let file: URL
    let records: GalaxySSIHealthRecords
    let originals: GalaxySSIHealthOriginalStore
    let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    let batch = UUID()
    let zone: TimeZone
    let retain: Bool
    var counter = 0
    init(zone: String = "UTC", retain: Bool = true) throws {
      self.zone = try XCTUnwrap(TimeZone(identifier: zone)); self.retain = retain
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      file = root.appendingPathComponent("records")
      let secrets = InMemorySecretStore()
      records = .init(owner: "report-batch", secrets: secrets, isolatedFile: file)
      originals = .init(owner: "report-batch", secrets: secrets, fixtureDirectory: root.appendingPathComponent("originals"), restoreRecordsFile: file)
      try records.setPrivacy(.overview, enabled: true); try records.setHealthOnlinePermission(true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func job(_ id: UUID) throws -> GalaxySSIHealthRecognitionJobs.Job {
      try XCTUnwrap(records.load().recognitionJobs?.first { $0.id == id })
    }
    func stage(value: String, metric: String = "glucose", unit: String = "mmol/L",
        collected: String = "2020-01-02 08:30:00Z", fasting: String = "fasting") throws -> UUID {
      let id = try prepare()
      let json: [String: Any] = ["rows": [["metric": metric, "values": ["value": value], "unit": unit, "reference": "", "source": "Synthetic \(metric) \(value)"]],
        "collected": collected, "fasting": fasting, "partial": false]
      let result = try GalaxySSIHealthReportVision.parse(String(decoding: JSONSerialization.data(withJSONObject: json), as: UTF8.self))
      _ = try records.commitAutomaticReportVision(result, job: job(id), consent: .init(records.load()), zone: zone.identifier,
        imageBytes: 1_000, originals: originals, now: now, holdForBatch: true, active: { true })
      return id
    }
    func prepare() throws -> UUID {
      counter += 1
      let format = UIGraphicsImageRendererFormat(); format.scale = 1
      let data = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { context in
        UIColor(hue: CGFloat(counter) / 20, saturation: 0.5, brightness: 0.9, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
      }.pngData())
      let original = try originals.storeReportImage(data, name: "\(counter).png", retainOriginal: retain, batchID: batch, modelFirst: true)
      let run = try records.beginRecognitionJob(id: original.id, expected: original.version)
      try records.commitRecognitionPage(id: original.id, run: run, page: .init(index: 0, fromOCR: false, lines: []))
      return original.id
    }
    func review(_ ids: [UUID]) throws -> Batch.Review { try records.reportBatchReview(ids: ids, originals: originals, zone: zone, now: now) }
    func complete(_ review: Batch.Review, input: Batch.Supplement = .init()) throws -> [GalaxySSIHealthReportQuickImport.Outcome] {
      try records.completeReportBatch(review, supplement: input, originals: originals, confirmed: true, zone: zone, now: now)
    }
  }
}
