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
    let fresh = try GalaxySSIHealthPortableBackup.previewRestore(input, records: fixture.target, originals: fixture.targetStore)
    try GalaxySSIHealthPortableBackup.restore(input, expected: fresh, records: fixture.target,
      originals: fixture.targetStore, replacing: [fixture.second.id])
    archive = try fixture.target.load()
    XCTAssertEqual(Set(archive.reportEvidence?.map(\.target.record) ?? []), Set([fixture.first.id, fixture.second.id]))
    XCTAssertEqual(Set(archive.tableEvidence?.map(\.target.record) ?? []), Set([fixture.first.id, fixture.second.id]))
    XCTAssertEqual(archive.reportEvidence?.count, 2)
    XCTAssertEqual(archive.tableEvidence?.count, 2)
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
