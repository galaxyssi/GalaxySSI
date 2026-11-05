import CoreGraphics
import Foundation
import UIKit
import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthRecordsTests: XCTestCase {
  func testSourceAttentionOnlyShowsSelectedFailuresAndAcknowledgesExactRevision() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var ledger = GalaxySSIHealthSourceAttention()
    ledger.selected = [.weight, .sleep]
    ledger.readFinished(.heartRate, succeeded: false, now: now)
    ledger.readFinished(.weight, succeeded: false, now: now)
    let original = try XCTUnwrap(ledger.active.first)
    ledger.readFinished(.sleep, succeeded: false, now: now.addingTimeInterval(5))
    ledger.readFinished(.weight, succeeded: false, now: now.addingTimeInterval(10))
    ledger.acknowledge(original)
    XCTAssertEqual(ledger.active.map(\.scope), [.weight, .sleep])
    ledger.selected.remove(.sleep)
    XCTAssertEqual(ledger.active.map(\.scope), [.weight])
    ledger.acknowledge(try XCTUnwrap(ledger.active.first))
    XCTAssertTrue(ledger.active.isEmpty)
    ledger.selected.insert(.sleep)
    ledger.readFinished(.sleep, succeeded: true, now: now)
    XCTAssertTrue(ledger.active.isEmpty)
  }

  @MainActor
  func testCorruptEncryptedSourceAttentionDoesNotHideMeasurementsOrReplaceIncidents() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let sidecar = file.appendingPathExtension("source-attention")
    defer {
      try? FileManager.default.removeItem(at: file)
      try? FileManager.default.removeItem(at: sidecar)
    }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let now = Date()
    try records.write(.init(metric: .weight, measuredAt: now, value: 60))
    try records.updateSourceAttention {
      $0.selected = [.weight]
      $0.readFinished(.weight, succeeded: false, now: now)
    }
    let reopened = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    XCTAssertEqual(try reopened.loadSourceAttention().active.map(\.scope), [.weight])
    let foreign = GalaxySSIHealthRecords(owner: "another", secrets: secrets, isolatedFile: file)
    XCTAssertThrowsError(try foreign.loadSourceAttention())
    let corrupt = Data("corrupt fixture".utf8)
    try corrupt.write(to: sidecar)
    XCTAssertThrowsError(try reopened.loadSourceAttention())
    XCTAssertThrowsError(try reopened.updateSourceAttention { $0.selected.removeAll() })
    XCTAssertEqual(try Data(contentsOf: sidecar), corrupt)
    XCTAssertEqual(try reopened.load().current.count, 1)
  }

  func testRecordCenterSeparatesReviewDraftsAndRequiresExactOriginalIdentity() {
    let id = UUID()
    let original = GalaxySSIHealthOriginalStore.Original(id: id, name: "fixture.pdf", kind: .pdf,
      fileExtension: "pdf", importedAt: Date(), bytes: 123, sha256: String(repeating: "a", count: 64))
    let confirmed = GalaxySSIHealthReading(metric: .weight, measuredAt: Date(), value: 60)
    let pending = GalaxySSIHealthReading(metric: .weight, measuredAt: Date(), value: 70)
    let source = GalaxySSIHealthReportReview.Source(original: id, sha256: original.sha256,
      page: 2, region: 3, fromOCR: true)
    var archive = GalaxySSIHealthRecords.Archive()
    archive.revisions = [confirmed]
    archive.reportReview = [.init(version: UUID(), source: source, excerpt: "Synthetic report", reading: pending)]
    archive.draft = GalaxySSIHealthDraft()
    let snapshot = GalaxySSIHealthRecordCenterSnapshot(archive: archive, originals: [original])
    XCTAssertEqual(snapshot.confirmed.map(\.id), [confirmed.id])
    XCTAssertEqual(snapshot.pending.count, 1)
    XCTAssertEqual(snapshot.pending.first?.original, original)
    XCTAssertEqual(snapshot.pending.first?.items.first?.source.page, 2)
    XCTAssertNotNil(snapshot.draft)
    let missing = GalaxySSIHealthRecordCenterSnapshot(archive: archive, originals: [])
    XCTAssertNil(missing.pending.first?.original)
    XCTAssertEqual(missing.pending.first?.items.count, 1)
    let replaced = GalaxySSIHealthOriginalStore.Original(id: id, name: original.name, kind: .pdf,
      fileExtension: "pdf", importedAt: original.importedAt, bytes: original.bytes, sha256: String(repeating: "b", count: 64))
    XCTAssertNil(GalaxySSIHealthRecordCenterSnapshot(archive: archive, originals: [replaced]).pending.first?.original)
    var removed = confirmed
    removed.revision += 1
    removed.deleted = true
    archive.revisions.append(removed)
    XCTAssertTrue(GalaxySSIHealthRecordCenterSnapshot(archive: archive, originals: [original]).confirmed.isEmpty)
  }
  func testHealthKitPreviewBindsSourceMetadataAndRowMultiplicity() {
    let now = Date()
    let source = GalaxySSIHealthKitImport.Source(key: "sample", origin: "fixture", name: "Original")
    let original = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 65, healthKitSource: source)
    let another = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 66, healthKitSource: source)
    var renamed = original
    renamed.healthKitSource = .init(key: source.key, origin: source.origin, name: "Updated")
    var reread = original
    reread.id = UUID()
    let stamp = GalaxySSIHealthKitImport.stamp
    XCTAssertEqual(stamp([original, another]), stamp([another, reread]))
    XCTAssertNotEqual(stamp([original]), stamp([renamed]))
    XCTAssertNotEqual(stamp([original]), stamp([original, original]))
  }

  @MainActor
  func testHealthKitImportKeepsOriginsEditsAndTombstones() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let now = Date()
    let first = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 65,
      healthKitSource: .init(key: String(repeating: "a", count: 64), origin: "fixture.a", name: "A"))
    let second = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 65,
      healthKitSource: .init(key: String(repeating: "b", count: 64), origin: "fixture.b", name: "B"))
    XCTAssertThrowsError(try records.importHealthKit([first, .init(metric: .weight, value: 60)]))
    XCTAssertTrue(try records.load().current.isEmpty)
    XCTAssertEqual(try records.importHealthKit([first, second]), 2)
    var edited = try XCTUnwrap(records.load().current.first { $0.id == first.id })
    edited.value = 67
    try records.write(edited)
    var removed = try XCTUnwrap(records.load().current.first { $0.id == second.id })
    removed.deleted = true
    try records.write(removed)
    XCTAssertEqual(try records.importHealthKit([first, second]), 0)
    XCTAssertEqual(try records.load().current.map(\.value), [67])
  }

  func testSleepReminderCoverageNormalizationAndRevocation() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10)))
    let readings = try (1...21).filter { $0 != 2 && $0 != 8 }.map { offset in
      let date = try XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: now))
      return GalaxySSIHealthReading(revision: 1, metric: .sleepDuration, measuredAt: date,
        value: offset <= 7 ? 435 : 8, unitOverride: offset <= 7 ? "min" : "h")
    }
    var ledger = GalaxySSIHealthSleepReminder.Ledger()
    ledger.preferences.enabled = true
    ledger.reconcile(current: readings, allowed: true, now: now, calendar: calendar)
    let episode = try XCTUnwrap(ledger.episodes.first)
    XCTAssertEqual(episode.latest.decrease, 45)
    XCTAssertEqual(episode.latest.days.filter { $0.minutes == nil }.count, 2)
    ledger.reconcile(current: readings, allowed: true, now: now.addingTimeInterval(60), calendar: calendar)
    XCTAssertEqual(ledger.episodes, [episode])
    ledger.reconcile(current: Array(readings.dropFirst(2)), allowed: true, now: now, calendar: calendar)
    XCTAssertEqual(ledger.episodes.first?.closed, true)
    ledger.reconcile(current: readings, allowed: false, now: now, calendar: calendar)
    XCTAssertFalse(ledger.episodes.contains { !$0.closed })
  }

  @MainActor
  func testReportReviewBatchIsAtomicAndVersionPinned() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let original = GalaxySSIHealthOriginalStore.Original(id: UUID(), name: "report.pdf", kind: .pdf,
      fileExtension: "pdf", importedAt: Date(), bytes: 1, sha256: String(repeating: "a", count: 64))
    let date = Date()
    func item(_ page: Int, value: Decimal) -> GalaxySSIHealthReportReview.Item {
      let source = GalaxySSIHealthReportReview.Source(original: original.id, sha256: original.sha256,
        page: page, region: 0, fromOCR: true)
      return .init(version: UUID(), source: source, excerpt: "Fixture",
        reading: .init(metric: .weight, measuredAt: date, value: value, reportSource: source))
    }
    let first = item(0, value: 61)
    let second = item(1, value: 62)
    try records.stageReportItem(first, replacing: nil)
    try records.stageReportItem(second, replacing: nil)
    let updated = item(1, value: 63)
    try records.stageReportItem(updated, replacing: second.version)
    XCTAssertThrowsError(try records.confirmReportItems([first.version, second.version], original: original))
    try records.write(.init(metric: .weight, measuredAt: date, value: 63))
    XCTAssertThrowsError(try records.confirmReportItems([first.version, updated.version], original: original))
    XCTAssertEqual(try records.load().current.count, 1)
    XCTAssertEqual(try records.load().reportReview?.count, 2)
    try records.confirmReportItems([first.version], original: original)
    XCTAssertEqual(try records.load().current.count, 2)
    XCTAssertEqual(try records.load().reportReview?.map(\.version), [updated.version])
  }

  @MainActor
  func testMetricDeletionIncludesSoftDeletedHistoryAndKeepsOtherMetricsAndOriginals() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: root.appendingPathComponent("records"))
    let originals = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: root)
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try originals.store(pdf, name: "fixture.pdf")
    let original = try XCTUnwrap(originals.list().originals.first)
    let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-01-01T12:00:00Z"))
    let manual = GalaxySSIHealthReading(metric: .weight, measuredAt: date, value: 60)
    try records.write(manual)
    let table = Data("value,time\n60,2025-01-01T12:00:00Z\n".utf8)
    let mapping = GalaxySSIHealthTableImport.Mapping(metric: .weight, value: 0, date: 1, confirmedUnit: true)
    let parsed = try GalaxySSIHealthTableImport.parse(table, json: false)
    let rows = try GalaxySSIHealthTableImport.preview(parsed, mapping: mapping, current: records.load().current)
    let row = try XCTUnwrap(rows.first)
    let target = try XCTUnwrap(row.duplicateTarget)
    XCTAssertEqual(try records.importTable(table, name: "fixture.csv", json: false, mapping: mapping,
                                           expected: [.duplicate], linkDuplicates: [row.id: target]), 0)
    var tombstone = try XCTUnwrap(records.load().current.first)
    tombstone.deleted = true
    try records.write(tombstone, rememberDeletion: true)
    let apple = GalaxySSIHealthReading(metric: .weight, measuredAt: date.addingTimeInterval(100), value: 61,
      healthKitSource: .init(key: String(repeating: "a", count: 64), origin: "fixture", name: nil))
    XCTAssertEqual(try records.importHealthKit([apple]), 1)
    func report(_ metric: GalaxySSIHealthMetric, region: Int) -> GalaxySSIHealthReportReview.Item {
      let source = GalaxySSIHealthReportReview.Source(original: original.id, sha256: original.sha256,
        page: 0, region: region, fromOCR: true)
      return .init(version: UUID(), source: source, excerpt: "Fixture",
        reading: .init(metric: metric, measuredAt: date, value: 65, reportSource: source))
    }
    let reviewed = report(.weight, region: 0)
    let staged = report(.weight, region: 1)
    let otherStaged = report(.heartRate, region: 2)
    try records.stageReportItem(reviewed, replacing: nil)
    try records.confirmReportItems([reviewed.version], original: original)
    try records.stageReportItem(staged, replacing: nil)
    try records.stageReportItem(otherStaged, replacing: nil)
    try records.storeDraft(.init(metric: .weight))
    try records.setHealthOnlinePermission(true)
    let other = GalaxySSIHealthReading(metric: .heartRate, measuredAt: date, value: 70)
    try records.write(other)

    let preview = try records.previewMetricDeletion(.weight)
    XCTAssertEqual(preview.scope.sources, [.manual: 1, .appleHealth: 1, .report: 1])
    XCTAssertEqual(preview.scope.earliest, date)
    XCTAssertEqual(preview.scope.latest, apple.measuredAt)
    XCTAssertEqual(preview.scope.drafts, 2)
    try records.deleteMetricHistory(preview)

    let archive = try records.load()
    XCTAssertEqual(archive.current.map(\.id), [other.id])
    XCTAssertEqual(archive.revisions.map(\.id), [other.id])
    XCTAssertNil(archive.draft)
    XCTAssertNil(archive.lastMeasurementDeletion)
    XCTAssertEqual(archive.reportReview?.map(\.version), [otherStaged.version])
    XCTAssertEqual(archive.tableEvidence?.count, 0)
    XCTAssertEqual(archive.tableBatches?.first?.data, table)
    XCTAssertEqual(try originals.read(original), pdf)
    XCTAssertNotNil(archive.healthOnlinePermission)
    XCTAssertEqual(archive.metricDeletionHistory?.first?.scope, preview.scope)
    XCTAssertEqual(try records.importHealthKit([apple]), 1)
  }

  @MainActor
  func testMetricDeletionRejectsChangedRevisionWithSamePreviewCounts() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    try records.write(.init(metric: .weight, value: 60))
    let before = try records.previewMetricDeletion(.weight)
    var updated = try XCTUnwrap(records.load().current.first)
    updated.value = 61
    try records.write(updated)
    let after = try records.previewMetricDeletion(.weight)
    XCTAssertEqual(before.scope, after.scope)
    XCTAssertThrowsError(try records.deleteMetricHistory(before)) { error in
      guard case GalaxySSIHealthRecords.Failure.stale = error else { return XCTFail("Expected stale preview") }
    }
    XCTAssertEqual(try records.load().current.first?.value, 61)
    XCTAssertNil(try records.load().metricDeletionHistory)
    try records.storeDraft(.init(metric: .heartRate))
    try records.deleteMetricHistory(after)
    XCTAssertEqual(try records.load().draft?.metric, .heartRate)
    XCTAssertTrue(try records.previewMetricDeletion(.weight).scope.isEmpty)
  }

  @MainActor
  func testAppleHealthLocalEraseKeepsSameMetricFromOtherSourcesAndLeavesPermissionsAlone() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(),
                                         isolatedFile: root.appendingPathComponent("records"))
    let now = Date()
    let packet = try XCTUnwrap(GalaxySSIHealthBluetoothPacket.decode(Data([0, 120, 0, 80, 0, 90, 0])))
    let bluetooth = GalaxySSIHealthBluetoothReceipt(device: UUID(), receivedAt: now, packet: packet)
      .reading(conditions: "")
    let manual = GalaxySSIHealthReading(metric: .bloodPressure, measuredAt: now, value: 120, diastolic: 80)
    let apple = GalaxySSIHealthReading(metric: .bloodPressure, measuredAt: now, value: 120, diastolic: 80,
      healthKitSource: .init(key: String(repeating: "a", count: 64), origin: "fixture", name: nil))
    let otherApple = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 65,
      healthKitSource: .init(key: String(repeating: "b", count: 64), origin: "fixture", name: nil))
    try records.write(bluetooth)
    try records.write(manual, allowDuplicate: true)
    XCTAssertEqual(try records.importHealthKit([apple, otherApple]), 2)
    try records.updateSourceAttention { $0.selected = [.bloodPressure, .weight] }
    let attention = try records.loadSourceAttention()
    let source = GalaxySSIHealthReportReview.Source(original: UUID(), sha256: String(repeating: "c", count: 64),
                                                   page: 0, region: 0, fromOCR: true)
    let report = GalaxySSIHealthReportReview.Item(version: UUID(), source: source, excerpt: "Fixture",
      reading: .init(metric: .bloodPressure, measuredAt: now, value: 121, diastolic: 79, reportSource: source))
    try records.stageReportItem(report, replacing: nil)
    let archivedApple = try XCTUnwrap(records.load().current.first { $0.id == apple.id })
    try records.storeDraft(.init(existing: archivedApple, metric: .bloodPressure))
    let withDraft = try records.previewMetricDeletion(.bloodPressure, filter: .appleHealth)
    XCTAssertEqual(withDraft.scope.drafts, 1)
    XCTAssertEqual(withDraft.scope.sources, [.appleHealth: 1])
    var tombstone = archivedApple
    tombstone.deleted = true
    tombstone.measuredAt = now.addingTimeInterval(-120)
    try records.write(tombstone, rememberDeletion: true)
    XCTAssertThrowsError(try records.deleteMetricHistory(withDraft))

    try records.storeDraft(.init(metric: .bloodPressure))
    let reviewed = try records.previewMetricDeletion(.bloodPressure, filter: .appleHealth)
    XCTAssertEqual(reviewed.scope.count, 1)
    XCTAssertEqual(reviewed.scope.drafts, 0)
    XCTAssertEqual(reviewed.scope.earliest, tombstone.measuredAt)
    XCTAssertEqual(reviewed.scope.latest, now)
    try records.deleteMetricHistory(reviewed)

    let archive = try records.load()
    XCTAssertEqual(Set(archive.current.map(\.id)), Set([manual.id, bluetooth.id, otherApple.id]))
    XCTAssertFalse(archive.revisions.contains { $0.id == apple.id })
    XCTAssertEqual(archive.draft?.metric, .bloodPressure)
    XCTAssertNil(archive.lastMeasurementDeletion)
    XCTAssertEqual(archive.reportReview?.map(\.version), [report.version])
    XCTAssertEqual(archive.metricDeletionHistory?.first?.scope.filter, .appleHealth)
    XCTAssertNil(archive.derivesOverview)
    XCTAssertEqual(try records.loadSourceAttention(), attention)
    XCTAssertEqual(try records.importHealthKit([apple]), 1)
  }

  @MainActor
  func testAppleHealthLocalEraseClearsOnlyDraftLinkedToRemovedCopy() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let copy = GalaxySSIHealthReading(metric: .weight, value: 65,
      healthKitSource: .init(key: String(repeating: "a", count: 64), origin: nil, name: nil))
    XCTAssertEqual(try records.importHealthKit([copy]), 1)
    let saved = try XCTUnwrap(records.load().current.first)
    try records.storeDraft(.init(existing: saved, metric: .weight))
    let reviewed = try records.previewMetricDeletion(.weight, filter: .appleHealth)
    XCTAssertEqual(reviewed.scope.drafts, 1)
    try records.deleteMetricHistory(reviewed)
    XCTAssertNil(try records.load().draft)
    XCTAssertTrue(try records.previewMetricDeletion(.weight, filter: .appleHealth).scope.isEmpty)
  }

  @MainActor
  func testHealthBackupHistoryKeepsVerifiedSaveAfterInterruptionAndPruning() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let history = GalaxySSIHealthBackupHistory(owner: "fixture", secrets: HealthFixtureSecrets(), fixtureDirectory: root)
    let id = try history.begin()
    let data = Data("synthetic sealed package".utf8)
    try history.publish(data, id: id)
    let first = try history.beginSave(id)
    let destination = root.appendingPathComponent("external")
    try data.write(to: destination)
    XCTAssertTrue(try GalaxySSIHealthBackupHistory.verifyDestination(destination, entry: first))
    try history.finishSave(id, verified: true)
    let saved = try XCTUnwrap(history.entries().first?.lastVerifiedAt)
    _ = try history.beginSave(id)
    let interrupted = try history.begin()
    try history.recover()
    let recovered = try history.entries()
    XCTAssertEqual(recovered.first { $0.id == interrupted }?.generation, .interrupted)
    XCTAssertEqual(recovered.first { $0.id == id }?.latestSave, .interrupted)
    for _ in 0..<2 { try history.publish(data, id: history.begin()) }
    let old = try XCTUnwrap(history.entries().first { $0.id == id })
    XCTAssertEqual(old.lastVerifiedAt, saved)
    XCTAssertFalse(history.hasCopy(old))
    XCTAssertThrowsError(try history.readCopy(old))
  }

  @MainActor
  func testProtectedHealthPDFRetainsExactBytesAndEnforcesExtractionPermission() throws {
    let bytes = NSMutableData()
    let consumer = try XCTUnwrap(CGDataConsumer(data: bytes as CFMutableData))
    let options: [String: Any] = [
      kCGPDFContextUserPassword as String: "fixture-reader",
      kCGPDFContextOwnerPassword as String: "fixture-owner",
      kCGPDFContextAllowsCopying as String: false
    ]
    var bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
    let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &bounds, options as CFDictionary))
    context.beginPDFPage(nil)
    context.endPDFPage()
    context.closePDF()
    let pdf = bytes as Data
    XCTAssertThrowsError(try GalaxySSIHealthPDFText.pageCount(pdf)) {
      guard case GalaxySSIHealthPDFText.Failure.locked = $0 else { return XCTFail("Expected locked PDF") }
    }
    XCTAssertThrowsError(try GalaxySSIHealthPDFText.pageCount(pdf, password: "wrong")) {
      guard case GalaxySSIHealthPDFText.Failure.incorrectPassword = $0 else { return XCTFail("Expected wrong password") }
    }
    XCTAssertEqual(try GalaxySSIHealthPDFText.pageCount(pdf, password: "fixture-reader"), 1)
    XCTAssertThrowsError(try GalaxySSIHealthPDFText.read(pdf, page: 0, password: "fixture-reader")) {
      guard case GalaxySSIHealthPDFText.Failure.extractionRestricted = $0 else { return XCTFail("Expected restricted extraction") }
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: HealthFixtureSecrets(), fixtureDirectory: root)
    try store.store(pdf, name: "protected.pdf")
    let original = try XCTUnwrap(store.list().originals.first)
    XCTAssertEqual(try store.read(original), pdf)
  }

  @MainActor
  func testDailyHealthReminderDoesNotBackfillAndRejectsStaleActions() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12)))
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    var settings = try records.loadRecordingReminders(at: now, calendar: calendar).settings
    settings.enabled = true
    settings.notifications = true
    try records.saveRecordingReminderSettings(settings, at: now)
    XCTAssertTrue(try records.loadRecordingReminders(at: now, calendar: calendar).history.isEmpty)
    let later = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: now))
    let ledger = try records.loadRecordingReminders(at: later, calendar: calendar)
    let first = try XCTUnwrap(ledger.history.first)
    XCTAssertEqual(ledger.history.count, 1)
    try records.updateRecordingReminder(first, complete: false, at: later, calendar: calendar)
    XCTAssertThrowsError(try records.updateRecordingReminder(first, complete: true, at: later, calendar: calendar))
    let refreshed = try records.loadRecordingReminders(at: later, calendar: calendar)
    XCTAssertEqual(refreshed.history.first?.snoozedUntil, later.addingTimeInterval(3_600))
    XCTAssertEqual(refreshed.upcoming(at: later, calendar: calendar).first?.1, later.addingTimeInterval(3_600))
    let snoozed = try XCTUnwrap(refreshed.history.first)
    try records.updateRecordingReminder(snoozed, complete: true, at: later, calendar: calendar)
    XCTAssertNotEqual(try records.loadRecordingReminders(at: later, calendar: calendar)
      .upcoming(at: later, calendar: calendar).first?.0, snoozed.day)
  }

  @MainActor
  func testExactTableDuplicateLinksToReviewedRevisionWithoutRewritingMeasurement() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-01-01T12:00:00Z"))
    try records.write(.init(metric: .weight, measuredAt: date, value: 60))
    let data = Data("value,time\n60,2025-01-01T12:00:00Z\n60,2025-01-01T12:00:10Z\n".utf8)
    let mapping = GalaxySSIHealthTableImport.Mapping(metric: .weight, value: 0, date: 1, confirmedUnit: true)
    let table = try GalaxySSIHealthTableImport.parse(data, json: false)
    let rows = try GalaxySSIHealthTableImport.preview(table, mapping: mapping, current: records.load().current)
    XCTAssertEqual(rows.map(\.status), [.duplicate, .duplicate])
    let target = try XCTUnwrap(rows[0].duplicateTarget)
    XCTAssertNil(rows[1].duplicateTarget)
    XCTAssertEqual(try records.importTable(data, name: "fixture.csv", json: false, mapping: mapping,
      expected: rows.map(\.status), linkDuplicates: [rows[0].id: target]), 0)
    var archive = try records.load()
    XCTAssertEqual(archive.revisions.count, 1)
    let batch = try XCTUnwrap(archive.tableBatches?.first)
    XCTAssertEqual(batch.linked, 1)
    var edited = try XCTUnwrap(archive.current.first)
    edited.notes = "later edit"
    try records.write(edited)
    XCTAssertThrowsError(try records.importTable(data, name: "fixture.csv", json: false, mapping: mapping,
      expected: rows.map(\.status), linkDuplicates: [rows[0].id: target]))
    archive = try records.load()
    let linked = GalaxySSIHealthTableImport.linkedReadings(batch: batch, revisions: archive.revisions,
      current: archive.current, evidence: archive.tableEvidence ?? [])
    XCTAssertEqual(linked.first?.reading.revision, 1)
    XCTAssertTrue(linked.first?.secondary == true)
    let zip = try GalaxySSIHealthTableImport.exportLinkedReadings(linked, batch: batch)
    XCTAssertNotNil(zip.range(of: data))
    XCTAssertEqual(try records.undoTableBatch(batch.id), 0)
    XCTAssertTrue(try records.load().tableEvidence?.isEmpty == true)
    XCTAssertEqual(try records.load().current.first?.notes, "later edit")
  }

  @MainActor
  func testUndoMeasurementRestoresExactSourceAndRejectsConflictsAndStaleVersions() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let data = Data("value,time\n60,2025-01-01T12:00:00Z\n".utf8)
    let mapping = GalaxySSIHealthTableImport.Mapping(metric: .weight, value: 0, date: 1, confirmedUnit: true)
    XCTAssertEqual(try records.importTable(data, name: "weight.csv", json: false, mapping: mapping,
                                           expected: [.ready]), 1)
    let original = try XCTUnwrap(records.load().current.first)
    let oldEditor = GalaxySSIHealthDraft(existing: original)
    try records.storeDraft(oldEditor)
    var tombstone = original
    tombstone.deleted = true
    try records.write(tombstone, rememberDeletion: true)
    let reopened = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let deletion = try XCTUnwrap(reopened.load().lastMeasurementDeletion)
    XCTAssertEqual(deletion.revision, 2)
    XCTAssertTrue(try reopened.load().current.isEmpty)
    XCTAssertNil(try reopened.load().draft)
    XCTAssertThrowsError(try reopened.storeDraft(oldEditor)) {
      guard case GalaxySSIHealthRecords.Failure.stale = $0 else { return XCTFail("Expected stale editor") }
    }
    XCTAssertThrowsError(try reopened.undoMeasurementDeletion(.init(id: UUID(), revision: 2)))
    let conflict = GalaxySSIHealthReading(metric: .weight, measuredAt: original.measuredAt, value: 60)
    try reopened.write(conflict)
    XCTAssertThrowsError(try reopened.undoMeasurementDeletion(deletion))
    XCTAssertEqual(try reopened.load().lastMeasurementDeletion, deletion)
    var removeConflict = try XCTUnwrap(reopened.load().current.first)
    removeConflict.deleted = true
    try reopened.write(removeConflict)
    let restored = try reopened.undoMeasurementDeletion(deletion)
    XCTAssertEqual(restored.id, original.id)
    XCTAssertEqual(restored.revision, 3)
    XCTAssertEqual(restored.tableSource, original.tableSource)
    XCTAssertThrowsError(try reopened.storeDraft(oldEditor))
    try reopened.storeDraft(.init(existing: restored))
    XCTAssertEqual(try reopened.load().draft?.existing?.revision, 3)
    XCTAssertNil(try reopened.load().lastMeasurementDeletion)
    XCTAssertThrowsError(try reopened.undoMeasurementDeletion(deletion))
  }

  func testSavedBluetoothHistoryKeepsExactDeviceAndBothDates() throws {
    let packet = try XCTUnwrap(GalaxySSIHealthBluetoothPacket.decode(Data([0, 120, 0, 80, 0, 90, 0])))
    let now = Date()
    let sameName = (0..<34).map { index -> GalaxySSIHealthReading in
      let receipt = GalaxySSIHealthBluetoothReceipt(device: UUID(), receivedAt: now.addingTimeInterval(Double(index)),
        packet: packet, deviceName: "Same monitor")
      var reading = receipt.reading(conditions: "")
      reading.measuredAt = now.addingTimeInterval(Double(-index - 60))
      return reading
    }
    var tombstone = sameName[0]
    tombstone.id = UUID()
    tombstone.deleted = true
    let history = GalaxySSIHealthBluetoothHistory(current: sameName + [tombstone,
      .init(metric: .bloodPressure, value: 120, diastolic: 80)])
    XCTAssertEqual(history.devices.count, 34)
    XCTAssertEqual(history.devices.dropFirst(30).count, 4)
    let device = try XCTUnwrap(history.devices.first)
    XCTAssertEqual(device.name, "Same monitor")
    XCTAssertEqual(history.readings(for: device.id).map(\.id), [sameName[0].id])
    XCTAssertEqual(device.latest.measuredAt, now.addingTimeInterval(-60))
    XCTAssertEqual(device.latest.bluetoothReceipt?.receivedAt, now)
    XCTAssertEqual(Set(history.devices.map(\.ordinal)).count, 34)
  }

  @MainActor
  func testSavedBluetoothHistoryTracksPrivacyAndOrdersOnlySelectedDeviceRecords() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let packet = try XCTUnwrap(GalaxySSIHealthBluetoothPacket.decode(Data([0, 120, 0, 80, 0, 90, 0])))
    let now = Date()
    let id = UUID()
    let newest = GalaxySSIHealthBluetoothReceipt(device: id, receivedAt: now, packet: packet, deviceName: " ")
      .reading(conditions: "")
    let older = GalaxySSIHealthBluetoothReceipt(device: id, receivedAt: now.addingTimeInterval(-90),
                                                 packet: packet, deviceName: "Monitor")
      .reading(conditions: "")
    let other = GalaxySSIHealthBluetoothReceipt(device: UUID(), receivedAt: now, packet: packet, deviceName: "Monitor")
      .reading(conditions: "")
    try records.write(newest)
    try records.write(older)
    try records.write(other)
    XCTAssertNil(try GalaxySSIHealthBluetoothHistory(visibleArchive: records.load()))
    try records.setOverviewPermission(true)
    let history = try XCTUnwrap(GalaxySSIHealthBluetoothHistory(visibleArchive: records.load()))
    XCTAssertEqual(history.devices.first { $0.id == id }?.name, "Monitor")
    XCTAssertEqual(history.readings(for: id).map(\.id), [newest.id, older.id])
    XCTAssertEqual(history.readings(for: UUID()).count, 0)
    try records.setOverviewPermission(false)
    XCTAssertNil(try GalaxySSIHealthBluetoothHistory(visibleArchive: records.load()))
    XCTAssertEqual(try records.load().current.count, 3)
  }

  @MainActor
  func testHealthBackupAuthenticatesOriginalsAndLeavesLocalRecordsUntouched() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets,
                                         isolatedFile: root.appendingPathComponent("measurements"))
    let originals = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: root)
    let oldPlan = try GalaxySSIHealthPortableBackup.plan(records: records, originals: originals)
    try records.write(.init(metric: .weight, value: 65, notes: "private backup fixture marker"))
    XCTAssertThrowsError(try GalaxySSIHealthPortableBackup.prepare(oldPlan, records: records, originals: originals))
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try originals.store(pdf, name: "fixture.pdf")
    let plan = try GalaxySSIHealthPortableBackup.plan(records: records, originals: originals)
    let (payload, expected) = try GalaxySSIHealthPortableBackup.prepare(plan, records: records, originals: originals)
    let sealed = try GalaxySSIHealthPortableBackup.seal(payload, password: "fixture-password")
    XCTAssertNil(sealed.range(of: Data("private backup fixture marker".utf8)))
    XCTAssertEqual(try GalaxySSIHealthPortableBackup.verify(sealed, password: "fixture-password"), expected)
    XCTAssertEqual(expected.readings, 1)
    XCTAssertEqual(expected.originals, 1)
    XCTAssertEqual(expected.missing, 0)
    XCTAssertThrowsError(try GalaxySSIHealthPortableBackup.verify(sealed + Data([1]), password: "fixture-password"))
    XCTAssertEqual(try records.load().current.count, 1)
  }

  @MainActor
  func testHealthBluetoothSameNameAndEqualValuesStaySeparated() throws {
    let bytes = Data([30, 120, 0, 80, 0, 90, 0, 234, 7, 11, 5, 12, 30, 0, 64, 0, 2, 1, 0])
    let packet = try XCTUnwrap(GalaxySSIHealthBluetoothPacket.decode(bytes))
    let now = Date()
    let a = GalaxySSIHealthBluetoothReceipt(device: UUID(), receivedAt: now, packet: packet, deviceName: "Monitor")
    let b = GalaxySSIHealthBluetoothReceipt(device: UUID(), receivedAt: now, packet: packet, deviceName: "Monitor")
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    try records.write(a.reading(conditions: ""))
    try records.write(b.reading(conditions: ""))
    let saved = try records.load().current
    XCTAssertEqual(saved.count, 2)
    XCTAssertEqual(GalaxySSIHealthTrendDevice.options(in: saved, metric: .bloodPressure).count, 2)
    let selected = GalaxySSIHealthTrendDevice.matching(saved, device: a.device)
    XCTAssertEqual(selected.map { $0.bluetoothReceipt?.device }, [a.device])
    let trend = GalaxySSIHealthTrend(current: selected, metric: .bloodPressure, component: .value,
                                    now: now, dayCount: 7, calendar: .current)
    XCTAssertEqual(trend.points.last?.readings.count, 1)
    let export = try GalaxySSIHealthMeasurementExport.encode(saved, as: .json, includeNotes: false)
    XCTAssertNil(export.range(of: Data(a.device.uuidString.utf8)))
    XCTAssertNil(export.range(of: Data("Monitor".utf8)))
  }

  @MainActor
  func testHealthRestoreRetainsTombstonesAndPublishesExactOriginalWithReceipt() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let source = root.appendingPathComponent("source")
    let target = root.appendingPathComponent("target")
    for directory in [source, target] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: source.appendingPathComponent("records"))
    let originals = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: source)
    let destination = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: target.appendingPathComponent("records"))
    let files = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: target,
                                             restoreRecordsFile: destination.isolatedFile)
    let deleted = GalaxySSIHealthReading(metric: .weight, value: 65)
    try records.write(deleted)
    try records.write(.init(metric: .glucose, value: 6))
    try destination.write(deleted)
    var tombstone = try XCTUnwrap(destination.load().current.first)
    tombstone.deleted = true
    try destination.write(tombstone)
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try originals.store(pdf, name: "fixture.pdf")
    let manifest = try XCTUnwrap(originals.list().originals.first)
    try files.stageRestore([(manifest, pdf)], receipt: UUID())
    XCTAssertTrue(try files.list().originals.isEmpty)
    let plan = try GalaxySSIHealthPortableBackup.plan(records: records, originals: originals)
    let (payload, _) = try GalaxySSIHealthPortableBackup.prepare(plan, records: records, originals: originals)
    let sealed = try GalaxySSIHealthPortableBackup.seal(payload, password: "fixture-password")
    let input = try GalaxySSIHealthPortableBackup.unlock(sealed, password: "fixture-password")
    let preview = try GalaxySSIHealthPortableBackup.previewRestore(input, records: destination, originals: files)
    XCTAssertEqual(preview.readings, 1)
    XCTAssertEqual(preview.conflicts.map(\.id), [deleted.id])
    try destination.write(.init(metric: .steps, value: 12))
    XCTAssertThrowsError(try GalaxySSIHealthPortableBackup.restore(input, expected: preview, records: destination, originals: files))
    let fresh = try GalaxySSIHealthPortableBackup.previewRestore(input, records: destination, originals: files)
    try GalaxySSIHealthPortableBackup.restore(input, expected: fresh, records: destination, originals: files)
    XCTAssertEqual(try destination.load().restoreReceipts?.count, 1)
    XCTAssertFalse(try destination.load().current.contains { $0.id == deleted.id })
    XCTAssertEqual(try files.read(manifest), pdf)
    XCTAssertFalse(try GalaxySSIHealthPortableBackup.previewRestore(input, records: destination, originals: files).hasChanges)
    let foreign = GalaxySSIHealthRecords(owner: "different", secrets: secrets, isolatedFile: destination.isolatedFile)
    XCTAssertThrowsError(try GalaxySSIHealthPortableBackup.previewRestore(input, records: foreign, originals: files))
    try files.remove(files.previewRemoval(manifest))
    let pendingReceipt = UUID()
    try files.stageRestore([(manifest, pdf)], receipt: pendingReceipt)
    try destination.commitRestore(destination.load(), receipt: pendingReceipt)
    XCTAssertEqual(try files.list().originals, [manifest])
    XCTAssertEqual(try files.read(manifest), pdf)
  }

  func testMeasurementExportKeepsComponentsAndProtectsCSVFormulas() throws {
    var reading = GalaxySSIHealthReading(metric: .bloodPressure, value: 120, diastolic: 80, pulse: 65)
    reading.conditions = " =2+2"
    reading.notes = "a\r\nb\nc\rd,\"quoted\""
    let csv = String(decoding: try GalaxySSIHealthMeasurementExport.encode([reading], as: .csv, includeNotes: true),
                     as: UTF8.self)
    XCTAssertTrue(csv.contains("\"120\",\"mmHg\",\"80\",\"65\""))
    XCTAssertTrue(csv.contains("\"' =2+2\""))
    XCTAssertTrue(csv.contains("\"a\r\nb\nc\rd,\"\"quoted\"\"\""))
    let json = try GalaxySSIHealthMeasurementExport.encode([reading], as: .json, includeNotes: false)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
    let row = try XCTUnwrap((object["measurements"] as? [[String: String]])?.first)
    XCTAssertEqual(row["diastolic"], "80")
    XCTAssertNil(row["conditions"])
    XCTAssertNil(row["notes"])
  }

  func testMeasurementXLSXUsesLiteralTextAndPreservesExactNotation() throws {
    var reading = GalaxySSIHealthReading(metric: .weight, value: try XCTUnwrap(Decimal(string: "60.123456789012345678")))
    reading.notes = "=2+2\r\n<&> _x000D_\u{0000}"
    let data = try GalaxySSIHealthMeasurementExport.encode([reading], as: .xlsx, includeNotes: true)
    let workbook = try GalaxySSIHealthXLSX(data)
    let sheet = try XCTUnwrap(workbook.sheets.first)
    let rows = try workbook.rows(sheet.id)
    XCTAssertTrue(try XCTUnwrap(rows.last).formulas.isEmpty)
    let table = try workbook.table(.init(sheet: sheet.id, header: 1))
    XCTAssertEqual(table.rows.first?[4], "60.123456789012345678")
    XCTAssertEqual(table.rows.first?[9], reading.notes)
    let withoutNotes = try GalaxySSIHealthMeasurementExport.encode([reading], as: .xlsx, includeNotes: false)
    let privateWorkbook = try GalaxySSIHealthXLSX(withoutNotes)
    let privateSheet = try XCTUnwrap(privateWorkbook.sheets.first)
    XCTAssertFalse(try privateWorkbook.table(.init(sheet: privateSheet.id, header: 1)).headers.contains("notes"))
  }

  @MainActor
  func testProfileIsSeparateAndStaleDraftCannotRestoreClearedFacts() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let profileFile = file.appendingPathExtension("profile")
    defer {
      try? FileManager.default.removeItem(at: file)
      try? FileManager.default.removeItem(at: profileFile)
    }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    try records.write(.init(metric: .weight, value: 65))
    var profile = try records.loadProfile()
    profile.name = "private profile marker"
    profile.background = [.init(kind: .allergy, title: "fixture", notes: "")]
    try records.writeProfile(profile)
    XCTAssertNil(String(decoding: try Data(contentsOf: profileFile), as: UTF8.self).range(of: profile.name))
    let stale = try records.loadProfile()
    XCTAssertEqual(stale.background.count, 1)
    var cleared = GalaxySSIHealthProfile()
    cleared.revision = stale.revision
    try records.writeProfile(cleared)
    XCTAssertThrowsError(try records.writeProfile(stale))
    XCTAssertTrue(try records.loadProfile().name.isEmpty)
    XCTAssertTrue(try records.loadProfile().background.isEmpty)
    XCTAssertEqual(try records.load().current.count, 1)
  }

  @MainActor
  func testPrivacyEventsRecordOnlyEffectiveScopedChanges() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    try records.setOverviewPermission(false)
    try records.setOverviewPermission(true)
    try records.setOverviewPermission(true)
    try records.setWeeklyReportAllowed(true)
    try records.setOverviewPermission(false)
    let archive = try records.load()
    let history = try XCTUnwrap(archive.privacyEvents)
    XCTAssertEqual(history.map(\.scope), [.overview, .weeklyReport, .overview])
    XCTAssertEqual(history.map(\.enabled), [true, true, false])
    XCTAssertEqual(archive.derivesOverview, false)
    XCTAssertEqual(archive.weeklyReportAllowed, true)
    XCTAssertNil(String(decoding: try Data(contentsOf: file), as: UTF8.self).range(of: "privacyEvents"))
  }

  @MainActor
  func testImportOriginalRetentionIsEncryptedAndIndependentOfOnlineConsent() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    XCTAssertTrue(try records.load().keepsNewImportOriginals)
    try records.setHealthOnlinePermission(true)
    let onlinePermission = try XCTUnwrap(records.load().healthOnlinePermission)
    try records.setPrivacy(.importOriginals, enabled: true)
    XCTAssertNil(try records.load().privacyEvents)
    try records.setPrivacy(.importOriginals, enabled: false)
    try records.setPrivacy(.importOriginals, enabled: false)
    let reopened = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let archive = try reopened.load()
    XCTAssertFalse(archive.keepsNewImportOriginals)
    XCTAssertEqual(archive.healthOnlinePermission, onlinePermission)
    XCTAssertEqual(archive.privacyEvents?.map(\.scope), [.importOriginals])
    XCTAssertEqual(archive.privacyEvents?.map(\.enabled), [false])
    XCTAssertNil(String(decoding: try Data(contentsOf: file), as: UTF8.self).range(of: "retainImportOriginals"))
  }

  func testImportRetentionChoiceDoesNotFallBackWhenPolicyIsUnavailable() {
    XCTAssertEqual(GalaxySSIHealthImportRetentionChoice.useDefault.resolve(default: false), false)
    XCTAssertEqual(GalaxySSIHealthImportRetentionChoice.useDefault.resolve(default: true), true)
    XCTAssertEqual(GalaxySSIHealthImportRetentionChoice.keep.resolve(default: false), true)
    XCTAssertEqual(GalaxySSIHealthImportRetentionChoice.reviewOnly.resolve(default: true), false)
    for choice in [GalaxySSIHealthImportRetentionChoice.useDefault, .keep, .reviewOnly] {
      XCTAssertNil(choice.resolve(default: nil))
    }
  }

  func testOverviewUsesConfirmedLatestReadingsAndLocalDayBoundary() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)))
    let boundary = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 4)))
    let weight = GalaxySSIHealthReading(metric: .weight, measuredAt: boundary, value: 65)
    let older = GalaxySSIHealthReading(metric: .weight, measuredAt: boundary.addingTimeInterval(-1), value: 60)
    let stale = GalaxySSIHealthReading(metric: .heartRate, measuredAt: boundary.addingTimeInterval(-1), value: 65)
    let future = GalaxySSIHealthReading(metric: .weight, measuredAt: now.addingTimeInterval(1), value: 90)
    let deleted = GalaxySSIHealthReading(metric: .glucose, measuredAt: now, value: 5, deleted: true)
    let overview = GalaxySSIHealthOverview(current: [older, weight, stale, future, deleted],
                                          now: now, calendar: calendar)
    XCTAssertEqual(overview.recentCount, 1)
    XCTAssertEqual(overview.metrics.first { $0.metric == .weight }?.reading?.id, weight.id)
    XCTAssertEqual(overview.metrics.first { $0.metric == .heartRate }?.freshness, .stale)
    XCTAssertEqual(overview.metrics.first { $0.metric == .glucose }?.freshness, .missing)
  }

  @MainActor
  func testOverviewPermissionIsOptInAndSurvivesReopening() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    XCTAssertNil(try records.load().derivesOverview)
    try records.setOverviewPermission(true)
    let reopened = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    XCTAssertEqual(try reopened.load().derivesOverview, true)
    try reopened.setOverviewPermission(false)
    XCTAssertEqual(try records.load().derivesOverview, false)
  }

  @MainActor
  func testWeeklyExportRequiresPermissionAndUnchangedSelectedRevisions() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let now = Date()
    try records.write(.init(metric: .weight, measuredAt: now, value: 65))
    let preview = GalaxySSIWeeklyHealthReport(current: try records.load().current,
      interval: DateInterval(start: now.addingTimeInterval(-60), duration: 120), metrics: [.weight], through: now)
    XCTAssertThrowsError(try records.prepareWeeklyExport(preview, includeRows: false))
    try records.setWeeklyReportAllowed(true)
    try records.write(.init(metric: .glucose, measuredAt: now, value: 5))
    try records.prepareWeeklyExport(preview, includeRows: false)
    var weight = try XCTUnwrap(preview.readings.first)
    weight.value = 64
    try records.write(weight)
    XCTAssertThrowsError(try records.prepareWeeklyExport(preview, includeRows: true))
    XCTAssertEqual(try records.load().weeklyExportRequests?.count, 1)
  }

  @MainActor
  func testPartialDraftIsEncryptedAndClearedOnlyByMatchingCommit() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    var draft = GalaxySSIHealthDraft()
    draft.value = "120."
    draft.notes = "private partial fixture marker"
    try records.storeDraft(draft)
    XCTAssertNil(String(decoding: try Data(contentsOf: file), as: UTF8.self).range(of: draft.notes))
    XCTAssertEqual(try records.load().draft?.value, "120.")
    try records.discardDraft(id: UUID())
    XCTAssertEqual(try records.load().draft?.id, draft.id)
    let invalid = GalaxySSIHealthReading(metric: .bloodPressure, value: 120)
    XCTAssertThrowsError(try records.write(invalid, draftId: draft.id))
    XCTAssertEqual(try records.load().draft?.id, draft.id)
    try records.write(GalaxySSIHealthReading(metric: .bloodPressure, value: 120, diastolic: 80),
                      draftId: draft.id)
    XCTAssertNil(try records.load().draft)
    XCTAssertEqual(try records.load().current.count, 1)
  }

  @MainActor
  func testDuplicateRevisionDeletionAndCorruption() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    var reading = GalaxySSIHealthReading(metric: .bloodPressure, value: 120, diastolic: 80)
    reading.notes = "private fixture marker"
    XCTAssertTrue(try records.load().current.isEmpty)
    try records.write(reading)
    XCTAssertNil(String(decoding: try Data(contentsOf: file), as: UTF8.self).range(of: reading.notes))
    XCTAssertThrowsError(try records.write(reading)) { error in
      guard case GalaxySSIHealthRecords.Failure.stale = error else { return XCTFail("\(error)") }
    }
    var duplicate = reading
    duplicate.id = UUID()
    XCTAssertThrowsError(try records.write(duplicate)) { error in
      guard case GalaxySSIHealthRecords.Failure.duplicate = error else { return XCTFail("\(error)") }
    }
    try records.write(duplicate, allowDuplicate: true)
    reading = try XCTUnwrap(records.load().current.first { $0.id == reading.id })
    reading.deleted = true
    try records.write(reading)
    XCTAssertEqual(try records.load().current.map(\.id), [duplicate.id])
    XCTAssertEqual(try records.load().revisions.count, 3)
    let otherOwner = GalaxySSIHealthRecords(owner: "other", secrets: secrets, isolatedFile: file)
    XCTAssertThrowsError(try otherOwner.load())
    try Data([1, 2, 3]).write(to: file)
    XCTAssertThrowsError(try records.write(duplicate))
    XCTAssertEqual(try Data(contentsOf: file), Data([1, 2, 3]))
  }

  @MainActor
  func testBluetoothPressureDecodesOptionalFieldsAndDoesNotResurrectDeletedReading() throws {
    let bytes = Data([30, 120, 0, 80, 0, 90, 0, 234, 7, 11, 5, 12, 30, 0, 64, 0, 2, 1, 0])
    let packet = try XCTUnwrap(GalaxySSIHealthBluetoothPacket.decode(bytes))
    XCTAssertEqual(packet.deviceClock, "2026-11-05 12:30:00")
    XCTAssertEqual(packet.slot, 2)
    XCTAssertEqual(packet.status, 1)
    XCTAssertEqual(packet.pulse, 64)
    XCTAssertNil(GalaxySSIHealthBluetoothPacket.decode(Data(bytes.dropLast())))
    XCTAssertNil(GalaxySSIHealthBluetoothPacket.decode(Data([0, 255, 7, 80, 0, 90, 0])))
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let receipt = GalaxySSIHealthBluetoothReceipt(device: UUID(), receivedAt: Date(), packet: packet)
    try records.write(receipt.reading(conditions: ""))
    var saved = try XCTUnwrap(records.load().current.first)
    saved.deleted = true
    try records.write(saved)
    let replay = GalaxySSIHealthBluetoothReceipt(device: receipt.device,
      receivedAt: receipt.receivedAt.addingTimeInterval(600), packet: packet)
    XCTAssertThrowsError(try records.write(replay.reading(conditions: ""), allowDuplicate: true))
    XCTAssertTrue(try records.load().current.isEmpty)
  }

  @MainActor
  func testOriginalLibraryKeepsExactBytesAndRejectsTamperedPayload() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: HealthFixtureSecrets(), fixtureDirectory: root)
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try store.store(pdf, name: "private-test-name.pdf")
    try store.store(pdf, name: "duplicate.pdf")
    let originals = try store.list().originals
    XCTAssertEqual(originals.count, 1)
    let item = try XCTUnwrap(originals.first)
    XCTAssertEqual(try store.read(item), pdf)
    let zip = try store.makeZIP([item])
    XCTAssertNotNil(zip.range(of: pdf))
    XCTAssertNotNil(zip.range(of: Data("manifest.json".utf8)))
    let file = root.appendingPathComponent(item.id.uuidString)
    var sealed = try Data(contentsOf: file)
    XCTAssertNil(sealed.range(of: Data(item.name.utf8)))
    XCTAssertNil(sealed.range(of: pdf))
    sealed[sealed.count - 1] ^= 1
    try sealed.write(to: file)
    XCTAssertThrowsError(try store.makeZIP([item]))
  }

  @MainActor
  func testOriginalZIPReceiptChecksReadbackAndPreservesPriorSuccess() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: HealthFixtureSecrets(), fixtureDirectory: root)
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try store.store(pdf, name: "private.pdf")
    let originals = try store.list().originals
    let output = root.appendingPathComponent("destination.zip")
    let (firstZIP, first) = try store.prepareExport(originals)
    XCTAssertTrue(store.hasShareArtifact(first))
    XCTAssertEqual(try store.readShareArtifact(first), firstZIP)
    XCTAssertEqual(try store.exportHistory().first?.outcome, .prepared)
    let artifact = root.appendingPathComponent("export-artifacts-v1").appendingPathComponent(first.id.uuidString)
    var sealedArtifact = try Data(contentsOf: artifact)
    XCTAssertNil(sealedArtifact.range(of: firstZIP))
    sealedArtifact[sealedArtifact.count - 1] ^= 1
    try sealedArtifact.write(to: artifact)
    XCTAssertThrowsError(try store.readShareArtifact(first))
    try firstZIP.write(to: output)
    XCTAssertTrue(try GalaxySSIHealthOriginalStore.verifyDestination(output, for: first))
    try store.finishExport(id: first.id, verified: true)
    let (secondZIP, second) = try store.prepareExport(originals)
    try Data(secondZIP.dropLast()).write(to: output)
    XCTAssertFalse(try GalaxySSIHealthOriginalStore.verifyDestination(output, for: second))
    var tampered = secondZIP
    tampered[tampered.count - 1] ^= 1
    try tampered.write(to: output)
    XCTAssertFalse(try GalaxySSIHealthOriginalStore.verifyDestination(output, for: second))
    try store.finishExport(id: second.id, verified: false)
    try store.finishExport(id: first.id, verified: false)
    let history = try store.exportHistory()
    XCTAssertEqual(history.map(\.outcome), [.unverified, .verified])
    XCTAssertEqual(history.last?.originals, originals)
    XCTAssertEqual(try store.list().originals, originals)
  }

  @MainActor
  func testSingleOriginalSaveChecksExactBytesAndRejectsReimportedSource() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: HealthFixtureSecrets(), fixtureDirectory: root,
                                             restoreRecordsFile: root.appendingPathComponent("records"))
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try store.store(pdf, name: "private.pdf")
    let source = try XCTUnwrap(store.list().originals.first)
    let output = root.appendingPathComponent("destination.pdf")
    let bytes = try store.read(source)
    XCTAssertEqual(bytes, pdf)
    XCTAssertTrue(try store.singleSaveHistory().isEmpty)
    try bytes.write(to: output)
    let matched = try GalaxySSIHealthOriginalStore.verifyDestination(output, bytes: source.bytes, sha256: source.sha256)
    XCTAssertTrue(matched)
    XCTAssertTrue(try store.finishSingleSave(source, destinationVerified: matched))

    var tampered = bytes
    tampered[tampered.count - 1] ^= 1
    try tampered.write(to: output)
    let corrupted = try GalaxySSIHealthOriginalStore.verifyDestination(output, bytes: source.bytes, sha256: source.sha256)
    XCTAssertFalse(corrupted)
    XCTAssertFalse(try store.finishSingleSave(source, destinationVerified: corrupted))

    try store.remove(store.previewRemoval(source))
    try store.store(pdf, name: source.name)
    XCTAssertThrowsError(try store.read(source))
    XCTAssertFalse(try store.finishSingleSave(source, destinationVerified: matched))
    let history = try store.singleSaveHistory()
    XCTAssertEqual(history.map(\.verified), [false, false, true])
    let receipt = try XCTUnwrap(history.first)
    let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt)) as? [String: Any])
    XCTAssertEqual(Set(fields.keys), Set(["at", "kind", "bytes", "verified"]))
    let audit = root.appendingPathComponent("single-save-v1")
    var sealed = try Data(contentsOf: audit)
    sealed[sealed.count - 1] ^= 1
    try sealed.write(to: audit)
    XCTAssertThrowsError(try store.singleSaveHistory())
  }

  @MainActor
  func testOriginalRemovalRequiresFreshLinkedRevisionsAndRetainsMetadataAndCopies() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: root.appendingPathComponent("records"))
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: root,
                                             restoreRecordsFile: records.isolatedFile)
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try store.store(pdf, name: "private.pdf")
    let original = try XCTUnwrap(store.list().originals.first)
    let (zip, export) = try store.prepareExport([original])
    let now = Date()
    func item(_ index: Int) -> GalaxySSIHealthReportReview.Item {
      let source = GalaxySSIHealthReportReview.Source(original: original.id, sha256: original.sha256,
                                                      page: index, region: 0, fromOCR: true)
      let reading = GalaxySSIHealthReading(metric: .weight, measuredAt: now.addingTimeInterval(Double(-120 * index)),
                                            value: 60, reportSource: source)
      return .init(version: UUID(), source: source, excerpt: "Fixture", reading: reading)
    }
    let linked = (1...35).map(item)
    for row in linked { try records.stageReportItem(row, replacing: nil) }
    try records.confirmReportItems(Set(linked.dropLast().map(\.version)), original: original)
    let initial = try store.previewRemoval(original)
    XCTAssertEqual(initial.links.count, 34)
    XCTAssertTrue(try store.removalHistory().isEmpty)
    XCTAssertEqual(try store.read(original), pdf)

    var edited = try XCTUnwrap(records.load().current.first)
    edited.notes = "Changed revision"
    try records.write(edited)
    XCTAssertThrowsError(try store.remove(initial)) { error in
      guard case GalaxySSIHealthOriginalStore.Failure.stale = error else { return XCTFail("Expected stale preview") }
    }
    let afterEdit = try store.previewRemoval(original)
    XCTAssertEqual(afterEdit.links.count, 34)
    try records.confirmReportItems([try XCTUnwrap(linked.last?.version)], original: original)
    XCTAssertThrowsError(try store.remove(afterEdit))
    let draft = item(36)
    try records.stageReportItem(draft, replacing: nil)
    let fresh = try store.previewRemoval(original)
    XCTAssertEqual(fresh.links.count, 35)
    try store.remove(fresh)

    let listing = try store.list()
    XCTAssertTrue(listing.originals.isEmpty)
    XCTAssertEqual(listing.removed, [original])
    XCTAssertTrue(listing.pendingRemovals.isEmpty)
    XCTAssertThrowsError(try store.read(original))
    XCTAssertEqual(try records.load().current.count, 35)
    XCTAssertEqual(try records.load().reportReview?.map(\.version), [draft.version])
    XCTAssertEqual(try store.readShareArtifact(export), zip)
    let history = try store.removalHistory()
    XCTAssertEqual(history.map(\.linkedMeasurements), [35])
    let encoded = try JSONEncoder().encode(history)
    let serialized = String(decoding: encoded, as: UTF8.self)
    XCTAssertFalse(serialized.contains(original.id.uuidString))
    XCTAssertFalse(serialized.contains(original.name))
    XCTAssertFalse(serialized.contains(original.sha256))
  }

  @MainActor
  func testHealthReportPDFReadsNativePageAndKeepsPageBounds() throws {
    let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 240, height: 200)).pdfData { context in
      context.beginPage()
      ("Synthetic report line 12345" as NSString).draw(at: CGPoint(x: 12, y: 18),
        withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
      context.beginPage()
    }
    XCTAssertEqual(try GalaxySSIHealthPDFText.pageCount(data), 2)
    let result = try GalaxySSIHealthPDFText.read(data, page: 0)
    XCTAssertEqual(result.method, .native)
    let text = try XCTUnwrap(result.regions.first)
    XCTAssertTrue(text.text.contains("Synthetic report"))
    XCTAssertTrue(result.crop.contains(text.bounds))
    let highlight = try XCTUnwrap(text.highlight)
    XCTAssertNotNil(result.preview)
    XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(highlight))
    XCTAssertLessThan(highlight.minY, 0.25)
    XCTAssertThrowsError(try GalaxySSIHealthPDFText.read(data, page: 2))
  }

  func testHealthPDFHighlightClipsToViewportAndFlipsVerticalAxis() throws {
    let viewport = CGRect(x: 20, y: 40, width: 100, height: 200)
    let region = CGRect(x: 10, y: 190, width: 35, height: 40)
    let highlight = try XCTUnwrap(GalaxySSIHealthPDFText.normalizedTopOrigin(region, in: viewport))
    XCTAssertEqual(highlight.minX, 0, accuracy: 0.0001)
    XCTAssertEqual(highlight.minY, 0.05, accuracy: 0.0001)
    XCTAssertEqual(highlight.width, 0.25, accuracy: 0.0001)
    XCTAssertNil(GalaxySSIHealthPDFText.normalizedTopOrigin(CGRect(x: 400, y: 0, width: 10, height: 10), in: viewport))
  }

  func testTrendAuditPinsContributorsAndExtremumRevision() throws {
    let now = Date()
    let readings = (0..<34).map {
      GalaxySSIHealthReading(revision: $0 + 1, metric: .glucose, measuredAt: now,
        value: Decimal(40 - $0))
    }
    let excluded = GalaxySSIHealthReading(metric: .glucose, measuredAt: now, value: 1, unitOverride: "mg/dL")
    func point(_ inputs: [GalaxySSIHealthReading]) throws -> GalaxySSIHealthTrend.Point {
      try XCTUnwrap(GalaxySSIHealthTrend(current: inputs, metric: .glucose, component: .value,
        now: now, dayCount: 7, calendar: .current, source: .manual).points.last)
    }
    let original = try point(readings + [excluded])
    XCTAssertEqual(original.readings.count, 34)
    XCTAssertEqual(original.value(.min, component: .value), 7)
    XCTAssertEqual(original.value(.max, component: .value), 40)
    XCTAssertEqual(original.extremum(.min, component: .value)?.revision, 34)
    XCTAssertEqual(original.revisions, try point(Array(readings.reversed())).revisions)
    var revised = readings
    revised[33].revision += 1
    XCTAssertNotEqual(original.revisions, try point(revised).revisions)
  }

  func testHealthAssistantSendsOnlyAggregatesAndRejectsUnknownEvidence() throws {
    let now = Date()
    let reading = GalaxySSIHealthReading(revision: 2, metric: .glucose, measuredAt: now, value: 6)
    let other = GalaxySSIHealthReading(metric: .glucose, measuredAt: now, value: 100, unitOverride: "mg/dL")
    let unrelated = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 72)
    let scope = GalaxySSIHealthAnalysis.Scope(interval: DateInterval(start: now, duration: 86_400), metrics: [.glucose])
    let analysis = GalaxySSIHealthAnalysis(scope: scope, current: [reading, other, unrelated], calendar: .current)
    XCTAssertEqual(analysis.evidence.count, 2)
    XCTAssertEqual(analysis.evidence.first?.aggregate.mean, "6")
    XCTAssertEqual(analysis.evidence.first?.readings.map(\.id), [reading.id])
    XCTAssertTrue(analysis.isCurrent([other, reading]))
    XCTAssertFalse(analysis.isCurrent([other]))
    let data = try analysis.requestJSON()
    let packet = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(Set(packet.keys), ["requestedDays", "aggregates"])
    let aggregates = try XCTUnwrap(packet["aggregates"] as? [[String: Any]])
    XCTAssertEqual(Set(try XCTUnwrap(aggregates.first).keys),
      ["id", "metric", "component", "unit", "count", "observedDays", "minimum", "maximum", "mean"])
    let output = #"{"evidence":["e1"],"next_step":"review_sources"}"#
    XCTAssertEqual(try analysis.recommendation(output).evidence, ["e1"])
    XCTAssertThrowsError(try analysis.recommendation(#"{"evidence":["e99"],"next_step":"review_sources"}"#))
    XCTAssertThrowsError(try analysis.recommendation(#"{"evidence":["e1"],"next_step":"review_sources","text":"extra"}"#))
  }

  func testTrendKeepsCalendarGapsAndExactComponentCohorts() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)))
    let first = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: now))
    let one = GalaxySSIHealthReading(revision: 2, metric: .bloodPressure, measuredAt: first,
                                   value: 120, diastolic: 80, pulse: 64)
    let two = GalaxySSIHealthReading(revision: 3, metric: .bloodPressure, measuredAt: now,
                                   value: 124, diastolic: 82, pulse: 69)
    let missing = GalaxySSIHealthReading(metric: .bloodPressure, measuredAt: now,
                                       value: 126, diastolic: 84)
    let trend = GalaxySSIHealthTrend(current: [two, one, missing], metric: .bloodPressure,
                                    component: .pulse, now: now, dayCount: 3, calendar: calendar)
    XCTAssertEqual(trend.validDays, 2)
    XCTAssertNil(trend.points[1].mean)
    XCTAssertEqual(trend.points[2].readings.map(\.revision), [3])
    XCTAssertEqual(trend.mean, Decimal(string: "66.5"))
    XCTAssertEqual(trend.minimum, 64)
    XCTAssertEqual(trend.maximum, 69)
  }

  func testHealthCatalogRefreshAnchorsToSurvivingVisibleRecord() throws {
    let anchor = try XCTUnwrap(GalaxySSIHealthCatalogAnchor.restoration(
      visible: [29, 30], updated: [100, 101] + Array(0..<29) + [30, 31], limit: 30))
    XCTAssertEqual(anchor.id, 30)
    XCTAssertEqual(anchor.limit, 32)
    XCTAssertNil(GalaxySSIHealthCatalogAnchor.restoration(visible: [29], updated: [30], limit: 30))
  }

  func testHealthCatalogTypedResultsDoNotEnterNumericTrendsOrMixUnits() throws {
    XCTAssertEqual(GalaxySSIHealthMetric.allCases.count, 27)
    XCTAssertTrue(GalaxySSIHealthMetric.hemoglobin.matches("HGB g/L"))
    let bound = try XCTUnwrap(GalaxySSIHealthReportedResult.parse("< 2.50", metric: .glucose))
    XCTAssertEqual(bound.kind, .comparison)
    XCTAssertEqual(bound.canonical, "<2.5")
    XCTAssertEqual(GalaxySSIHealthReportedResult.parse("1 - 4", metric: .glucose)?.kind, .range)
    XCTAssertNil(GalaxySSIHealthReportedResult.parse("4 - 1", metric: .glucose))
    let label = try XCTUnwrap(GalaxySSIHealthReportedResult.parse("Negative", metric: .urineProtein))
    XCTAssertTrue(GalaxySSIHealthReading(metric: .urineProtein, value: nil, reported: label).isValid)
    XCTAssertFalse(GalaxySSIHealthReading(metric: .urineProtein, value: 0).isValid)
    XCTAssertTrue(GalaxySSIHealthReading(metric: .steps, value: 0).isValid)
    XCTAssertFalse(GalaxySSIHealthReading(metric: .steps, value: Decimal(string: "1.5")).isValid)
    let now = Date()
    let range = GalaxySSIHealthReading(metric: .glucose, measuredAt: now, value: nil, reported: bound)
    let standard = GalaxySSIHealthReading(metric: .glucose, measuredAt: now, value: 6)
    let otherUnit = GalaxySSIHealthReading(metric: .glucose, measuredAt: now, value: 100, unitOverride: "mg/dL")
    let trend = GalaxySSIHealthTrend(current: [range, standard, otherUnit], metric: .glucose,
      component: .value, now: now, dayCount: 7, calendar: .current)
    XCTAssertEqual(trend.mean, 6)
    XCTAssertEqual(trend.points.last?.readings.map(\.id), [standard.id])
  }

  @MainActor
  func testStructuredImportKeepsExactSourceAndUndoPreservesEdits() throws {
    let data = Data("value,time,note\r\n60,2025-01-01T12:00:00Z,\"line\r\nnext\"\r\n61,2025-01-02T12:00:00Z,\r\n60,2025-01-01T12:00:00Z,\r\n".utf8)
    let table = try GalaxySSIHealthTableImport.parse(data, json: false)
    XCTAssertEqual(table.rows.first?[2], "line\r\nnext")
    let mapping = GalaxySSIHealthTableImport.Mapping(metric: .weight, value: 0, date: 1, notes: 2, confirmedUnit: true)
    let rows = try GalaxySSIHealthTableImport.preview(table, mapping: mapping, current: [])
    XCTAssertEqual(rows.map(\.status), [.ready, .ready, .duplicate])
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    XCTAssertEqual(try records.importTable(data, name: "fixture.csv", json: false, mapping: mapping,
                                           expected: rows.map(\.status)), 2)
    XCTAssertThrowsError(try records.importTable(data, name: "fixture.csv", json: false, mapping: mapping,
                                                  expected: rows.map(\.status)))
    let archive = try records.load()
    let batch = try XCTUnwrap(archive.tableBatches?.first)
    XCTAssertEqual(batch.data, data)
    XCTAssertNil(try Data(contentsOf: file).range(of: data))
    var edited = try XCTUnwrap(archive.current.first)
    edited.value = 62
    try records.write(edited)
    XCTAssertEqual(try records.undoTableBatch(batch.id), 1)
    XCTAssertEqual(try records.load().current.map(\.value), [62])
    XCTAssertEqual(try records.undoTableBatch(batch.id), 0)
  }

  @MainActor
  func testReviewOnlyTablePreservesSourceReferenceWithoutArchivingBytes() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: root.appendingPathComponent("records"))
    let originals = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: root)
    let data = Data("value,time\n60,2025-01-01T12:00:00Z\n".utf8)
    let mapping = GalaxySSIHealthTableImport.Mapping(metric: .weight, value: 0, date: 1, confirmedUnit: true)
    try records.setPrivacy(.importOriginals, enabled: false)
    let pendingRetention = try XCTUnwrap(GalaxySSIHealthImportRetentionChoice.useDefault.resolve(
      default: records.load().keepsNewImportOriginals))
    try records.setPrivacy(.importOriginals, enabled: true)
    XCTAssertEqual(try records.importTable(data, name: "review.csv", json: false, mapping: mapping,
                                           expected: [.ready], retainOriginal: pendingRetention), 1)
    let archive = try records.load()
    let batch = try XCTUnwrap(archive.tableBatches?.first)
    let source = try XCTUnwrap(archive.current.first?.tableSource)
    XCTAssertTrue(batch.data.isEmpty)
    XCTAssertEqual(source.batch, batch.id)
    XCTAssertEqual(source.sha256, batch.sourceDigest)
    XCTAssertNil(GalaxySSIHealthTableImport.Batch.original(for: batch.id, in: [batch]))
    let independent = GalaxySSIHealthTableImport.Batch(id: UUID(), name: "archived.csv", at: Date(),
                                                       data: data, inserted: 1, undone: nil)
    XCTAssertEqual(GalaxySSIHealthTableImport.Batch.original(for: batch.id, in: [batch, independent])?.id, independent.id)
    let plan = try GalaxySSIHealthPortableBackup.plan(records: records, originals: originals)
    let (_, summary) = try GalaxySSIHealthPortableBackup.prepare(plan, records: records, originals: originals)
    XCTAssertEqual(summary.tables, 0)
    XCTAssertEqual(summary.links, 1)
  }

  func testStructuredOriginalPreviewBoundsDoNotMutateSourceTable() throws {
    let long = String(repeating: "x", count: 300)
    let columns = (0..<13).map { "column\($0)" }
    let rows = Array(repeating: Array(repeating: long, count: 13), count: 31)
    let table = GalaxySSIHealthTableImport.Table(headers: columns, rows: rows)
    let sample = GalaxySSIHealthTableSourceSample(table)
    XCTAssertTrue(sample.limited)
    XCTAssertEqual(sample.headers.count, 12)
    XCTAssertEqual(sample.rows.count, 30)
    XCTAssertEqual(sample.rows.first?.first?.count, 256)
    XCTAssertEqual(table.rows.first?.first, long)
  }

  func testXLSXUsesWorksheetRelationshipsPhysicalRowsAndExplicitFormulaConsent() throws {
    let xml = [
      "xl/workbook.xml": #"<workbook xmlns:r="urn:test"><workbookPr date1904="1"/><sheets><sheet name="Weight" r:id="rId7"/></sheets></workbook>"#,
      "xl/_rels/workbook.xml.rels": #"<Relationships><Relationship Id="rId7" Type="urn:test/worksheet" Target="worksheets/sheet3.xml"/></Relationships>"#,
      "xl/worksheets/sheet3.xml": #"<worksheet><sheetData><row r="3"><c r="A3" t="inlineStr"><is><t>Value</t></is></c><c r="C3" t="inlineStr"><is><t>Time</t></is></c></row><row r="8"><c r="A8"><f>1+60</f><v>61</v></c><c r="C8"><v>1.5</v></c></row></sheetData></worksheet>"#
    ]
    let data = AgentRuntimeProjectArchiveBuilder.buildStoredZip(entries: xml.map { .init(path: $0.key, data: Data($0.value.utf8)) })
    let workbook = try GalaxySSIHealthXLSX(data)
    let table = try workbook.table(.init(sheet: "rId7", header: 3))
    XCTAssertEqual(table.headers, ["Value", "", "Time"])
    XCTAssertEqual(table.sheetPath, "xl/worksheets/sheet3.xml")
    let sample = GalaxySSIHealthTableSourceSample(sheetRows: try workbook.rows("rId7"))
    XCTAssertEqual(sample.rowNumbers, [3, 8])
    XCTAssertEqual(sample.rows.last?.first, "=1+60\n61")
    let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    var mapping = GalaxySSIHealthTableImport.Mapping(metric: .weight, value: 0, date: 2,
                                                     confirmedUnit: true, dateStyle: .excel, localZone: utc)
    XCTAssertEqual(try GalaxySSIHealthTableImport.preview(table, mapping: mapping, current: []).first?.status, .invalid)
    mapping.useFormulaCache = true
    let row = try XCTUnwrap(GalaxySSIHealthTableImport.preview(table, mapping: mapping, current: []).first)
    XCTAssertEqual(row.id, 8)
    XCTAssertEqual(row.reading?.value, 61)
    XCTAssertEqual(row.reading?.measuredAt, ISO8601DateFormatter().date(from: "1904-01-02T12:00:00Z"))
    XCTAssertNil(GalaxySSIHealthXLSX.date(serial: 60, date1904: false, zone: utc))
    var damaged = data
    let cached = try XCTUnwrap(damaged.range(of: Data("<v>61</v>".utf8)))
    damaged[cached.lowerBound + 3] = 55
    XCTAssertThrowsError(try GalaxySSIHealthXLSX(damaged))
    var nativeParts = xml
    let sheetPath = "xl/worksheets/sheet3.xml"
    nativeParts[sheetPath] = try XCTUnwrap(xml[sheetPath]).replacingOccurrences(
      of: #"<c r="C8"><v>1.5</v></c>"#,
      with: #"<c r="C8" t="d"><v>2025-11-02T01:30:00-04:00</v></c>"#)
    let nativeData = AgentRuntimeProjectArchiveBuilder.buildStoredZip(entries: nativeParts.map {
      .init(path: $0.key, data: Data($0.value.utf8))
    })
    let nativeWorkbook = try GalaxySSIHealthXLSX(nativeData)
    let nativeRow = try XCTUnwrap(nativeWorkbook.rows("rId7").last)
    XCTAssertEqual(nativeRow.isoDates, [2])
    XCTAssertEqual(nativeRow.formulaText[0], "1+60")
    XCTAssertEqual(nativeRow.cells[2], "2025-11-02T01:30:00-04:00")
  }

  func testXLSXTypedDatesPreserveOffsetAndRejectAmbiguousWallTimes() throws {
    let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let expected = ISO8601DateFormatter().date(from: "2025-11-02T05:30:00Z")
    XCTAssertEqual(GalaxySSIHealthXLSX.isoDate("2025-11-02T01:30:00-04:00", zone: utc, dateOnlyMinute: nil), expected)
    XCTAssertNil(GalaxySSIHealthXLSX.isoDate("2025-11-02T01:30:00", zone: zone, dateOnlyMinute: nil))
    XCTAssertNil(GalaxySSIHealthXLSX.isoDate("2025-03-09T02:30:00", zone: zone, dateOnlyMinute: nil))
    XCTAssertNil(GalaxySSIHealthXLSX.isoDate("2025-02-30T12:00:00Z", zone: utc, dateOnlyMinute: nil))
    XCTAssertNil(GalaxySSIHealthXLSX.isoDate("2025-11-02", zone: zone, dateOnlyMinute: nil))
    XCTAssertEqual(GalaxySSIHealthXLSX.isoDate("2025-11-02", zone: zone, dateOnlyMinute: 720),
                   ISO8601DateFormatter().date(from: "2025-11-02T17:00:00Z"))
    let table = GalaxySSIHealthTableImport.Table(headers: ["Value", "Time"],
      rows: [["61", "2025-11-02T01:30:00-04:00"], ["62", "44500"]], rowNumbers: [4, 9],
      formulas: [[], []], date1904: false, isoDates: [[1], []])
    let mapping = GalaxySSIHealthTableImport.Mapping(metric: .weight, value: 0, date: 1,
      confirmedUnit: true, dateStyle: .excel, localZone: zone)
    let rows = try GalaxySSIHealthTableImport.preview(table, mapping: mapping, current: [])
    XCTAssertEqual(rows.map(\.status), [.ready, .ready])
    XCTAssertEqual(rows.first?.reading?.measuredAt, expected)
    XCTAssertEqual(rows.first?.rawDate, "2025-11-02T01:30:00-04:00")
  }

  func testPaperEdgeSuggestionConvertsOriginAndRejectsClippedOrSmallRectangles() throws {
    let accepted = try XCTUnwrap(GalaxySSIHealthPaperEdges.paddedCrop(
      visionBounds: CGRect(x: 0.15, y: 0.10, width: 0.6, height: 0.5)))
    XCTAssertEqual(accepted.minX, 0.125, accuracy: 0.0001)
    XCTAssertEqual(accepted.minY, 0.375, accuracy: 0.0001)
    XCTAssertEqual(accepted.height, 0.55, accuracy: 0.0001)
    XCTAssertNil(GalaxySSIHealthPaperEdges.paddedCrop(visionBounds: CGRect(x: 0, y: 0.1, width: 0.6, height: 0.5)))
    XCTAssertNil(GalaxySSIHealthPaperEdges.paddedCrop(visionBounds: CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)))
  }

  @MainActor
  func testEncryptedReportCropKeepsOriginalAndRejectsStaleReplacement() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: HealthFixtureSecrets(), fixtureDirectory: root)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let png = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 80), format: format).pngData { context in
      UIColor.red.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
    }
    try store.store(png, name: "fixture.png")
    let original = try XCTUnwrap(store.list().originals.first)
    let output = try GalaxySSIHealthCropEncoder.encode(png, bounds: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    XCTAssertEqual(output.width, 50)
    XCTAssertEqual(output.height, 40)
    let saved = try store.saveCrop(output, for: original, replacing: nil)
    XCTAssertEqual(try store.readCrop(for: original)?.metadata, saved)
    XCTAssertEqual(try store.readCrop(for: original)?.png, output.png)
    XCTAssertThrowsError(try store.saveCrop(output, for: original, replacing: nil))
    XCTAssertEqual(try store.read(original), png)
    let sealed = root.appendingPathComponent("report-crops-v1").appendingPathComponent(original.id.uuidString)
    XCTAssertNil(try Data(contentsOf: sealed).range(of: output.png))
    let cropRoot = sealed.deletingLastPathComponent()
    let interrupted = cropRoot.appendingPathComponent(UUID().uuidString).appendingPathExtension("pending")
    let unrelated = cropRoot.appendingPathComponent("unrelated.pending")
    try Data([1, 2, 3]).write(to: interrupted)
    try Data([4]).write(to: unrelated)
    let committed = try Data(contentsOf: sealed)
    let reopened = GalaxySSIHealthOriginalStore(owner: store.owner, secrets: store.secrets, fixtureDirectory: root)
    try reopened.recoverInterruptedCrops()
    XCTAssertFalse(FileManager.default.fileExists(atPath: interrupted.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    XCTAssertEqual(try Data(contentsOf: sealed), committed)
    XCTAssertEqual(try reopened.readCrop(for: original)?.metadata, saved)
    XCTAssertEqual(try reopened.read(original), png)
  }
}

private final class HealthFixtureSecrets: GalaxySSISecretStore {
  private var values: [String: String] = [:]
  func setString(_ value: String, account: String) throws { values[account] = value }
  func string(account: String) -> String? { values[account] }
  func delete(account: String) { values.removeValue(forKey: account) }
}
