import Foundation
import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthRecordsTests: XCTestCase {
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
