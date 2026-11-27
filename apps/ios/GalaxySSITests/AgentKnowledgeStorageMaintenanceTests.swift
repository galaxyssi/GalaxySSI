import Foundation
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeStorageMaintenanceTests: XCTestCase {
  func testIdlePolicyRejectsForegroundLockedPowerSavingAndHotStates() {
    for thermal in [ProcessInfo.ThermalState.nominal, .fair] {
      XCTAssertTrue(AgentKnowledgeStorageMaintenancePolicy.permits(foreground: false, protectedData: true, lowPower: false, thermal: thermal))
      XCTAssertFalse(AgentKnowledgeStorageMaintenancePolicy.permits(foreground: true, protectedData: true, lowPower: false, thermal: thermal))
      XCTAssertFalse(AgentKnowledgeStorageMaintenancePolicy.permits(foreground: false, protectedData: false, lowPower: false, thermal: thermal))
      XCTAssertFalse(AgentKnowledgeStorageMaintenancePolicy.permits(foreground: false, protectedData: true, lowPower: true, thermal: thermal))
    }
    for thermal in [ProcessInfo.ThermalState.serious, .critical] {
      XCTAssertFalse(AgentKnowledgeStorageMaintenancePolicy.permits(foreground: false, protectedData: true, lowPower: false, thermal: thermal))
    }
  }

  func testMonotonicBudgetRejectsDeadlineBackwardAndNonfiniteClocks() throws {
    var now: TimeInterval = 100
    let budget = AgentKnowledgeStorageMaintenanceBudget(seconds: 10, clock: { now })
    try budget.check()
    now = 109.999
    try budget.check()
    for value in [110.0, 200, 99, .infinity, .nan] {
      now = value
      XCTAssertThrowsError(try budget.check())
    }
    now = 100
    XCTAssertThrowsError(try AgentKnowledgeStorageMaintenanceBudget(seconds: 0, clock: { now }).check())
    XCTAssertThrowsError(try AgentKnowledgeStorageMaintenanceBudget(seconds: -1, clock: { now }).check())
  }

  func testExpiredGrantCompletesOnceAndCancelsLateRegisteredWork() {
    var completions = 0, cancellations = 0
    let control = AgentKnowledgeBackgroundCompletion { success, pending in
      completions += 1
      XCTAssertFalse(success)
      XCTAssertEqual(pending, true)
    }
    control.onCancellation { cancellations += 1 }
    control.finish(success: false, pending: true)
    control.onCancellation { cancellations += 1 }
    control.finish(success: true, pending: true)
    XCTAssertEqual(completions, 1)
    XCTAssertEqual(cancellations, 2)
  }

  func testSuccessfulGrantKeepsPeriodicIntentWithoutCancellingFinishedWork() {
    var completions = 0, cancellations = 0
    let control = AgentKnowledgeBackgroundCompletion { success, pending in
      completions += 1
      XCTAssertTrue(success)
      XCTAssertEqual(pending, true)
    }
    control.onCancellation { cancellations += 1 }
    control.finish(success: true, pending: true)
    control.onCancellation { cancellations += 1 }
    control.finish(success: false, pending: true)
    XCTAssertEqual(completions, 1)
    XCTAssertEqual(cancellations, 0)
  }

  func testStorageSliceMigratesAndReclaimsWithoutAnEmbeddingRuntime() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("knowledge.sqlite"), secrets = InMemorySecretStore()
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    let items = (0..<12).map { index in AgentKnowledgeItem(id: "background-\(index)", kind: .document,
      title: "Synthetic", content: "complete body \(index)", source: "background", updatedAtMillis: Int64(index + 1)) }
    XCTAssertTrue(database.replaceAll(items))
    try seedLegacyKnowledgePayloads(items, url: url, secrets: secrets, externalIDs: Set(items.map(\.id)))
    let revision = try database.sourceBrowseRevision()
    let payloads = URL(fileURLWithPath: url.path + ".payloads", isDirectory: true)
    for file in try FileManager.default.contentsOfDirectory(at: payloads, includingPropertiesForKeys: nil) {
      try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: file.path)
    }
    XCTAssertTrue(try database.maintainPrimaryStorageSlice(maximumPages: 1))
    XCTAssertFalse(try database.maintainPrimaryStorageSlice(maximumPages: 8))
    XCTAssertEqual(try database.all(), items)
    XCTAssertEqual(try database.sourceBrowseRevision(), revision)
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: payloads, includingPropertiesForKeys: nil).isEmpty)
  }

  func testCancellationLeavesCommittedDataReadableAndResumable() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("knowledge.sqlite"), secrets = InMemorySecretStore()
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    let item = AgentKnowledgeItem(id: "cancelled-storage", kind: .note, title: "Synthetic", content: "preserve", source: "fixture", updatedAtMillis: 1)
    XCTAssertTrue(database.replaceAll([item]))
    try seedLegacyKnowledgePayloads([item], url: url, secrets: secrets, externalIDs: [item.id])
    var checks = 0
    XCTAssertThrowsError(try database.maintainPrimaryStorageSlice { checks += 1; throw CancellationError() })
    XCTAssertEqual(checks, 1)
    XCTAssertEqual(try database.all(), [item])
    XCTAssertThrowsError(try database.maintainPrimaryStorageSlice(maximumPages: 0))
    XCTAssertThrowsError(try database.maintainPrimaryStorageSlice(maximumPages: 33))
    XCTAssertFalse(try database.maintainPrimaryStorageSlice())
    XCTAssertEqual(try database.all(), [item])
  }
}
