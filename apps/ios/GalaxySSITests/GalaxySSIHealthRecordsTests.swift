import Foundation
import UIKit
import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthRecordsTests: XCTestCase {
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
