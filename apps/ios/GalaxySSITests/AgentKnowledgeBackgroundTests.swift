import Foundation
import UIKit
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeBackgroundTests: XCTestCase {
  func testExpirationCompletesOnceAndCancelsLateInstalledWork() {
    var completed = 0, cancelled = 0
    let control = AgentKnowledgeBackgroundCompletion { success, pending in
      XCTAssertFalse(success)
      XCTAssertEqual(pending, true)
      completed += 1
    }
    control.onCancellation { cancelled += 1 }
    control.finish(success: false, pending: true)
    control.onCancellation { cancelled += 1 }
    control.finish(success: true, pending: false)
    control.finish(success: false, pending: true)
    XCTAssertEqual(completed, 1)
    XCTAssertEqual(cancelled, 2)
  }

  func testSuccessfulCompletionCannotBeExpiredOrRescheduledAgain() {
    var completed = 0, cancelled = 0
    let control = AgentKnowledgeBackgroundCompletion { success, pending in
      XCTAssertTrue(success)
      XCTAssertEqual(pending, false)
      completed += 1
    }
    control.onCancellation { cancelled += 1 }
    control.finish(success: true, pending: false)
    control.finish(success: false, pending: true)
    control.onCancellation { cancelled += 1 }
    XCTAssertEqual(completed, 1)
    XCTAssertEqual(cancelled, 0)
  }

  func testBackgroundLeaseDoesNotReenableForegroundQueryPermissions() throws {
    let files = makeFiles()
    defer { restoreNotifications() }
    NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
    XCTAssertNil(files.activeToken())
    let token = files.token()
    let lease = try files.beginBackgroundLease()
    XCTAssertTrue(lease.isValid)
    XCTAssertEqual(lease.token, token)
    XCTAssertNil(files.activeToken())
    lease.end()
    XCTAssertFalse(lease.isValid)
    XCTAssertEqual(files.token(), token)
    XCTAssertNil(files.activeToken())
  }

  func testProtectedDataRevocationInvalidatesAllBackgroundLeases() throws {
    let files = makeFiles()
    defer { restoreNotifications() }
    let lease = try files.beginBackgroundLease()
    NotificationCenter.default.post(name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
    XCTAssertFalse(lease.isValid)
    XCTAssertNil(files.activeToken())
    XCTAssertThrowsError(try files.beginBackgroundLease())
    NotificationCenter.default.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
    XCTAssertFalse(lease.isValid)
    XCTAssertTrue(try files.beginBackgroundLease().isValid)
  }

  func testForegroundReentryRetiresOnlyTheBackgroundCapability() throws {
    let files = makeFiles()
    defer { restoreNotifications() }
    NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
    let lease = try files.beginBackgroundLease(), token = files.token()
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertFalse(lease.isValid)
    XCTAssertEqual(files.activeToken(), token)
    let another = try files.beginBackgroundLease()
    lease.end()
    XCTAssertTrue(another.isValid)
  }

  func testProducerResumesOnlyExactIncompleteSourceCheckpoints() {
    let item = source(), spec = provenance()
    let first = checkpoint(item: item, spec: spec)
    let resumed = AgentKnowledgeVectorIndexer.resumableCheckpoints([first], item: item, provenance: spec,
      chunks: ["first", "second"])
    XCTAssertEqual(resumed[0], first)
    XCTAssertNil(resumed[1])
  }

  func testProducerRejectsChangedSourceContractAndOffsets() {
    let item = source(), spec = provenance(), first = checkpoint(item: source(), spec: provenance())
    var changed = item
    changed.content = "first replacement"
    XCTAssertTrue(AgentKnowledgeVectorIndexer.resumableCheckpoints([first], item: changed, provenance: spec,
      chunks: ["first", "replacement"]).isEmpty)
    var contract = spec
    contract.contextTokens += 1
    XCTAssertTrue(AgentKnowledgeVectorIndexer.resumableCheckpoints([first], item: item, provenance: contract,
      chunks: ["first", "second"]).isEmpty)
    var wrong = first
    wrong.sourceStartUTF16 = 1
    XCTAssertTrue(AgentKnowledgeVectorIndexer.resumableCheckpoints([wrong], item: item, provenance: spec,
      chunks: ["first", "second"]).isEmpty)
  }

  func testCompleteLegacyRecordsMustBeReindexedForPublication() {
    let item = source(), spec = provenance()
    var complete = checkpoint(item: item, spec: spec)
    complete.chunkCount = 1
    complete.sourceEndUTF16 = item.content.utf16.count
    XCTAssertTrue(AgentKnowledgeVectorIndexer.resumableCheckpoints([complete], item: item, provenance: spec,
      chunks: [item.content]).isEmpty)
  }

  @MainActor
  func testColdBackgroundLookupNeverCreatesAHistoryIdentity() throws {
    let name = "knowledge-background-\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    XCTAssertNil(GalaxySSIStore.existingAgentKnowledgeDatabase(defaults: defaults, secrets: InMemorySecretStore()))
    XCTAssertNil(defaults.string(forKey: "galaxyssi_agent_conversation_database_id_v1"))
    defaults.set("../not-a-history-id", forKey: "galaxyssi_agent_conversation_database_id_v1")
    XCTAssertNil(GalaxySSIStore.existingAgentKnowledgeDatabase(defaults: defaults, secrets: InMemorySecretStore()))
  }

  private func makeFiles() -> AgentKnowledgeNativeFiles {
    AgentKnowledgeNativeFiles(databaseURL: FileManager.default.temporaryDirectory
      .appendingPathComponent("knowledge-background-\(UUID().uuidString).sqlite"), secrets: InMemorySecretStore())
  }

  private func restoreNotifications() {
    NotificationCenter.default.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
  }

  private func source() -> AgentKnowledgeItem {
    AgentKnowledgeItem(id: "source", kind: .note, title: "Source", content: "first second", updatedAtMillis: 1)
  }

  private func provenance() -> AgentKnowledgeVectorProvenance {
    AgentKnowledgeVectorProvenance(modelSHA256: String(repeating: "a", count: 64), dimensions: 2,
      contextTokens: 32, chunkingContract: "fixture-v1")
  }

  private func checkpoint(item: AgentKnowledgeItem, spec: AgentKnowledgeVectorProvenance) -> AgentKnowledgeVectorCheckpoint {
    AgentKnowledgeVectorCheckpoint(itemId: item.id, sourceRevision: AgentKnowledgeVectorCheckpoint.sourceRevision(for: item),
      chunkIndex: 0, chunkCount: 2, vector: [0.6, 0.8], provenance: spec, sourceStartUTF16: 0, sourceEndUTF16: 5)
  }
}
