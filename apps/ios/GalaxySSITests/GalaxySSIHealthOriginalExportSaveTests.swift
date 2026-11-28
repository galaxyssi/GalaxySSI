import Foundation
import UIKit
import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthOriginalExportSaveTests: XCTestCase {
  @MainActor
  func testLegacyExportsDoNotInventSaveReceiptsOrVerifiedTimes() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let entry = try fixture.prepared()
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
    object.removeValue(forKey: "latestSave")
    object.removeValue(forKey: "lastVerifiedAt")
    let legacy = try JSONDecoder().decode(GalaxySSIHealthOriginalStore.ExportAttempt.self,
      from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNil(legacy.latestSave)
    XCTAssertNil(legacy.lastVerifiedAt)
  }

  @MainActor
  func testResaveFailurePreservesPriorVerifiedTimeAndRejectsOldCompletion() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let prepared = try fixture.prepared()
    let (_, first) = try fixture.store.beginExportSave(prepared)
    try fixture.store.finishExportSave(first, verified: true)
    let saved = try XCTUnwrap(fixture.store.exportHistory().first)
    let verifiedAt = try XCTUnwrap(saved.lastVerifiedAt)
    let (_, next) = try fixture.store.beginExportSave(saved)
    XCTAssertNotEqual(first.token, next.token)
    XCTAssertThrowsError(try fixture.store.finishExportSave(first, verified: true))
    XCTAssertEqual(try fixture.store.exportHistory().first?.latestSave?.id, next.token)
    XCTAssertTrue(GalaxySSIHealthOriginalExportSave.isActive(next.token, scope: next.scope))
    try fixture.store.finishExportSave(next, verified: false)
    let final = try XCTUnwrap(fixture.store.exportHistory().first)
    XCTAssertEqual(final.outcome, .verified)
    XCTAssertEqual(final.lastVerifiedAt, verifiedAt)
    XCTAssertEqual(final.latestSave?.outcome, .unverified)
    XCTAssertEqual(try fixture.store.readShareArtifact(final), try fixture.store.readShareArtifact(prepared))
  }

  @MainActor
  func testRecoveryPreservesLiveSavesAndInterruptsOnlyLostLifetimes() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let prepared = try fixture.prepared()
    var request: GalaxySSIHealthOriginalExportSave.Request? = try fixture.store.beginExportSave(prepared).1
    let token = try XCTUnwrap(request?.token)
    try withExtendedLifetime(request) {
      try fixture.store.recoverExportSaves()
      XCTAssertEqual(try fixture.store.exportHistory().first?.latestSave?.outcome, .pending)
      XCTAssertThrowsError(try fixture.store.beginExportSave(prepared))
    }
    request = nil
    try fixture.store.recoverExportSaves()
    let reopened = try XCTUnwrap(fixture.store.exportHistory().first)
    XCTAssertEqual(reopened.latestSave?.id, token)
    XCTAssertEqual(reopened.latestSave?.outcome, .interrupted)
    XCTAssertNil(reopened.lastVerifiedAt)
    let (_, retry) = try fixture.store.beginExportSave(reopened)
    try fixture.store.interruptExportSave(retry)
    XCTAssertEqual(try fixture.store.exportHistory().first?.latestSave?.outcome, .interrupted)
  }

  @MainActor
  func testForeignOwnerOrDatasetCannotFinishOrReleaseTheLiveRequest() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let (_, request) = try fixture.store.beginExportSave(fixture.prepared())
    let foreignOwner = GalaxySSIHealthOriginalStore(owner: "other", secrets: fixture.secrets,
      fixtureDirectory: fixture.root, restoreRecordsFile: fixture.recordsFile)
    let foreignDataset = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: fixture.secrets,
      fixtureDirectory: fixture.root, restoreRecordsFile: fixture.root.appendingPathComponent("other-records"))
    XCTAssertThrowsError(try foreignOwner.finishExportSave(request, verified: true))
    XCTAssertThrowsError(try foreignDataset.finishExportSave(request, verified: true))
    XCTAssertTrue(GalaxySSIHealthOriginalExportSave.isActive(request.token, scope: request.scope))
    XCTAssertNil(try fixture.store.exportHistory().first?.lastVerifiedAt)
    try fixture.store.interruptExportSave(request)
  }

  @MainActor
  func testChangedManifestCannotBeginAndLegacyCallbackCannotBypassToken() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let prepared = try fixture.prepared()
    let changed = GalaxySSIHealthOriginalStore.ExportAttempt(id: prepared.id, at: prepared.at.addingTimeInterval(1),
      originals: prepared.originals, bytes: prepared.bytes, sha256: prepared.sha256, outcome: prepared.outcome)
    XCTAssertThrowsError(try fixture.store.beginExportSave(changed))
    XCTAssertNil(try fixture.store.exportHistory().first?.latestSave)
    let (_, request) = try fixture.store.beginExportSave(prepared)
    XCTAssertThrowsError(try fixture.store.finishExport(id: prepared.id, verified: true))
    XCTAssertEqual(try fixture.store.exportHistory().first?.latestSave?.outcome, .pending)
    try fixture.store.interruptExportSave(request)
  }

  @MainActor
  func testDestinationVerificationUsesFrozenArchiveBytesAndHash() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let (data, request) = try fixture.store.beginExportSave(fixture.prepared())
    let url = fixture.root.appendingPathComponent("saved.zip")
    try data.write(to: url)
    XCTAssertTrue(try GalaxySSIHealthOriginalStore.verifyDestination(url, for: request.export))
    try (data + Data([0])).write(to: url)
    let verified = try GalaxySSIHealthOriginalStore.verifyDestination(url, for: request.export)
    XCTAssertFalse(verified)
    try fixture.store.finishExportSave(request, verified: verified)
    XCTAssertEqual(try fixture.store.exportHistory().first?.latestSave?.outcome, .unverified)
    XCTAssertNil(try fixture.store.exportHistory().first?.lastVerifiedAt)
  }

  @MainActor
  private struct Fixture {
    let root: URL
    let recordsFile: URL
    let secrets: SaveSecrets
    let store: GalaxySSIHealthOriginalStore
    init() throws {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let recordsFile = root.appendingPathComponent("records"), secrets = SaveSecrets()
      let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: root, restoreRecordsFile: recordsFile)
      let data = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 100)).pngData { context in
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 100))
      }
      try store.store(data, name: "synthetic.png")
      self.root = root; self.recordsFile = recordsFile; self.secrets = secrets; self.store = store
    }
    func prepared() throws -> GalaxySSIHealthOriginalStore.ExportAttempt {
      try store.prepareExport(store.list().originals).1
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
  }
}

private final class SaveSecrets: GalaxySSISecretStore {
  private var values: [String: String] = [:]
  func setString(_ value: String, account: String) throws { values[account] = value }
  func string(account: String) -> String? { values[account] }
  func delete(account: String) { values.removeValue(forKey: account) }
}
