import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeStatisticsContextTests: XCTestCase {
  private func request(knowledge: Bool = true, privateMode: Bool = false) -> AgentModelPlanningPromptRequest {
    AgentModelPlanningPromptRequest(planRequest: AgentPlanRequest(goal: "Search knowledge", screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")),
      conversationContext: AgentConversationContext(conversationId: "fixture", summary: "", turns: [], privateMode: privateMode),
      requirements: AgentTaskRequirements(capabilities: knowledge ? [.knowledgeSearch] : [], mode: .quality))
  }
  func testIndexedCountsPassThroughWithoutCacheEnumeration() {
    let stats = AgentKnowledgeStats(itemCount: 4_294_967_300, sourceCount: 4_294_967_301, lastUpdatedAtMillis: 99)
    XCTAssertEqual(AgentKnowledgeStatisticsContext.resolve(stats), stats)
    XCTAssertEqual(AgentKnowledgeStatisticsContext.parameters(stats)["item_count"], "4294967300")
    XCTAssertEqual(AgentKnowledgeStatisticsContext.parameters(stats)["source_count"], "4294967301")
  }
  func testUnavailableReadDoesNotReportExactZeroOrIndexingProgress() {
    let stats = AgentKnowledgeStatisticsContext.resolve(nil), values = AgentKnowledgeStatisticsContext.parameters(stats)
    XCTAssertFalse(stats.countsComplete); XCTAssertTrue(stats.countsUnavailable)
    XCTAssertNil(values["item_count"]); XCTAssertNil(values["source_count"])
    XCTAssertEqual(values["knowledge_count_status"], "unavailable")
    XCTAssertEqual(values["counts_complete"], "false")
    let summary = AgentKnowledgeStatisticsContext.summary(stats, language: "en")
    XCTAssertTrue(summary.contains("unavailable")); XCTAssertFalse(summary.contains("0")); XCTAssertFalse(summary.contains("indexing"))
  }
  func testPartialCountsAreLowerBoundsInEnglishAndChinese() {
    let stats = AgentKnowledgeStats(itemCount: 70, sourceCount: 2, countsComplete: false)
    let en = AgentKnowledgeStatisticsContext.summary(stats, language: "en")
    XCTAssertTrue(en.contains("at least 70")); XCTAssertTrue(en.contains("at least 2")); XCTAssertTrue(en.contains("indexing"))
    let zh = AgentKnowledgeStatisticsContext.summary(stats, language: "zh-CN")
    XCTAssertTrue(zh.contains("\u{81f3}\u{5c11} 70")); XCTAssertTrue(zh.contains("\u{81f3}\u{5c11} 2"))
    XCTAssertEqual(AgentKnowledgeStatisticsContext.parameters(stats)["knowledge_count_status"], "partial_indexing")
  }
  func testCompleteCountsDoNotClaimPartialIndexing() {
    let stats = AgentKnowledgeStats(itemCount: 70, sourceCount: 2)
    XCTAssertEqual(AgentKnowledgeStatisticsContext.summary(stats, language: "en"), "Knowledge base: 70 items; sources=2")
    XCTAssertEqual(AgentKnowledgeStatisticsContext.parameters(stats)["knowledge_count_status"], "complete")
  }
  func testLegacyStatsDecodeAndNewUnavailableInvariantRoundTrip() throws {
    let old = Data(#"{"item_count":4294967300,"source_count":2,"last_updated_at_millis":99}"#.utf8)
    let decoded = try JSONDecoder().decode(AgentKnowledgeStats.self, from: old)
    XCTAssertEqual(decoded.itemCount, 4_294_967_300); XCTAssertTrue(decoded.countsComplete); XCTAssertFalse(decoded.countsUnavailable)
    let unavailable = AgentKnowledgeStats(countsComplete: true, countsUnavailable: true)
    XCTAssertFalse(unavailable.countsComplete)
    XCTAssertEqual(try JSONDecoder().decode(AgentKnowledgeStats.self, from: JSONEncoder().encode(unavailable)), unavailable)
  }
  func testPrivateOrNonKnowledgePlanningNeverReadsStatistics() {
    for input in [request(knowledge: false), request(privateMode: true)] {
      var reads = 0
      XCTAssertNil(AgentKnowledgeStatisticsContext.capture(for: input) { reads += 1; return AgentKnowledgeStats() })
      XCTAssertEqual(reads, 0)
    }
  }
  func testKnowledgePlanningCapturesOneMetadataOnlySnapshot() {
    var reads = 0
    let stats = AgentKnowledgeStats(itemCount: 42, sourceCount: 2, countsComplete: false)
    XCTAssertEqual(AgentKnowledgeStatisticsContext.capture(for: request()) { reads += 1; return stats }, stats)
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(Set(AgentKnowledgeStatisticsContext.parameters(stats).keys),
      ["item_count", "source_count", "last_updated_at_millis", "counts_complete", "knowledge_count_status"])
  }
  func testPlannerPromptIncludesPartialStatusButNotRecordBodies() {
    var input = request()
    input.knowledgeStats = AgentKnowledgeStats(itemCount: 12, sourceCount: 2, countsComplete: false)
    let prompt = AgentModelPlanningPrompt.build(request: input, settings: AgentModelPlannerSettings(enabled: true))
    XCTAssertTrue(prompt.contains("partial_indexing")); XCTAssertTrue(prompt.contains("metadata only; not retrieval evidence"))
    XCTAssertTrue(prompt.contains("\"item_count\":\"12\"")); XCTAssertFalse(prompt.contains("private record body"))
  }
  func testPromptBuilderRechecksPrivacyForRestoredRequests() {
    for var input in [request(knowledge: false), request(privateMode: true)] {
      input.knowledgeStats = AgentKnowledgeStats(itemCount: 987654321, sourceCount: 2)
      XCTAssertFalse(AgentModelPlanningPrompt.build(request: input, settings: AgentModelPlannerSettings(enabled: true)).contains("987654321"))
    }
  }
  func testPlanningSnapshotRoundTripPreservesWideCountsAndOldAbsence() throws {
    var input = request()
    let old = try JSONEncoder().encode(input)
    XCTAssertNil(try JSONDecoder().decode(AgentModelPlanningPromptRequest.self, from: old).knowledgeStats)
    input.knowledgeStats = AgentKnowledgeStats(itemCount: 9_007_199_254_740_993, sourceCount: 2, countsComplete: false)
    let encoded = try JSONEncoder().encode(input)
    XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("9007199254740993"))
    XCTAssertEqual(try JSONDecoder().decode(AgentModelPlanningPromptRequest.self, from: encoded).knowledgeStats, input.knowledgeStats)
  }

  @MainActor private func fixture(_ body: @MainActor (GalaxySSIStore, URL) async throws -> Void) async throws {
    let suite = "KnowledgeStats-\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let store = GalaxySSIStore(defaults: defaults, secrets: InMemorySecretStore(), workspaceStore: InMemoryAgentWorkspaceStore())
    store.languagePolicy.responseLanguage = "en"
    let directory = store.agentKnowledgeDatabase.nativeFiles.rootDirectory
    let root = directory.deletingLastPathComponent(), id = defaults.string(forKey: "galaxyssi_agent_conversation_database_id_v1") ?? ""
    let url = root.appendingPathComponent("agent-knowledge-\(id).sqlite", isDirectory: false)
    defer {
      defaults.removePersistentDomain(forName: suite)
      if UUID(uuidString: id) != nil, root.lastPathComponent == "History" {
        for prefix in ["agent-knowledge-", "agent-conversations-", "chat-history-"] {
          for suffix in ["", "-wal", "-shm", ".payloads", ".primary", ".native"] {
            try? FileManager.default.removeItem(at: root.appendingPathComponent("\(prefix)\(id).sqlite\(suffix)"))
          }
        }
      }
    }
    try await body(store, url)
  }
  private func sql(_ url: URL, _ sql: String) throws {
    var raw: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
    let database = try XCTUnwrap(raw); defer { sqlite3_close_v2(database) }
    XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
  }
  @MainActor func testOverviewUsesBoundedIndexedSourcesInsteadOfEmptyUICache() async throws {
    try await fixture { store, _ in
      let items = (0..<14).map { AgentKnowledgeItem(id: "item-\($0)", kind: .note, title: "Title \($0)", content: "Body", source: "source-\($0)", updatedAtMillis: Int64($0 + 1)) }
      XCTAssertTrue(store.agentKnowledgeDatabase.replaceAll(items)); XCTAssertTrue(store.agentKnowledgeItems.isEmpty)
      let response = try await AgentPersonalDataCommandRouter.handle("knowledge status", store: store)
      let result = try XCTUnwrap(response)
      XCTAssertEqual(result.parameters["item_count"], "14"); XCTAssertEqual(result.parameters["counts_complete"], "true")
      XCTAssertEqual(result.text.components(separatedBy: "\n").count, 11)
      XCTAssertFalse(result.text.contains("No knowledge items"))
    }
  }
  @MainActor func testPartialDirectoryDoesNotClaimKnowledgeIsEmpty() async throws {
    try await fixture { store, url in
      let item = AgentKnowledgeItem(id: "item", kind: .note, title: "Title", content: "Body", source: "source", updatedAtMillis: 1)
      XCTAssertTrue(store.agentKnowledgeDatabase.replaceAll([item]))
      try sql(url, "UPDATE knowledge_item_count_state SET complete=0,items=0; UPDATE knowledge_source_directory_state SET complete=0")
      let response = try await AgentPersonalDataCommandRouter.handle("knowledge status", store: store)
      let result = try XCTUnwrap(response)
      XCTAssertEqual(result.parameters["counts_complete"], "false"); XCTAssertTrue(result.text.contains("at least 0"))
      XCTAssertTrue(result.text.contains("Recent sources are still indexing")); XCTAssertFalse(result.text.contains("No knowledge items"))
    }
  }
  @MainActor func testUnavailableCountersDoNotFallBackToCachedExactTotals() async throws {
    try await fixture { store, url in
      try sql(url, "DROP TABLE knowledge_item_count_state")
      XCTAssertTrue(store.agentKnowledgeStats.countsUnavailable)
      let response = try await AgentPersonalDataCommandRouter.handle("knowledge status", store: store)
      let result = try XCTUnwrap(response)
      XCTAssertEqual(result.parameters["knowledge_count_status"], "unavailable"); XCTAssertNil(result.parameters["item_count"])
      XCTAssertTrue(result.text.contains("unavailable")); XCTAssertFalse(result.text.contains("No knowledge items"))
    }
  }
  @MainActor func testWideCountersAndCoveringLatestIndexRemainAvailableWithoutBodyReads() async throws {
    try await fixture { store, url in
      try sql(url, "UPDATE knowledge_item_count_state SET items=4294967300,complete=1; UPDATE knowledge_source_directory_state SET groups=4294967301,complete=1")
      XCTAssertEqual(try store.agentKnowledgeDatabase.knowledgeStats().itemCount, 4_294_967_300)
      var raw: OpaquePointer?; XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
      let db = try XCTUnwrap(raw); defer { sqlite3_close_v2(db) }
      var statement: OpaquePointer?
      XCTAssertEqual(sqlite3_prepare_v2(db, "EXPLAIN QUERY PLAN SELECT updated_at FROM knowledge_items ORDER BY updated_at DESC,item_hash ASC LIMIT 1", -1, &statement, nil), SQLITE_OK)
      let row = try XCTUnwrap(statement); defer { sqlite3_finalize(row) }
      var plan = ""
      while sqlite3_step(row) == SQLITE_ROW { if let text = sqlite3_column_text(row, 3) { plan += String(cString: text) } }
      XCTAssertTrue(plan.contains("knowledge_item_recent")); XCTAssertTrue(plan.uppercased().contains("COVERING"))
    }
  }
}
