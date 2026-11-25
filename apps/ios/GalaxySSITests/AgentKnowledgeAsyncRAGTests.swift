import Foundation
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeAsyncRAGTests: XCTestCase {
  @MainActor
  func testSearchUsesSemanticCandidatesWithoutLexicalOverlap() async throws {
    try await fixture { store in
      let source = Self.item("semantic", content: "orbital procedure")
      XCTAssertTrue(store.agentKnowledgeDatabase.replaceAll([source]))
      var calls = 0
      let hits = try await store.searchAgentKnowledgeHybrid("  nebula  ", limit: 8) { query, lexical, limit in
        calls += 1
        XCTAssertEqual(query, "nebula")
        XCTAssertTrue(lexical.isEmpty)
        XCTAssertEqual(limit, 8)
        return [Self.hit(source)]
      }
      XCTAssertEqual(calls, 1)
      XCTAssertEqual(hits.map(\.item.id), [source.id])
    }
  }

  @MainActor
  func testRAGPreservesCloudSummaryAndSelectedAgentPolicies() async throws {
    try await fixture { store in
      let denied = Self.item("denied", content: "not exportable")
      var summary = Self.item("summary", content: "private report body")
      summary.summary = "Approved abstract"
      summary.cloudAccess = .summaryOnly
      var full = Self.item("full", content: "permitted evidence")
      full.cloudAccess = .full
      full.agentAccess = .selectedAgents
      full.allowedAgentIds = ["paired-one"]
      XCTAssertTrue(store.agentKnowledgeDatabase.replaceAll([denied, summary, full]))
      let semantic: AgentKnowledgeSemanticQuery = { _, _, _ in [Self.hit(denied), Self.hit(summary), Self.hit(full)] }
      let cloud = try await store.retrieveAgentKnowledge("nebula", targetId: "cloud-models", semanticQuery: semantic)
      XCTAssertEqual(cloud.citations.count, 2)
      XCTAssertEqual(cloud.blockedMatchCount, 1)
      XCTAssertEqual(cloud.citations.first?.excerpt, "Approved abstract")
      XCTAssertEqual(cloud.citations.first?.evidenceMode, .summary)
      XCTAssertFalse(cloud.citations.contains { $0.itemId == denied.id })
      let paired = try await store.retrieveAgentKnowledge("nebula", targetId: "paired-one", semanticQuery: semantic)
      XCTAssertEqual(paired.citations.map(\.itemId), [full.id])
      let unknown = try await store.retrieveAgentKnowledge("nebula", targetId: "paired-other", semanticQuery: semantic)
      XCTAssertTrue(unknown.citations.isEmpty)
    }
  }

  @MainActor
  func testRAGDropsPolicyChangedOrDeletedHitsAfterAwait() async throws {
    try await fixture { store in
      var source = Self.item("changed", content: "old evidence")
      source.cloudAccess = .full
      XCTAssertTrue(store.agentKnowledgeDatabase.replaceAll([source]))
      let policy = try await store.retrieveAgentKnowledge("nebula", targetId: "cloud-models") { _, _, _ in
        var revoked = source
        revoked.cloudAccess = .deny
        XCTAssertTrue(store.agentKnowledgeDatabase.replaceAll([revoked]))
        return [Self.hit(source)]
      }
      XCTAssertTrue(policy.citations.isEmpty)
      let deleted = try await store.retrieveAgentKnowledge("nebula", targetId: "agent-knowledge-local") { _, _, _ in
        XCTAssertTrue(store.agentKnowledgeDatabase.replaceAll([]))
        return [Self.hit(source)]
      }
      XCTAssertTrue(deleted.citations.isEmpty)
    }
  }

  @MainActor
  func testResetOrCancelledCommandsDoNotProduceReadAudits() async throws {
    try await fixture { store in
      let source = Self.item("reset", content: "private evidence")
      XCTAssertTrue(store.agentKnowledgeDatabase.replaceAll([source]))
      do {
        _ = try await AgentPersonalDataCommandRouter.handle("ask knowledge nebula", store: store) { _, _, _ in
          store.agentKnowledgeDatabase.nativeFiles.invalidate()
          return [Self.hit(source)]
        }
        XCTFail("A reset read must not finish")
      } catch is CancellationError { } catch { XCTFail("Unexpected error: \(error)") }
      XCTAssertTrue(store.agentKnowledgeAccessAudit.isEmpty)
      let cancelled = Task { @MainActor in
        try await Task.sleep(nanoseconds: 1_000_000)
        return try await AgentPersonalDataCommandRouter.handle("search knowledge nebula", store: store,
          semanticQuery: { _, _, _ in [Self.hit(source)] })
      }
      cancelled.cancel()
      do { _ = try await cancelled.value; XCTFail("Cancelled commands must not finish") }
      catch is CancellationError { } catch { XCTFail("Unexpected error: \(error)") }
      XCTAssertTrue(store.agentKnowledgeAccessAudit.isEmpty)
    }
  }

  @MainActor
  func testReadCommandsUseHybridResultsAndRecordCurrentAudits() async throws {
    try await fixture { store in
      let source = Self.item("read", content: "orbital procedure")
      XCTAssertTrue(store.agentKnowledgeDatabase.replaceAll([source]))
      let semantic: AgentKnowledgeSemanticQuery = { _, _, _ in [Self.hit(source)] }
      let answer = try await AgentPersonalDataCommandRouter.handle("ask knowledge nebula", store: store, semanticQuery: semantic)
      XCTAssertEqual(answer?.actionId, "knowledge_answer")
      XCTAssertTrue(answer?.text.contains(source.content) == true)
      let search = try await AgentPersonalDataCommandRouter.handle("search knowledge nebula", store: store, semanticQuery: semantic)
      XCTAssertEqual(search?.actionId, "knowledge_search")
      XCTAssertTrue(search?.text.contains(source.content) == true)
      XCTAssertEqual(store.agentKnowledgeAccessAudit.count, 2)
      XCTAssertTrue(store.agentKnowledgeAccessAudit.allSatisfy { $0.targetId == "agent-knowledge-local" && $0.itemIdHashes.count == 1 })
    }
  }

  @MainActor
  func testDestructiveCommandsNeverUseTheSemanticBoundary() async throws {
    try await fixture { store in
      var calls = 0
      let result = try await AgentPersonalDataCommandRouter.handle("forget knowledge nebula", store: store) { _, _, _ in
        calls += 1
        return []
      }
      XCTAssertEqual(result?.actionId, "knowledge_forget")
      XCTAssertEqual(calls, 0)
      XCTAssertFalse(AgentPersonalDataCommandRouter.isKnowledgeRead("forget knowledge nebula"))
      XCTAssertTrue(AgentPersonalDataCommandRouter.isKnowledgeRead("ASK KNOWLEDGE nebula"))
    }
  }

  @MainActor
  func testEmptyOrZeroLimitSearchSkipsNativeExecution() async throws {
    try await fixture { store in
      var calls = 0
      let semantic: AgentKnowledgeSemanticQuery = { _, _, _ in calls += 1; return [] }
      let blank = try await store.searchAgentKnowledgeHybrid("  ", semanticQuery: semantic)
      let zero = try await store.searchAgentKnowledgeHybrid("nebula", limit: 0, semanticQuery: semantic)
      XCTAssertTrue(blank.isEmpty)
      XCTAssertTrue(zero.isEmpty)
      XCTAssertEqual(calls, 0)
    }
  }

  @MainActor
  private func fixture(_ body: @MainActor (GalaxySSIStore) async throws -> Void) async throws {
    let suite = "AgentKnowledgeAsyncRAG-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let store = GalaxySSIStore(defaults: defaults, secrets: InMemorySecretStore(), workspaceStore: InMemoryAgentWorkspaceStore())
    let root = store.agentKnowledgeDatabase.nativeFiles.rootDirectory.deletingLastPathComponent()
    let identifier = defaults.string(forKey: "galaxyssi_agent_conversation_database_id_v1") ?? ""
    defer {
      defaults.removePersistentDomain(forName: suite)
      // Remove only this fixture's UUID-qualified database families, never History.
      if UUID(uuidString: identifier) != nil, root.lastPathComponent == "History" {
        for prefix in ["agent-knowledge-", "agent-conversations-", "chat-history-"] {
          for suffix in ["", "-wal", "-shm", ".payloads", ".native"] {
            try? FileManager.default.removeItem(at: root.appendingPathComponent("\(prefix)\(identifier).sqlite\(suffix)"))
          }
        }
      }
    }
    try await body(store)
  }

  private static func item(_ id: String, content: String) -> AgentKnowledgeItem {
    AgentKnowledgeItem(id: id, kind: .note, title: "Guide", content: content, source: "local:\(id)", updatedAtMillis: 1)
  }

  private static func hit(_ source: AgentKnowledgeItem) -> AgentKnowledgeHit {
    AgentKnowledgeHit(item: source, score: 0.9, excerpt: source.content, matchedTerms: [])
  }
}
