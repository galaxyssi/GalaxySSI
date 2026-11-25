import Foundation
import XCTest
@testable import GalaxySSI

final class AgentIOSIndexedWebSourceCatalogTests: XCTestCase {
  func testBundledCatalogRegistersAllIndexedSitesAndCountsOnlyNativeAdapters() throws {
    let sources = AgentIOSWebIntelligenceSourceCatalog.indexedSources
    XCTAssertEqual(sources.count, 247)
    XCTAssertEqual(Set(sources.map(\.id)).count, 247)
    XCTAssertEqual(AgentIOSWebIntelligenceSourceCatalog.baseSearchEngineCount, 22)
    XCTAssertEqual(AgentIOSWebIntelligenceSourceCatalog.sourceCount, 269)
    XCTAssertEqual(AgentIOSWebIntelligenceSourceCatalog.officialDocumentationSources.count, 5)
    let agent = try XCTUnwrap(sources.first { $0.id == "openai_agents_sdk" })
    XCTAssertEqual(agent.scope, "openai.github.io/openai-agents-python")
    XCTAssertTrue(AgentIOSWebSearchEnginePolicy.supported.contains(agent.id))
    XCTAssertFalse(AgentIOSWebSearchEnginePolicy.supported.contains("google"))
  }

  func testCatalogDecodeRejectsWholeInvalidOrDuplicateSnapshots() throws {
    let valid: [String: Any] = ["id": "fixture_docs", "title": "Fixture", "vertical": "docs", "host": "docs.example.test",
      "scope": "docs.example.test/guide", "languages": ["*"], "authority": 0.9]
    let data = try JSONSerialization.data(withJSONObject: ["version": 1, "sources": [valid]])
    XCTAssertEqual(try AgentIOSIndexedWebSourceCatalog.decode(data).count, 1)
    XCTAssertThrowsError(try AgentIOSIndexedWebSourceCatalog.decode(JSONSerialization.data(withJSONObject: ["version": 2, "sources": [valid]])))
    XCTAssertThrowsError(try AgentIOSIndexedWebSourceCatalog.decode(JSONSerialization.data(withJSONObject: ["version": 1, "sources": [valid, valid]])))
    for scope in ["user:pass@docs.example.test/guide", "foreign.test/guide", "docs.example.test/../private",
      "docs.example.test/guide?credential=not-allowed", "docs.example.test:8443/guide"] {
      var invalid = valid
      invalid["scope"] = scope
      XCTAssertThrowsError(try AgentIOSIndexedWebSourceCatalog.decode(JSONSerialization.data(withJSONObject: ["version": 1, "sources": [invalid]])))
    }
    XCTAssertThrowsError(try AgentIOSIndexedWebSourceCatalog.decode(Data(repeating: 65, count: 131_073)))
  }

  func testLanguageRankingUsesDeclaredLanguagesWithoutGuessingTopics() {
    let chinese = AgentIOSWebIntelligenceQueryRouting.select(query: "\u{65b0}\u{95fb}", requestedVerticals: [.news], requestedEngineIds: [])
    XCTAssertEqual(chinese.selected.first?.id, "xinhua_news")
    let english = AgentIOSWebIntelligenceQueryRouting.select(query: "news", requestedVerticals: [.news], requestedEngineIds: [])
    XCTAssertEqual(english.selected.first?.id, "reuters_news")
    XCTAssertEqual(AgentIOSWebIntelligenceQueryRouting.queryLanguage("\u{3042}"), "ja")
    XCTAssertEqual(AgentIOSWebIntelligenceQueryRouting.queryLanguage("\u{ac00}"), "ko")
    XCTAssertTrue(AgentIOSWebIntelligenceQueryRouting.select(query: "medical news", requestedVerticals: [], requestedEngineIds: []).selected.isEmpty)
  }

  func testRequestedCategoryAndVerticalCoveragePrecedesRemainingCandidates() {
    let routing = AgentIOSWebIntelligenceQueryRouting.select(query: "independent sources", requestedVerticals: [.medical, .news],
      requestedEngineIds: [], requestedCategories: ["medical", "news"])
    XCTAssertEqual(Set(routing.selected.prefix(2).map(\.vertical)), [.medical, .news])
    XCTAssertEqual(Set(routing.selected.map(\.id)).count, routing.selected.count)
  }

  func testSiteScopeRequiresHostAndPathSegmentBoundary() {
    let scope = "openai.github.io/openai-agents-python"
    for url in ["https://openai.github.io/openai-agents-python", "https://openai.github.io/openai-agents-python/guide"] {
      XCTAssertTrue(AgentIOSIndexedWebSourceCatalog.allowsResult(url, scope: scope))
    }
    for url in ["https://openai.github.io/other", "https://openai.github.io/openai-agents-python-impostor/guide",
      "https://openai.github.io.evil.test/openai-agents-python", "https://user:pass@openai.github.io/openai-agents-python",
      "https://openai.github.io/openai-agents-python/../other"] {
      XCTAssertFalse(AgentIOSIndexedWebSourceCatalog.allowsResult(url, scope: scope))
    }
  }

  func testBuiltInIndexedDomainsAndSubdomainsAreNotLearnedAgain() {
    let observations = AgentIOSWebSourceLearningPolicy.observations(query: "Synthetic source discovery", categories: ["news"], results: [
      ["url": .string("https://reuters.com/article"), "vertical": .string("news")],
      ["url": .string("https://sub.reuters.com/article"), "vertical": .string("news")],
      ["url": .string("https://notreuters.com/article"), "vertical": .string("news")]
    ])
    XCTAssertEqual(observations.map(\.host), ["notreuters.com"])
    let host = "reuters.com"
    let saved = AgentIOSLearnedWebSource(sourceID: AgentIOSWebSourceLearningPolicy.sourceID(host: host, vertical: "news"),
      host: host, vertical: "news", categoryTags: ["news"], status: "verified", observations: 6,
      queryFingerprints: [String(repeating: "a", count: 24), String(repeating: "b", count: 24)],
      firstSeenAtMillis: 1, lastSeenAtMillis: 2)
    XCTAssertTrue(saved.isValid)
    XCTAssertFalse(saved.isSearchEligible)
  }

  func testActualRegistryUsesScopedIndexedEndpointAndFiltersForeignPathBeforeTruncation() throws {
    let transport = IndexedCatalogTransport()
    let result = try invoke("openai_agents_sdk", transport: transport)
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    let request = try XCTUnwrap(transport.requests.first)
    let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
    XCTAssertEqual(query, "site:openai.github.io/openai-agents-python Agent guide")
    XCTAssertEqual(transport.requests.count, 1)
    let results = try XCTUnwrap(result.output["results"]?.arrayValue)
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results.first?.objectValue?.string("url"), "https://openai.github.io/openai-agents-python/guide")
  }

  func testUnsupportedBaseAdapterDoesNotSilentlyFallBack() throws {
    let transport = IndexedCatalogTransport()
    let result = try invoke("google", transport: transport)
    XCTAssertFalse(result.isSuccess)
    XCTAssertTrue(transport.requests.isEmpty)
  }

  private func invoke(_ engine: String, transport: IndexedCatalogTransport) throws -> AgentNativeToolResult {
    let provider = AgentIOSURLSessionWebMediaToolProvider(transport: transport, sourceHealthStore: nil, nowMillis: { 1_000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: provider))
    return registry.invoke(AgentIOSWebMediaNativeToolCatalog.webSearch,
      input: ["query": .string("Agent guide"), "engines": .array([.string(engine)]), "max_results": .int(1)],
      context: .init(grantedPermissions: [AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission],
        grantedConsents: [AgentIOSWebMediaNativeToolCatalog.publicWebConsent]), hooks: .init(nowMillis: { 1_000 }))
  }
}

private final class IndexedCatalogTransport: AgentIOSURLSessionWebTransporting {
  private let lock = NSLock()
  private var saved: [AgentIOSURLSessionWebRequest] = []
  var requests: [AgentIOSURLSessionWebRequest] { lock.lock(); defer { lock.unlock() }; return saved }
  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
    lock.lock(); saved.append(request); lock.unlock()
    let html = """
      <ol><li class="b_algo"><h2><a href="https://openai.github.io/other">Agent guide outside scope</a></h2></li>
      <li class="b_algo"><h2><a href="https://openai.github.io/openai-agents-python/guide">Agent guide</a></h2></li></ol>
      """
    return .init(statusCode: 200, finalURL: request.url, headers: ["content-type": "text/html"], body: Data(html.utf8), retrievedAtEpochMillis: 1_000)
  }
}
