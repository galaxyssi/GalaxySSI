import Foundation
import UIKit
import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthRecordsTests: XCTestCase {
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
    let link = try XCTUnwrap(episode.first.reportLink())
    XCTAssertFalse(link.allowsRefresh)
    XCTAssertEqual(link.metrics, [.sleepDuration])
    XCTAssertEqual(episode.first.contributors(readings, baseline: true)?.count, 13)
    XCTAssertEqual(episode.first.contributors(readings, baseline: false)?.count, 6)
    var edited = readings
    edited[0].revision += 1
    XCTAssertFalse(link.isCurrent(edited))
    XCTAssertNil(episode.first.contributors(edited, baseline: true))
    ledger.reconcile(current: readings, allowed: true, now: now.addingTimeInterval(60), calendar: calendar)
    XCTAssertEqual(ledger.episodes, [episode])
    ledger.reconcile(current: Array(readings.dropFirst(2)), allowed: true, now: now, calendar: calendar)
    XCTAssertEqual(ledger.episodes.first?.closed, true)
    ledger.reconcile(current: readings, allowed: false, now: now, calendar: calendar)
    XCTAssertFalse(ledger.episodes.contains { !$0.closed })
  }

  @MainActor
  func testHealthKitEraseInvalidatesPreviewWhenReportEvidenceChanges() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let date = Date()
    let original = GalaxySSIHealthOriginalStore.Original(id: UUID(), name: "fixture.pdf", kind: .pdf,
      fileExtension: "pdf", importedAt: date, bytes: 1, sha256: String(repeating: "a", count: 64))
    let imported = GalaxySSIHealthReading(metric: .weight, measuredAt: date, value: 65,
      healthKitSource: .init(key: String(repeating: "b", count: 64), origin: "fixture", name: nil))
    _ = try records.importHealthKit([imported])
    let preview = try records.previewHealthKitErase(.weight)
    let source = GalaxySSIHealthReportReview.Source(original: original.id, sha256: original.sha256,
      page: 0, region: 0, fromOCR: true)
    let item = GalaxySSIHealthReportReview.Item(version: UUID(), source: source, excerpt: "fixture",
      reading: .init(metric: .weight, measuredAt: date, value: 65, reportSource: source))
    try records.stageReportItem(item, replacing: nil)
    let target = try XCTUnwrap(GalaxySSIHealthReportReview.exactTarget(for: item, current: records.load().current))
    try records.linkReportDuplicates([item.version: target], original: original)
    XCTAssertThrowsError(try records.eraseHealthKitCopies(preview))
    let latest = try records.previewHealthKitErase(.weight)
    XCTAssertEqual(latest.reportLinks.map(\.target), [target])
    XCTAssertEqual(try records.eraseHealthKitCopies(latest), 1)
    XCTAssertTrue(try records.load().reportEvidence?.isEmpty == true)
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
  func testAppleHealthPressureErasePreservesSameValueBluetoothPressure() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let now = Date()
    let packet = try XCTUnwrap(GalaxySSIHealthBluetoothPacket.decode(Data([0, 120, 0, 80, 0, 90, 0])))
    let receipt = GalaxySSIHealthBluetoothReceipt(device: UUID(), receivedAt: now, packet: packet)
    let bluetooth = receipt.reading(conditions: "")
    let imported = GalaxySSIHealthReading(metric: .bloodPressure, measuredAt: now, value: 120, diastolic: 80,
      healthKitSource: .init(key: String(repeating: "a", count: 64), origin: "fixture", name: nil))
    try records.write(bluetooth)
    XCTAssertEqual(try records.importHealthKit([imported]), 1)
    let preview = try records.previewHealthKitErase(.bloodPressure)
    XCTAssertEqual(preview.count, 1)
    XCTAssertEqual(try records.eraseHealthKitCopies(preview), 1)
    let archive = try records.load()
    XCTAssertEqual(archive.revisions.map(\.id), [bluetooth.id])
    XCTAssertEqual(archive.current.first?.bluetoothReceipt, receipt)
  }

  @MainActor
  func testHealthKitCopyEraseWorksWithoutDerivedPermissionAndKeepsOtherData() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let now = Date()
    let weight = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 65,
      healthKitSource: .init(key: String(repeating: "a", count: 64), origin: "fixture", name: nil))
    let pulse = GalaxySSIHealthReading(metric: .heartRate, measuredAt: now, value: 72,
      healthKitSource: .init(key: String(repeating: "b", count: 64), origin: "fixture", name: nil))
    let manual = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 68)
    try records.write(manual)
    _ = try records.importHealthKit([weight, pulse])
    let checkpoint = try records.beginHealthKitSync(.weight, floor: now.addingTimeInterval(-86_400), reset: false)
    let old = try records.previewHealthKitErase(.weight)
    var updated = try XCTUnwrap(records.load().current.first { $0.id == weight.id })
    updated.notes = "edited after preview"
    updated.measuredAt = now.addingTimeInterval(60)
    try records.write(updated)
    XCTAssertThrowsError(try records.eraseHealthKitCopies(old))
    let latest = try XCTUnwrap(records.load().current.first { $0.id == weight.id })
    let draft = GalaxySSIHealthDraft(existing: latest)
    try records.storeDraft(draft)
    let plan = try records.previewHealthKitErase(.weight)
    XCTAssertEqual(plan.count, 1)
    XCTAssertEqual(plan.versions.count, 2)
    XCTAssertEqual(plan.start, now)
    XCTAssertEqual(plan.end, updated.measuredAt)
    XCTAssertEqual(try records.eraseHealthKitCopies(plan), 1)
    let archive = try records.load()
    XCTAssertFalse(archive.derivesOverview == true)
    XCTAssertEqual(Set(archive.current.map(\.id)), [manual.id, pulse.id])
    XCTAssertEqual(archive.healthKitSync?["weight"], checkpoint)
    XCTAssertNil(archive.draft)
    XCTAssertEqual(archive.healthKitErasureLog?.last?.scope, "weight")
    XCTAssertThrowsError(try records.storeDraft(draft))
  }

  @MainActor
  func testHealthKitCoverageKeepsSelectionReadEvidenceAndSyncHistorySeparate() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    try records.setHealthKitSelection([.weight, .steps])
    let now = Date()
    let checkpoint = try records.beginHealthKitSync(.weight, floor: now.addingTimeInterval(-86_400), reset: false)
    let page = GalaxySSIHealthKitSync.Page(rows: [], anchor: Data([1]), providerCount: 0, more: false)
    _ = try records.commitHealthKitPage(scope: .weight, expected: checkpoint, page: page, at: now)
    var archive = try records.load()
    var coverage = GalaxySSIHealthKitSync.Coverage(scope: .weight, selection: archive.healthKitSelection ?? [],
      reads: archive.healthKitReadAt ?? [:], checkpoints: archive.healthKitSync ?? [:])
    XCTAssertTrue(coverage.selected)
    XCTAssertNil(coverage.lastReadableAt)
    XCTAssertEqual(coverage.lastCompletedAt, now)
    try records.setHealthKitSelection([.steps])
    _ = try records.beginHealthKitSync(.weight, floor: now, reset: true)
    archive = try records.load()
    coverage = GalaxySSIHealthKitSync.Coverage(scope: .weight, selection: archive.healthKitSelection ?? [],
      reads: archive.healthKitReadAt ?? [:], checkpoints: archive.healthKitSync ?? [:])
    XCTAssertFalse(coverage.selected)
    XCTAssertEqual(coverage.lastCompletedAt, now)
    XCTAssertNil(coverage.lastReadableAt)
  }

  func testSyncIncidentDeliveryKeepsTokenAndCancelsWhenDeselected() throws {
    let now = Date()
    let incident = UUID()
    let job = GalaxySSIHealthReviewReminders.Job(target: incident, kind: .incident,
      versions: [UUID()], at: now, scope: "weight")
    var state = GalaxySSIHealthReviewReminders.State()
    state.notificationPreferences = .init(quietStart: 0, quietEnd: 0, incidentEnabled: true)
    let (tickets, desired) = GalaxySSIHealthReviewDelivery.plan(jobs: [job], state: state, now: now,
      calendar: .current, permitted: true, scheduled: [], delivered: [])
    let first = try XCTUnwrap(desired.first)
    XCTAssertFalse(first.identifier.contains(incident.uuidString))
    state.deliveries = tickets
    let retry = GalaxySSIHealthReviewReminders.Job(target: incident, kind: .incident,
      versions: [UUID()], at: now, scope: "weight")
    let (adopted, next) = GalaxySSIHealthReviewDelivery.plan(jobs: [retry], state: state, now: now,
      calendar: .current, permitted: true, scheduled: [], delivered: [first.token])
    XCTAssertEqual(next.first?.token, first.token)
    XCTAssertEqual(next.first?.submitted, true)
    state.deliveries = adopted
    state.notificationPreferences?.incidentScopes = []
    let (retained, cancelled) = GalaxySSIHealthReviewDelivery.plan(jobs: [retry], state: state, now: now,
      calendar: .current, permitted: true, scheduled: [], delivered: [first.token])
    XCTAssertEqual(retained[retry.key]?.token, first.token)
    XCTAssertTrue(cancelled.isEmpty)
    let (resolved, _) = GalaxySSIHealthReviewDelivery.plan(jobs: [], state: state, now: now,
      calendar: .current, permitted: true, scheduled: [], delivered: [first.token])
    XCTAssertTrue(resolved.isEmpty)
  }

  func testReviewNotificationPlanDefersAndDoesNotReplayDelivery() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 23)))
    let job = GalaxySSIHealthReviewReminders.Job(target: UUID(), kind: .report, versions: [], at: now)
    var state = GalaxySSIHealthReviewReminders.State()
    state.enabled = true
    state.notificationPreferences = .init(enabled: true)
    let (tickets, desired) = GalaxySSIHealthReviewDelivery.plan(jobs: [job], state: state, now: now,
      calendar: calendar, permitted: true, scheduled: [], delivered: [])
    var ticket = try XCTUnwrap(desired.first)
    XCTAssertEqual(calendar.component(.hour, from: ticket.due), 8)
    XCTAssertFalse(ticket.identifier.contains(job.target.uuidString))
    ticket.submitted = true
    state.deliveries = tickets.merging([job.key: ticket]) { _, new in new }
    let later = ticket.due.addingTimeInterval(5)
    let (_, afterRestart) = GalaxySSIHealthReviewDelivery.plan(jobs: [job], state: state, now: later,
      calendar: calendar, permitted: true, scheduled: [], delivered: [])
    XCTAssertEqual(afterRestart, [ticket])
    let snooze = later.addingTimeInterval(3_600)
    state.actions[job.key] = .snoozed(snooze)
    let (_, delayed) = GalaxySSIHealthReviewDelivery.plan(jobs: [job], state: state, now: later,
      calendar: calendar, permitted: true, scheduled: [], delivered: [])
    XCTAssertEqual(delayed.first?.due, snooze)
    XCTAssertNotEqual(delayed.first?.token, ticket.token)
    let (_, denied) = GalaxySSIHealthReviewDelivery.plan(jobs: [job], state: state, now: later,
      calendar: calendar, permitted: false, scheduled: [], delivered: [])
    XCTAssertTrue(denied.isEmpty)
  }

  @MainActor
  func testHealthSyncIncidentKeepsIdentityAndResolvesOnEmptySuccess() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let now = Date()
    let floor = now.addingTimeInterval(-86_400)
    let interrupted = try records.beginHealthKitSync(.weight, floor: floor, reset: false)
    try records.finishHealthKitSync(.weight, run: interrupted.run, status: .interrupted)
    XCTAssertNil(try records.load().healthKitIncidents?["weight"])
    let failed = try records.beginHealthKitSync(.weight, floor: floor, reset: false)
    try records.finishHealthKitSync(.weight, run: failed.run, status: .failed)
    let first = try XCTUnwrap(records.load().healthKitIncidents?["weight"])
    try records.acknowledgeHealthKitIncident(first)
    XCTAssertTrue(try XCTUnwrap(records.load().healthKitIncidents?["weight"]).acknowledged)
    let retry = try records.beginHealthKitSync(.weight, floor: floor, reset: false)
    try records.finishHealthKitSync(.weight, run: retry.run, status: .permission)
    let repeated = try XCTUnwrap(records.load().healthKitIncidents?["weight"])
    XCTAssertEqual(repeated.id, first.id)
    XCTAssertEqual(repeated.attempts, 2)
    XCTAssertFalse(repeated.acknowledged)
    XCTAssertThrowsError(try records.acknowledgeHealthKitIncident(first))
    try records.setHealthKitSelection([.weight])
    XCTAssertEqual(GalaxySSIHealthReviewReminders.deliveryJobs(in: try records.load()).map(\.target), [repeated.id])
    try records.setHealthKitSelection([])
    XCTAssertTrue(GalaxySSIHealthReviewReminders.deliveryJobs(in: try records.load()).isEmpty)
    XCTAssertEqual(try records.load().healthKitIncidents?["weight"], repeated)
    let success = try records.beginHealthKitSync(.weight, floor: floor, reset: false)
    let page = GalaxySSIHealthKitSync.Page(rows: [], anchor: Data([1]), providerCount: 0, more: false)
    XCTAssertEqual(try records.commitHealthKitPage(scope: .weight, expected: success, page: page, at: now).status, .empty)
    XCTAssertNil(try records.load().healthKitIncidents?["weight"])
    XCTAssertTrue(try records.load().current.isEmpty)
  }

  @MainActor
  func testHealthKitSyncCommitsPageAndCursorTogetherAndResumesWithoutDeleting() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let now = Date()
    let floor = now.addingTimeInterval(-86_400)
    let first = try records.beginHealthKitSync(.weight, floor: floor, reset: false)
    let item = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 65,
      healthKitSource: .init(key: String(repeating: "a", count: 64), origin: "fixture", name: nil))
    let broken = GalaxySSIHealthKitSync.Page(rows: [item, .init(metric: .weight, value: 66)], anchor: Data([1]),
      providerCount: 2, more: true)
    XCTAssertThrowsError(try records.commitHealthKitPage(scope: .weight, expected: first, page: broken, at: now))
    XCTAssertTrue(try records.load().current.isEmpty)
    XCTAssertNil(try records.load().healthKitSync?["weight"]?.anchor)
    let page = GalaxySSIHealthKitSync.Page(rows: [item], anchor: Data([2]), providerCount: 1, more: true)
    let saved = try records.commitHealthKitPage(scope: .weight, expected: first, page: page, at: now)
    XCTAssertEqual(saved.anchor, Data([2]))
    XCTAssertEqual(try records.load().current.map(\.id), [item.id])
    XCTAssertThrowsError(try records.commitHealthKitPage(scope: .weight, expected: first, page: page, at: now))
    try records.finishHealthKitSync(.weight, run: saved.run, status: .interrupted)
    let resumed = try records.beginHealthKitSync(.weight, floor: now, reset: false)
    XCTAssertEqual(resumed.floor, floor)
    XCTAssertEqual(resumed.anchor, saved.anchor)
    let deletionOnly = GalaxySSIHealthKitSync.Page(rows: [], anchor: Data([3]), providerCount: 1, more: false)
    XCTAssertEqual(try records.commitHealthKitPage(scope: .weight, expected: resumed, page: deletionOnly, at: now).status, .empty)
    XCTAssertEqual(try records.load().current.map(\.id), [item.id])
    let reset = try records.beginHealthKitSync(.weight, floor: now, reset: true)
    XCTAssertTrue(reset.previousCoverageUnverified)
    XCTAssertNil(reset.anchor)
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

  @MainActor
  func testBluetoothEraseRejectsStalePreviewAndKeepsSameNameDevice() throws {
    let packet = try XCTUnwrap(GalaxySSIHealthBluetoothPacket.decode(Data([0, 120, 0, 80, 0, 90, 0])))
    let now = Date()
    let a = GalaxySSIHealthBluetoothReceipt(device: UUID(), receivedAt: now, packet: packet, deviceName: "Same monitor")
    let b = GalaxySSIHealthBluetoothReceipt(device: UUID(), receivedAt: now, packet: packet, deviceName: "Same monitor")
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    try records.write(a.reading(conditions: ""))
    try records.write(b.reading(conditions: ""))
    XCTAssertThrowsError(try records.previewBluetoothErase(a.device))
    try records.setOverviewPermission(true)
    let old = try records.previewBluetoothErase(a.device)
    var reading = try XCTUnwrap(records.load().current.first { $0.bluetoothReceipt?.device == a.device })
    reading.notes = "update after preview"
    reading.measuredAt = now.addingTimeInterval(120)
    try records.write(reading)
    XCTAssertThrowsError(try records.eraseBluetoothHistory(old))
    let latest = try XCTUnwrap(records.load().current.first { $0.id == reading.id })
    let draft = GalaxySSIHealthDraft(existing: latest)
    try records.storeDraft(draft)
    let beforeLink = try records.previewBluetoothErase(a.device)
    let original = GalaxySSIHealthOriginalStore.Original(id: UUID(), name: "fixture.pdf", kind: .pdf,
      fileExtension: "pdf", importedAt: now, bytes: 1, sha256: String(repeating: "a", count: 64))
    let source = GalaxySSIHealthReportReview.Source(original: original.id, sha256: original.sha256,
      page: 0, region: 0, fromOCR: true)
    var reported = latest
    reported.bluetoothReceipt = nil
    reported.reportSource = source
    let item = GalaxySSIHealthReportReview.Item(version: UUID(), source: source, excerpt: "fixture", reading: reported)
    try records.stageReportItem(item, replacing: nil)
    let target = GalaxySSIHealthReportReview.Target(record: latest.id, revision: latest.revision)
    try records.linkReportDuplicates([item.version: target], original: original)
    XCTAssertThrowsError(try records.eraseBluetoothHistory(beforeLink))
    let plan = try records.previewBluetoothErase(a.device)
    XCTAssertEqual(plan.count, 1)
    XCTAssertEqual(plan.versions.count, 2)
    XCTAssertEqual(plan.start, now)
    XCTAssertEqual(plan.end, reading.measuredAt)
    XCTAssertEqual(plan.reportLinks.map(\.target), [target])
    XCTAssertEqual(try records.eraseBluetoothHistory(plan), 1)
    let archive = try records.load()
    XCTAssertEqual(archive.revisions.compactMap { $0.bluetoothReceipt?.device }, [b.device])
    XCTAssertTrue(archive.reportEvidence?.isEmpty == true)
    XCTAssertNil(archive.draft)
    XCTAssertEqual(archive.bluetoothErasureLog?.last?.records, 1)
    XCTAssertThrowsError(try records.storeDraft(draft))
    XCTAssertThrowsError(try records.write(latest))
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
    XCTAssertEqual(device.readings.map(\.id), [sameName[0].id])
    XCTAssertEqual(device.latest?.measuredAt, now.addingTimeInterval(-60))
    XCTAssertEqual(device.latest?.bluetoothReceipt?.receivedAt, now)
    XCTAssertEqual(Set(history.devices.map(\.ordinal)).count, 34)
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
  func testReportDuplicateEvidenceUsesExactRevisionAndAtomicConsent() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let original = GalaxySSIHealthOriginalStore.Original(id: UUID(), name: "fixture.pdf", kind: .pdf,
      fileExtension: "pdf", importedAt: Date(), bytes: 1, sha256: String(repeating: "a", count: 64))
    let date = Date()
    try records.write(.init(metric: .weight, measuredAt: date, value: 65))
    func item(_ page: Int) -> GalaxySSIHealthReportReview.Item {
      let source = GalaxySSIHealthReportReview.Source(original: original.id, sha256: original.sha256,
        page: page, region: 0, fromOCR: true)
      return .init(version: UUID(), source: source, excerpt: "fixture",
        reading: .init(metric: .weight, measuredAt: date, value: 65, reportSource: source))
    }
    let first = item(0), second = item(1)
    try records.stageReportItem(first, replacing: nil)
    try records.stageReportItem(second, replacing: nil)
    let target = try XCTUnwrap(GalaxySSIHealthReportReview.exactTarget(for: first, current: records.load().current))
    let stale = GalaxySSIHealthReportReview.Target(record: target.record, revision: target.revision + 1)
    XCTAssertThrowsError(try records.linkReportDuplicates([first.version: target, second.version: stale], original: original))
    XCTAssertNil(try records.load().reportEvidence)
    XCTAssertEqual(try records.load().reportReview?.count, 2)
    try records.linkReportDuplicates([first.version: target], original: original)
    var edited = try XCTUnwrap(records.load().current.first)
    edited.notes = "later"
    try records.write(edited)
    XCTAssertThrowsError(try records.linkReportDuplicates([second.version: target], original: original))
    let archive = try records.load()
    let links = GalaxySSIHealthReportReview.linked(original: original, revisions: archive.revisions,
      current: archive.current, evidence: archive.reportEvidence ?? [])
    XCTAssertEqual(links.first?.reading.revision, target.revision)
    XCTAssertTrue(links.first?.secondary == true)
    XCTAssertEqual(archive.current.count, 1)
  }

  @MainActor
  func testReviewReminderActionsDoNotConfirmAndTableCommitClearsDraft() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let now = Date()
    let data = Data("value,time\n60,2025-01-01T12:00:00Z\n".utf8)
    let mapping = GalaxySSIHealthTableImport.Mapping(metric: .weight, value: 0, date: 1, confirmedUnit: true)
    let draft = GalaxySSIHealthReviewReminders.TableDraft(id: UUID(), name: "fixture.csv", at: now,
      data: data, mapping: mapping, worksheet: nil)
    try records.saveTableReview(draft, replacing: nil)
    try records.setReviewRemindersEnabled(true)
    var archive = try records.load()
    let job = try XCTUnwrap(GalaxySSIHealthReviewReminders.jobs(in: archive).first)
    try records.updateReviewReminder(job, action: .snoozed(now.addingTimeInterval(60)))
    archive = try records.load()
    let state = try XCTUnwrap(archive.reviewReminderState)
    XCTAssertTrue(GalaxySSIHealthReviewReminders.visible([job], state: state, now: now).isEmpty)
    XCTAssertEqual(GalaxySSIHealthReviewReminders.visible([job], state: state, now: now.addingTimeInterval(61)), [job])
    try records.updateReviewReminder(job, action: .handled)
    XCTAssertTrue(try records.load().current.isEmpty)
    XCTAssertEqual(try records.load().tableReview?.id, draft.id)
    XCTAssertEqual(try records.importTable(data, name: draft.name, json: false, mapping: mapping,
                                           expected: [.ready], reviewID: draft.id), 1)
    XCTAssertTrue(GalaxySSIHealthReviewReminders.jobs(in: try records.load()).isEmpty)
    XCTAssertThrowsError(try records.updateReviewReminder(job, action: .handled))
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
  func testProfileBackgroundSelectionPinsEntriesAndAuditsOnlyCount() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: file)
      try? FileManager.default.removeItem(at: file.appendingPathExtension("profile"))
    }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let selected = GalaxySSIHealthProfile.Background(kind: .history, title: "private-selected-fixture", notes: "private-note")
    let other = GalaxySSIHealthProfile.Background(kind: .allergy, title: "unselected-fixture", notes: "")
    var profile = GalaxySSIHealthProfile()
    profile.background = [selected, other]
    try records.writeProfile(profile)
    try records.setOverviewPermission(true)
    try records.setProfileAnalysisAllowed(true)
    profile = try records.loadProfile()
    let version = try XCTUnwrap(profile.backgroundVersion(profile.background[0]))
    let selection = [selected.id: version]
    let snapshot = try XCTUnwrap(records.captureProfileAnalysis([], background: selection))
    XCTAssertEqual(snapshot.background.map(\.id), [selected.id])
    XCTAssertEqual(try records.load().profileAnalysisAudit?.last?.backgroundCount, 1)
    profile.background[1].title = "changed unrelated entry"
    try records.writeProfile(profile)
    XCTAssertTrue(try snapshot.isCurrent(profile: records.loadProfile(), permission: records.load().profileAnalysisPermission))
    profile = try records.loadProfile()
    profile.background.removeFirst()
    try records.writeProfile(profile)
    XCTAssertThrowsError(try records.captureProfileAnalysis([], background: selection))
    XCTAssertFalse(try snapshot.isCurrent(profile: records.loadProfile(), permission: records.load().profileAnalysisPermission))
    let scope = GalaxySSIHealthAnalysis.Scope(interval: DateInterval(start: Date(), duration: 60), metrics: [.weight])
    let data = try GalaxySSIHealthAnalysis(scope: scope, current: [], calendar: .current).requestJSON()
    XCTAssertNil(data.range(of: Data(selected.title.utf8)))
    XCTAssertNil(data.range(of: Data(selected.notes.utf8)))
  }

  @MainActor
  func testProfileAnalysisBindsOnlySelectedFieldsAndPermission() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: file)
      try? FileManager.default.removeItem(at: file.appendingPathExtension("profile"))
    }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    var profile = try records.loadProfile()
    profile.height = 170
    profile.context = "private fixture"
    try records.writeProfile(profile)
    try records.setOverviewPermission(true)
    XCTAssertThrowsError(try records.captureProfileAnalysis([.height]))
    try records.setProfileAnalysisAllowed(true)
    let snapshot = try XCTUnwrap(records.captureProfileAnalysis([.height, .birthDate]))
    XCTAssertEqual(snapshot.values[.height], .height(170, .cm))
    XCTAssertNil(snapshot.values[.context])
    XCTAssertNil(snapshot.values[.birthDate])
    profile = try records.loadProfile()
    profile.context = "unrelated update"
    try records.writeProfile(profile)
    XCTAssertTrue(try snapshot.isCurrent(profile: records.loadProfile(), permission: records.load().profileAnalysisPermission))
    profile = try records.loadProfile()
    profile.height = 171
    try records.writeProfile(profile)
    XCTAssertFalse(try snapshot.isCurrent(profile: records.loadProfile(), permission: records.load().profileAnalysisPermission))
    profile = try records.loadProfile()
    profile.height = 170
    try records.writeProfile(profile)
    XCTAssertFalse(try snapshot.isCurrent(profile: records.loadProfile(), permission: records.load().profileAnalysisPermission))
    let latest = try XCTUnwrap(records.captureProfileAnalysis([.height]))
    try records.setProfileAnalysisAllowed(false)
    try records.setProfileAnalysisAllowed(true)
    XCTAssertFalse(try latest.isCurrent(profile: records.loadProfile(), permission: records.load().profileAnalysisPermission))
    XCTAssertEqual(try records.load().profileAnalysisAudit?.first?.fields, [.height, .birthDate])
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
  func testWeeklyReportLinkPinsHistoricalCalendarAndComparisonRevisions() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
    let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: start))
    let prior = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: start))
    let recent = GalaxySSIHealthReading(revision: 1, metric: .weight, measuredAt: start, value: 65)
    var baseline = GalaxySSIHealthReading(revision: 1, metric: .weight, measuredAt: prior, value: 66)
    let other = GalaxySSIHealthReading(revision: 1, metric: .glucose, measuredAt: start, value: 6)
    let link = GalaxySSIWeeklyHealthReport.Link(interval: DateInterval(start: start, end: end),
      metrics: [.weight], calendar: calendar, compare: true, current: [recent, baseline, other])
    XCTAssertEqual(link.calendar.timeZone.identifier, "America/New_York")
    XCTAssertEqual(link.comparison?.end, start)
    XCTAssertTrue(link.isCurrent([baseline, recent]))
    let report = GalaxySSIWeeklyHealthReport(current: [recent, baseline, other], interval: link.interval,
      metrics: link.metrics, through: end, comparison: link.comparison)
    XCTAssertEqual(report.readings.map(\.id), [recent.id])
    XCTAssertEqual(report.comparisonReadings.map(\.id), [baseline.id])
    baseline.revision += 1
    XCTAssertFalse(link.isCurrent([recent, baseline]))
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

  func testTrendHealthOriginsKeepExactApplicationsAndDailyAggregatesSeparate() throws {
    let now = Date()
    let applications = (0..<35).map { index in
      GalaxySSIHealthReading(revision: index + 1, metric: .steps, measuredAt: now, value: Decimal(index + 1),
        healthKitSource: .init(key: String(index), origin: "fixture.\(index)", name: "Same name"))
    }
    let daily = GalaxySSIHealthReading(revision: 1, metric: .steps, measuredAt: now, value: 100,
      healthKitSource: .init(key: "daily", origin: nil, name: nil))
    let manual = GalaxySSIHealthReading(metric: .steps, measuredAt: now, value: 200)
    let current = applications + [daily, manual]
    let options = GalaxySSIHealthTrend.origins(in: current, metric: .steps)
    XCTAssertEqual(options.count, 36)
    XCTAssertEqual(options.last?.id, .dailySteps)
    func trend(_ origin: GalaxySSIHealthTrend.HealthOrigin) -> GalaxySSIHealthTrend {
      GalaxySSIHealthTrend(current: current, metric: .steps, component: .value, now: now,
        dayCount: 7, calendar: .current, source: .healthKit, healthOrigin: origin)
    }
    let app = try XCTUnwrap(trend(.application("fixture.34")).points.last)
    XCTAssertEqual(app.readings.map(\.id), [applications[34].id])
    XCTAssertEqual(app.revisions[applications[34].id], 35)
    XCTAssertEqual(trend(.dailySteps).points.last?.readings.map(\.id), [daily.id])
    XCTAssertEqual(trend(.application("fixture")).validDays, 0)
    XCTAssertFalse(GalaxySSIHealthTrend.Source.manual.includes(daily))
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
