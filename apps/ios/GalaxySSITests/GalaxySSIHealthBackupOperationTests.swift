import Foundation
import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthBackupOperationTests: XCTestCase {
  @MainActor
  func testLegacyEntryHasNoInventedOperationTokens() throws {
    let entry = GalaxySSIHealthBackupHistory.Entry(id: UUID(), at: Date())
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
    object.removeValue(forKey: "generationToken"); object.removeValue(forKey: "saveToken")
    let reopened = try JSONDecoder().decode(GalaxySSIHealthBackupHistory.Entry.self,
      from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNil(reopened.generationToken)
    XCTAssertNil(reopened.saveToken)
    XCTAssertNil(reopened.lastVerifiedAt)
  }

  @MainActor
  func testRecoveryPreservesLiveGenerationAndLegacyPublishCannotBypassIt() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let request = try fixture.history.beginGeneration()
    try withExtendedLifetime(request) {
      try fixture.history.recover()
      XCTAssertEqual(try fixture.history.entries().first?.generation, .pending)
      XCTAssertThrowsError(try fixture.history.publish(fixture.data, id: request.entry.id))
      XCTAssertThrowsError(try fixture.history.finishSave(request, verified: true))
      XCTAssertTrue(GalaxySSIHealthBackupOperation.owns(request))
    }
    try fixture.history.publish(fixture.data, request: request)
    XCTAssertEqual(try fixture.history.entries().first?.generation, .ready)
    XCTAssertFalse(GalaxySSIHealthBackupOperation.owns(request))
    let cancelled = try fixture.history.beginGeneration()
    GalaxySSIHealthBackupOperation.release(cancelled)
    try fixture.history.recover()
    XCTAssertEqual(try fixture.history.entries().first?.generation, .interrupted)
    XCTAssertThrowsError(try fixture.history.publish(fixture.data, request: cancelled))
  }

  @MainActor
  func testOldCallbackCannotFinishNewSaveAndFailurePreservesVerifiedTime() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let entry = try fixture.ready()
    let (_, first) = try fixture.history.prepareSave(entry)
    try fixture.history.finishSave(first, verified: true)
    let saved = try XCTUnwrap(fixture.history.entries().first)
    let at = try XCTUnwrap(saved.lastVerifiedAt)
    let (_, next) = try fixture.history.prepareSave(saved)
    XCTAssertNotEqual(first.token, next.token)
    XCTAssertThrowsError(try fixture.history.finishSave(first, verified: true))
    XCTAssertThrowsError(try fixture.history.finishSave(entry.id, verified: true))
    XCTAssertTrue(fixture.history.isSaving(next.entry))
    XCTAssertEqual(try fixture.history.entries().first?.saveToken, next.token)
    try fixture.history.finishSave(next, verified: false)
    XCTAssertEqual(try fixture.history.entries().first?.latestSave, .unverified)
    XCTAssertEqual(try fixture.history.entries().first?.lastVerifiedAt, at)
  }

  @MainActor
  func testRecoveryPreservesLiveSaveThenMarksLostRequestInterrupted() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let entry = try fixture.ready()
    var request: GalaxySSIHealthBackupOperation.Request? = try fixture.history.prepareSave(entry).1
    try withExtendedLifetime(request) {
      try fixture.history.recover()
      XCTAssertEqual(try fixture.history.entries().first?.latestSave, .pending)
      XCTAssertThrowsError(try fixture.history.prepareSave(entry))
    }
    request = nil
    try fixture.history.recover()
    let recovered = try XCTUnwrap(fixture.history.entries().first)
    XCTAssertEqual(recovered.latestSave, .interrupted)
    XCTAssertNil(recovered.lastVerifiedAt)
    let (_, retry) = try fixture.history.prepareSave(recovered)
    try fixture.history.finishSave(retry, verified: false)
  }

  @MainActor
  func testForeignScopeOrForgedRequestCannotReleaseGenuineOwner() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let (_, request) = try fixture.history.prepareSave(fixture.ready())
    let otherOwner = GalaxySSIHealthBackupHistory(owner: "other", secrets: fixture.secrets, fixtureDirectory: fixture.root)
    let otherDirectory = GalaxySSIHealthBackupHistory(owner: "fixture", secrets: fixture.secrets,
      fixtureDirectory: fixture.root.appendingPathComponent("other"))
    XCTAssertThrowsError(try otherOwner.finishSave(request, verified: true))
    XCTAssertThrowsError(try otherDirectory.finishSave(request, verified: true))
    let forged = GalaxySSIHealthBackupOperation.Request(scope: request.scope, kind: .save, entry: request.entry, token: request.token)
    XCTAssertThrowsError(try fixture.history.finishSave(forged, verified: true))
    GalaxySSIHealthBackupOperation.release(forged)
    XCTAssertTrue(GalaxySSIHealthBackupOperation.owns(request))
    try fixture.history.finishSave(request, verified: false)
  }

  @MainActor
  func testFailedReceiptPersistenceCannotReportVerifiedSuccess() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let (_, request) = try fixture.history.prepareSave(fixture.ready())
    fixture.secrets.unavailable = true
    XCTAssertThrowsError(try fixture.history.finishSave(request, verified: true))
    fixture.secrets.unavailable = false
    try fixture.history.recover()
    XCTAssertEqual(try fixture.history.entries().first?.latestSave, .interrupted)
    XCTAssertNil(try fixture.history.entries().first?.lastVerifiedAt)
  }

  @MainActor
  func testChangedMetadataOrPrivateBytesCannotBeginASave() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let entry = try fixture.ready()
    var changed = entry
    changed.sha256 = String(repeating: "a", count: 64)
    XCTAssertThrowsError(try fixture.history.prepareSave(changed))
    try Data("corrupt synthetic package".utf8).write(to: fixture.root.appendingPathComponent(entry.id.uuidString))
    XCTAssertThrowsError(try fixture.history.prepareSave(entry))
    XCTAssertNil(try fixture.history.entries().first?.saveToken)
    XCTAssertNil(try fixture.history.entries().first?.latestSave)
  }

  @MainActor
  private struct Fixture {
    let root: URL
    let secrets: BackupOperationSecrets
    let history: GalaxySSIHealthBackupHistory
    let data = Data("synthetic package bytes, not an archive integration fixture".utf8)
    init() throws {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let secrets = BackupOperationSecrets()
      self.root = root; self.secrets = secrets
      history = GalaxySSIHealthBackupHistory(owner: "fixture", secrets: secrets, fixtureDirectory: root)
    }
    func ready() throws -> GalaxySSIHealthBackupHistory.Entry {
      let request = try history.beginGeneration()
      try history.publish(data, request: request)
      return try XCTUnwrap(history.entries().first)
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
  }
}

private final class BackupOperationSecrets: GalaxySSISecretStore {
  var unavailable = false
  private var values: [String: String] = [:]
  func setString(_ value: String, account: String) throws {
    guard !unavailable else { throw GalaxySSIHealthPortableBackup.Failure.invalid }
    values[account] = value
  }
  func string(account: String) -> String? { unavailable ? nil : values[account] }
  func delete(account: String) { values.removeValue(forKey: account) }
}
