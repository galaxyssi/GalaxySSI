import Foundation
import UIKit
import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthPhotoPaperHintTests: XCTestCase {
  @MainActor
  func testLegacyEntryRemainsUncheckedAndCheckedWithoutEdgesSurvivesCoding() throws {
    let original = original()
    let legacy = GalaxySSIHealthPhotoDraft.Entry(id: UUID(), original: original, hints: [])
    let data = try JSONEncoder().encode(legacy)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "paper")
    let decoded = try JSONDecoder().decode(GalaxySSIHealthPhotoDraft.Entry.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNil(decoded.validatedPaper)
    var checked = legacy
    checked.paper = .init(sha256: original.sha256, bounds: nil)
    let reopened = try JSONDecoder().decode(GalaxySSIHealthPhotoDraft.Entry.self, from: JSONEncoder().encode(checked))
    XCTAssertNotNil(reopened.validatedPaper)
    XCTAssertNil(reopened.validatedPaper?.bounds)
  }

  func testMalformedAndNonfiniteBoundsAreRejectedWithoutClamping() {
    let hash = String(repeating: "a", count: 64)
    for bounds in [CGRect(x: -0.1, y: 0.1, width: 0.7, height: 0.7),
                   CGRect(x: 0.1, y: 0.1, width: 1.0, height: 0.7),
                   CGRect(x: 0.1, y: 0.1, width: 0, height: 0.7),
                   CGRect(x: CGFloat.nan, y: 0.1, width: 0.7, height: 0.7)] {
      XCTAssertFalse(GalaxySSIHealthPhotoDraft.PaperHint(sha256: hash, bounds: bounds).isValid)
    }
    XCTAssertFalse(GalaxySSIHealthPhotoDraft.PaperHint(sha256: "bad", bounds: nil).isValid)
    XCTAssertTrue(GalaxySSIHealthPhotoDraft.PaperHint(sha256: hash, bounds: bounds()).isValid)
  }

  @MainActor
  func testForeignHintAndDeviceModeCannotMutateTheDraft() throws {
    let original = original()
    let foreign = GalaxySSIHealthPhotoDraft.PaperHint(sha256: String(repeating: "b", count: 64), bounds: bounds())
    var report = GalaxySSIHealthPhotoDraft.Batch(mode: .report)
    let before = report
    XCTAssertThrowsError(try report.install(original, hints: [], replacing: nil, paper: foreign))
    XCTAssertEqual(report, before)
    var device = GalaxySSIHealthPhotoDraft.Batch(mode: .device)
    let deviceBefore = device
    XCTAssertThrowsError(try device.install(original, hints: [], replacing: nil,
      paper: .init(sha256: original.sha256, bounds: bounds())))
    XCTAssertEqual(device, deviceBefore)
    let entry = GalaxySSIHealthPhotoDraft.Entry(id: UUID(), original: original, hints: [], paper: foreign)
    XCTAssertNil(entry.validatedPaper)
  }

  @MainActor
  func testReorderingPreservesBindingsAndRetakeDoesNotReuseOldBounds() throws {
    let first = original(), second = original(hash: String(repeating: "b", count: 64))
    var batch = GalaxySSIHealthPhotoDraft.Batch(mode: .report)
    try batch.install(first, hints: [], replacing: nil, paper: .init(sha256: first.sha256, bounds: bounds()))
    let page = try XCTUnwrap(batch.pages.first)
    try batch.install(second, hints: [], replacing: nil)
    try batch.edit(page.id, offset: 1)
    XCTAssertEqual(batch.pages.last?.validatedPaper?.bounds, bounds())
    let version = batch.version
    try batch.install(original(hash: String(repeating: "c", count: 64)), hints: [], replacing: page.id)
    XCTAssertNotEqual(batch.version, version)
    XCTAssertEqual(batch.pages.last?.id, page.id)
    XCTAssertNil(batch.pages.last?.validatedPaper)
  }

  @MainActor
  func testHintPersistsWithTheEncryptedPageAndWrongHashDoesNotCommit() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = PaperHintSecrets(), file = root.appendingPathComponent("records")
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: root, restoreRecordsFile: file)
    let data = image()
    let hint = GalaxySSIHealthPhotoDraft.PaperHint(sha256: GalaxySSIHealthLinkedExport.digest(data), bounds: bounds())
    try store.storePhotoCapturePage(data, name: "synthetic.png", acquisition: .uploaded, mode: .report,
      expected: nil, replacing: nil, paper: hint, hints: [])
    let batch = try XCTUnwrap(records.load().photoCaptureDraft)
    XCTAssertEqual(batch.pages.first?.validatedPaper, hint)
    let reopened = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    XCTAssertEqual(try reopened.load().photoCaptureDraft?.pages.first?.validatedPaper, hint)
    let foreign = GalaxySSIHealthPhotoDraft.PaperHint(sha256: String(repeating: "b", count: 64), bounds: bounds())
    XCTAssertThrowsError(try store.storePhotoCapturePage(data, name: "synthetic.png", acquisition: .uploaded, mode: .report,
      expected: batch.version, replacing: batch.pages.first?.id, paper: foreign, hints: []))
    XCTAssertEqual(try records.load().photoCaptureDraft, batch)
  }

  @MainActor
  func testDeviceInspectionDoesNotProducePaperHints() throws {
    let inspection = try GalaxySSIHealthPhotoDraft.inspectCapture(image(), mode: .device)
    XCTAssertNil(inspection.paper)
  }

  private func bounds() -> CGRect { CGRect(x: 0.1, y: 0.15, width: 0.7, height: 0.65) }
  @MainActor
  private func original(hash: String = String(repeating: "a", count: 64)) -> GalaxySSIHealthOriginalStore.Original {
    .init(id: UUID(), name: "synthetic.png", kind: .image, fileExtension: "png", importedAt: Date(), bytes: 100, sha256: hash)
  }
  @MainActor
  private func image() -> Data {
    UIGraphicsImageRenderer(size: CGSize(width: 100, height: 120)).pngData { context in
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 100, height: 120))
      UIColor.black.setFill()
      context.fill(CGRect(x: 20, y: 30, width: 60, height: 8))
    }
  }
}

private final class PaperHintSecrets: GalaxySSISecretStore {
  private var values: [String: String] = [:]
  func setString(_ value: String, account: String) throws { values[account] = value }
  func string(account: String) -> String? { values[account] }
  func delete(account: String) { values.removeValue(forKey: account) }
}
