import Foundation
import UIKit
import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthRestoreConflictSourceTests: XCTestCase {
  @MainActor
  func testOnlySelectedConflictGetsSecondarySourcesAtItsNewRevision() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let input = try fixture.input()
    let preview = try GalaxySSIHealthPortableBackup.previewRestore(input, records: fixture.target, originals: fixture.targetStore)
    try GalaxySSIHealthPortableBackup.restore(input, expected: preview, records: fixture.target,
      originals: fixture.targetStore, replacing: [fixture.first.id])
    var archive = try fixture.target.load()
    XCTAssertEqual(archive.current.first { $0.id == fixture.first.id }?.revision, 2)
    XCTAssertEqual(archive.current.first { $0.id == fixture.second.id }?.value, 76)
    XCTAssertEqual(archive.reportEvidence?.map(\.target.record), [fixture.first.id])
    XCTAssertEqual(archive.reportEvidence?.first?.target.revision, 2)
    XCTAssertEqual(archive.tableEvidence?.map(\.target.record), [fixture.first.id])
    XCTAssertEqual(archive.tableEvidence?.first?.target.revision, 2)
    XCTAssertEqual(archive.tableEvidence?.first?.source.dateOnlyDecision?.chosenMinute, 480)
    XCTAssertEqual(archive.tableEvidence?.first?.source.excelDate1904, false)
    let firstReceipt = try XCTUnwrap(archive.restoreHistory?.first)
    XCTAssertEqual(firstReceipt.counts.readings, 2)
    XCTAssertEqual(firstReceipt.counts.replaced, 1)
    XCTAssertEqual(firstReceipt.counts.conflicts, 1)
    XCTAssertEqual(firstReceipt.counts.sourcesAdded, 2)
    XCTAssertEqual(firstReceipt.counts.sourcesSkipped, 2)
    XCTAssertEqual(firstReceipt.counts.originalsAdded, 1)
    XCTAssertEqual(firstReceipt.counts.tablesAdded, 1)
    XCTAssertTrue(archive.restoreReceipts?.contains(firstReceipt.id) == true)
    let fresh = try GalaxySSIHealthPortableBackup.previewRestore(input, records: fixture.target, originals: fixture.targetStore)
    try GalaxySSIHealthPortableBackup.restore(input, expected: fresh, records: fixture.target,
      originals: fixture.targetStore, replacing: [fixture.second.id])
    archive = try fixture.target.load()
    XCTAssertEqual(Set(archive.reportEvidence?.map(\.target.record) ?? []), Set([fixture.first.id, fixture.second.id]))
    XCTAssertEqual(Set(archive.tableEvidence?.map(\.target.record) ?? []), Set([fixture.first.id, fixture.second.id]))
    XCTAssertEqual(archive.reportEvidence?.count, 2)
    XCTAssertEqual(archive.tableEvidence?.count, 2)
    XCTAssertEqual(archive.restoreHistory?.count, 2)
    let secondReceipt = try XCTUnwrap(archive.restoreHistory?.first)
    XCTAssertEqual(secondReceipt.counts.duplicates, 1)
    XCTAssertEqual(secondReceipt.counts.replaced, 1)
    XCTAssertEqual(secondReceipt.counts.conflicts, 0)
    XCTAssertEqual(secondReceipt.counts.sourcesAdded, 2)
    XCTAssertEqual(secondReceipt.counts.sourcesReused, 2)
    XCTAssertEqual(secondReceipt.counts.sourcesSkipped, 0)
    XCTAssertEqual(secondReceipt.counts.originalsReused, 1)
  }

  @MainActor
  func testSelectedConflictMapsVerifiedExistingReportAndTableAliases() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    try fixture.targetStore.store(fixture.sourceStore.read(fixture.report), name: "alias.pdf")
    let alias = try XCTUnwrap(fixture.targetStore.list().originals.first)
    let tableAlias = GalaxySSIHealthTableImport.Batch(id: UUID(), name: "alias.csv", at: Date(),
      data: fixture.table.data, inserted: 0, undone: nil)
    var archive = try fixture.target.load()
    archive.tableBatches = [tableAlias]
    try fixture.target.persistQuickReport(archive)
    XCTAssertNil(try fixture.target.load().restoreHistory)
    let input = try fixture.input()
    let preview = try GalaxySSIHealthPortableBackup.previewRestore(input, records: fixture.target, originals: fixture.targetStore)
    XCTAssertEqual(preview.originals, 0)
    XCTAssertEqual(preview.tables, 0)
    try GalaxySSIHealthPortableBackup.restore(input, expected: preview, records: fixture.target,
      originals: fixture.targetStore, replacing: [fixture.first.id])
    archive = try fixture.target.load()
    XCTAssertEqual(archive.reportEvidence?.first?.source.original, alias.id)
    XCTAssertEqual(archive.tableEvidence?.first?.source.batch, tableAlias.id)
    XCTAssertEqual(archive.tableBatches?.count, 1)
    XCTAssertEqual(archive.reportEvidence?.first?.target.revision, 2)
    XCTAssertEqual(archive.tableEvidence?.first?.target.revision, 2)
    XCTAssertEqual(archive.tableEvidence?.first?.source.dateOnlyDecision?.resolvedTime, fixture.first.measuredAt)
    XCTAssertEqual(archive.tableEvidence?.first?.source.excelDate1904, false)
    XCTAssertEqual(archive.restoreHistory?.first?.counts.originalsReused, 1)
    XCTAssertEqual(archive.restoreHistory?.first?.counts.originalsAdded, 0)
  }

  @MainActor
  func testOccupiedSecondarySourceSlotsCannotMoveToASelectedConflict() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    try fixture.targetStore.store(fixture.sourceStore.read(fixture.report), name: "existing.pdf")
    let original = try XCTUnwrap(fixture.targetStore.list().originals.first)
    let foreign = GalaxySSIHealthReading(metric: .weight, value: 99)
    try fixture.target.write(foreign)
    var archive = try fixture.target.load()
    archive.tableBatches = [fixture.table]
    archive.reportEvidence = [.init(target: .init(record: foreign.id, revision: 1),
      source: .init(original: original.id, sha256: original.sha256, page: 1, region: 10, fromOCR: true), excerpt: "Synthetic foreign owner")]
    archive.tableEvidence = [.init(target: .init(record: foreign.id, revision: 1),
      source: .init(batch: fixture.table.id, row: 2, sha256: GalaxySSIHealthLinkedExport.digest(fixture.table.data)))]
    try fixture.target.persistQuickReport(archive)
    let input = try fixture.input()
    let preview = try GalaxySSIHealthPortableBackup.previewRestore(input, records: fixture.target, originals: fixture.targetStore)
    try GalaxySSIHealthPortableBackup.restore(input, expected: preview, records: fixture.target,
      originals: fixture.targetStore, replacing: [fixture.first.id])
    archive = try fixture.target.load()
    XCTAssertEqual(archive.current.first { $0.id == fixture.first.id }?.revision, 2)
    XCTAssertEqual(archive.reportEvidence?.map(\.target.record), [foreign.id])
    XCTAssertEqual(archive.tableEvidence?.map(\.target.record), [foreign.id])
    XCTAssertEqual(archive.restoreHistory?.first?.counts.sourcesSkipped, 4)
    XCTAssertEqual(archive.restoreHistory?.first?.counts.sourcesAdded, 0)
  }

  @MainActor
  func testChangedPreviewCannotAttachSourcesOrCommitAReplacement() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let input = try fixture.input()
    let preview = try GalaxySSIHealthPortableBackup.previewRestore(input, records: fixture.target, originals: fixture.targetStore)
    var changed = try XCTUnwrap(fixture.target.load().current.first { $0.id == fixture.first.id })
    changed.value = 77
    try fixture.target.write(changed)
    XCTAssertThrowsError(try GalaxySSIHealthPortableBackup.restore(input, expected: preview, records: fixture.target,
      originals: fixture.targetStore, replacing: [fixture.first.id]))
    let archive = try fixture.target.load()
    XCTAssertEqual(archive.current.first { $0.id == fixture.first.id }?.value, 77)
    XCTAssertTrue(archive.reportEvidence?.isEmpty ?? true)
    XCTAssertTrue(archive.tableEvidence?.isEmpty ?? true)
    XCTAssertTrue(archive.restoreReceipts?.isEmpty ?? true)
    XCTAssertNil(archive.restoreHistory)
  }

  func testReceiptBoundsRejectOverflowAndConservationFailures() throws {
    var counts = emptyCounts()
    XCTAssertTrue(counts.isValid)
    counts.added = Int.max
    XCTAssertFalse(counts.isValid)
    counts.added = -1
    XCTAssertFalse(counts.isValid)
    counts.added = 1
    XCTAssertFalse(counts.isValid)
    counts.readings = 1
    XCTAssertTrue(counts.isValid)
    let invalid = GalaxySSIHealthRestoreReceipt(id: UUID(), at: Date(), backupFingerprint: String(repeating: "a", count: 64),
      first: nil, last: nil, counts: counts)
    XCTAssertFalse(invalid.isValid)
  }

  func testReceiptHistoryIsBoundedWithoutPruningCommitAuthority() throws {
    var history: [GalaxySSIHealthRestoreReceipt] = []
    var committed = Set<UUID>()
    for index in 0..<105 {
      let receipt = GalaxySSIHealthRestoreReceipt(id: UUID(), at: Date(timeIntervalSince1970: Double(index)),
        backupFingerprint: String(repeating: "a", count: 64), first: nil, last: nil, counts: emptyCounts())
      history = try GalaxySSIHealthRestoreReceipt.recording(receipt, in: history, committed: committed)
      committed.insert(receipt.id)
    }
    XCTAssertEqual(history.count, 100)
    XCTAssertEqual(committed.count, 105)
    XCTAssertEqual(history.first?.at, Date(timeIntervalSince1970: 104))
    XCTAssertTrue(GalaxySSIHealthRestoreReceipt.validHistory(history, committed: committed))
    XCTAssertFalse(GalaxySSIHealthRestoreReceipt.validHistory(history, committed: []))
    XCTAssertThrowsError(try GalaxySSIHealthRestoreReceipt.recording(XCTUnwrap(history.first), in: history, committed: committed))
  }

  @MainActor
  func testInvalidDetailCannotCommitAndGenericStagingPreservesHistory() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let original = try fixture.target.load()
    let id = UUID()
    let receipt = GalaxySSIHealthRestoreReceipt(id: id, at: Date(), backupFingerprint: String(repeating: "a", count: 64),
      first: nil, last: nil, counts: emptyCounts())
    XCTAssertThrowsError(try fixture.target.commitRestore(original, receipt: UUID(), receiptDetail: receipt))
    XCTAssertNil(try fixture.target.load().restoreHistory)
    try fixture.target.commitRestore(original, receipt: id, receiptDetail: receipt)
    try fixture.target.commitRestore(original, receipt: UUID())
    let reopened = try fixture.target.load()
    XCTAssertEqual(reopened.restoreHistory, [receipt])
    XCTAssertTrue(reopened.restoreReceipts?.contains(id) == true)
    XCTAssertEqual(reopened.restoreReceipts?.count, 2)
    XCTAssertThrowsError(try fixture.target.commitRestore(reopened, receipt: id, receiptDetail: receipt))
  }

  private func emptyCounts() -> GalaxySSIHealthRestoreReceipt.Counts {
    .init(readings: 0, added: 0, duplicates: 0, conflicts: 0, replaced: 0,
      originals: 0, originalsAdded: 0, originalsReused: 0, originalsRepaired: 0, originalsUnavailable: 0,
      tablesAdded: 0, sources: 0, sourcesAdded: 0, sourcesReused: 0, sourcesSkipped: 0, missingReferences: 0)
  }

  @MainActor
  private struct Fixture {
    let root: URL
    let source: GalaxySSIHealthRecords
    let target: GalaxySSIHealthRecords
    let sourceStore: GalaxySSIHealthOriginalStore
    let targetStore: GalaxySSIHealthOriginalStore
    let report: GalaxySSIHealthOriginalStore.Original
    let table: GalaxySSIHealthTableImport.Batch
    let first: GalaxySSIHealthReading
    let second: GalaxySSIHealthReading

    init() throws {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      let sourceRoot = root.appendingPathComponent("source"), targetRoot = root.appendingPathComponent("target")
      try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
      let secrets = Secrets(), sourceFile = sourceRoot.appendingPathComponent("records"), targetFile = targetRoot.appendingPathComponent("records")
      let source = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: sourceFile)
      let target = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: targetFile)
      let sourceStore = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: sourceRoot, restoreRecordsFile: sourceFile)
      let targetStore = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: targetRoot, restoreRecordsFile: targetFile)
      let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
      try sourceStore.store(pdf, name: "synthetic.pdf")
      let report = try XCTUnwrap(sourceStore.list().originals.first)
      let first = GalaxySSIHealthReading(metric: .weight,
        measuredAt: try XCTUnwrap(ISO8601DateFormatter().date(from: "2023-11-14T08:00:00Z")), value: 60)
      let second = GalaxySSIHealthReading(metric: .weight, measuredAt: first.measuredAt.addingTimeInterval(60), value: 70)
      for reading in [first, second] {
        try source.write(reading)
        var local = reading
        local.value = (reading.value ?? 0) + 6
        try target.write(local)
      }
      let data = Data("value,time\n60,2023-11-14\n70,2023-11-14\n".utf8)
      let table = GalaxySSIHealthTableImport.Batch(id: UUID(), name: "synthetic.csv", at: Date(), data: data, inserted: 0, undone: nil)
      var archive = try source.load()
      archive.tableBatches = [table]
      archive.reportEvidence = [first, second].enumerated().map { index, reading in
        .init(target: .init(record: reading.id, revision: 1), source: .init(original: report.id, sha256: report.sha256,
          page: 1, region: 10 + index, fromOCR: true), excerpt: "Synthetic report")
      }
      archive.tableEvidence = [first, second].enumerated().map { index, reading in
        .init(target: .init(record: reading.id, revision: 1),
          source: .init(batch: table.id, row: 2 + index, sha256: GalaxySSIHealthLinkedExport.digest(data),
            dateOnlyDecision: .init(sourceDate: "2023-11-14", chosenMinute: 480 + index, resolvedTime: reading.measuredAt),
            excelDate1904: false))
      }
      try source.persistQuickReport(archive)
      self.root = root; self.source = source; self.target = target
      self.sourceStore = sourceStore; self.targetStore = targetStore
      self.report = report; self.table = table; self.first = first; self.second = second
    }

    func input() throws -> GalaxySSIHealthPortableBackup.RestoreInput {
      let plan = try GalaxySSIHealthPortableBackup.plan(records: source, originals: sourceStore)
      let (payload, _) = try GalaxySSIHealthPortableBackup.prepare(plan, records: source, originals: sourceStore)
      return try GalaxySSIHealthPortableBackup.unlock(GalaxySSIHealthPortableBackup.seal(payload, password: "fixture-password"), password: "fixture-password")
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
  }
}

private final class Secrets: GalaxySSISecretStore {
  private var values: [String: String] = [:]
  func setString(_ value: String, account: String) throws { values[account] = value }
  func string(account: String) -> String? { values[account] }
  func delete(account: String) { values.removeValue(forKey: account) }
}
