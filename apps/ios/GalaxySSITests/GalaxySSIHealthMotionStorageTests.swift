import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthMotionStorageTests: XCTestCase {
  func testMotionStateIsEncryptedSeparateFromMeasurementsAndGoalCanBeCleared() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: file.appendingPathExtension("motion")) }
    let records = GalaxySSIHealthRecords(owner: "motion-fixture", secrets: InMemorySecretStore(), isolatedFile: file)
    try records.write(.init(metric: .weight, value: 65))
    let measurements = try Data(contentsOf: file)
    let first = try records.updateMotion { $0.goal = 10_000 }
    XCTAssertEqual(try records.loadMotion(), first)
    let encrypted = try Data(contentsOf: file.appendingPathExtension("motion"))
    XCTAssertThrowsError(try JSONDecoder().decode(GalaxySSIHealthMotion.State.self, from: encrypted))
    XCTAssertEqual(try Data(contentsOf: file), measurements)
    try records.updateMotion { $0.goal = nil }
    XCTAssertNil(try records.loadMotion().goal)
    XCTAssertEqual(try Data(contentsOf: file), measurements)
  }
  func testCorruptionFailsClosedWithoutOverwritingExistingCiphertext() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let path = file.appendingPathExtension("motion")
    defer { try? FileManager.default.removeItem(at: path) }
    let records = GalaxySSIHealthRecords(owner: "motion-fixture", secrets: InMemorySecretStore(), isolatedFile: file)
    try records.updateMotion { $0.goal = 1 }
    var bytes = try Data(contentsOf: path); bytes[bytes.count - 1] ^= 1; try bytes.write(to: path)
    XCTAssertThrowsError(try records.loadMotion())
    XCTAssertThrowsError(try records.updateMotion { $0.goal = 2 })
    XCTAssertEqual(try Data(contentsOf: path), bytes)
  }
  func testCiphertextCannotBeReplayedAcrossOwners() throws {
    let first = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let second = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { for file in [first, second] { try? FileManager.default.removeItem(at: file.appendingPathExtension("motion")) } }
    let secrets = InMemorySecretStore()
    let a = GalaxySSIHealthRecords(owner: "a", secrets: secrets, isolatedFile: first)
    let b = GalaxySSIHealthRecords(owner: "b", secrets: secrets, isolatedFile: second)
    try a.updateMotion { $0.goal = 1 }; try b.updateMotion { $0.goal = 2 }
    try Data(contentsOf: first.appendingPathExtension("motion")).write(to: second.appendingPathExtension("motion"))
    XCTAssertThrowsError(try b.loadMotion()); XCTAssertEqual(try a.loadMotion().goal, 1)
  }
  func testBirthdayReferenceRequiresTheSameCurrentProfileConsent() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: file.appendingPathExtension("profile")) }
    let records = GalaxySSIHealthRecords(owner: "guidance-fixture", secrets: InMemorySecretStore(), isolatedFile: file)
    var profile = GalaxySSIHealthProfile(); profile.birthDate = Date(timeIntervalSince1970: 1_000_000_000)
    try records.writeProfile(profile)
    XCTAssertNil(try records.overviewBirthDate(expected: records.load()))
    try records.setPrivacy(.profileAnalysis, enabled: true)
    let approved = try records.load()
    XCTAssertEqual(try records.overviewBirthDate(expected: approved), profile.birthDate)
    try records.setPrivacy(.profileAnalysis, enabled: false)
    XCTAssertNil(try records.overviewBirthDate(expected: approved))
    try records.setPrivacy(.profileAnalysis, enabled: true)
    XCTAssertNil(try records.overviewBirthDate(expected: approved))
  }
}
