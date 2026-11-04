import Foundation
import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthRecordsTests: XCTestCase {
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
}

private final class HealthFixtureSecrets: GalaxySSISecretStore {
  private var values: [String: String] = [:]
  func setString(_ value: String, account: String) throws { values[account] = value }
  func string(account: String) -> String? { values[account] }
  func delete(account: String) { values.removeValue(forKey: account) }
}
