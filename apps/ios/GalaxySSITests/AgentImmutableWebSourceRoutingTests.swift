import XCTest
@testable import GalaxySSI

final class AgentImmutableWebSourceRoutingTests: XCTestCase {
  private func select(health: [String: AgentIOSWebSourceHealth] = [:], now: Int64 = 0,
    learned: [AgentIOSLearnedWebSource] = [], ids: [String] = [], fanout: Int = 32) -> AgentIOSWebIntelligenceSourceSelection {
    AgentIOSWebIntelligenceQueryRouting.select(query: "synthetic query", requestedVerticals: [],
      requestedEngineIds: Set(ids), learnedSources: learned, requestedEngineOrder: ids,
      health: health, fanout: fanout, nowMillis: now)
  }
  func testEveryPinnedBaseSourceRemainsAvailableInItsExplicitOrder() {
    let ids = AgentIOSWebIntelligenceQueryRouting.baseSourceOrder
    XCTAssertEqual(ids.count, 41); XCTAssertEqual(Set(ids).count, 41)
    var observed: [String] = []
    for start in stride(from: 0, to: ids.count, by: 32) {
      let batch = Array(ids[start..<min(start + 32, ids.count)])
      observed += select(ids: batch).selected.map(\.id)
    }
    XCTAssertEqual(observed, ids)
    XCTAssertEqual(AgentIOSWebIntelligenceSourceCatalog.sourceCount, 288)
  }
  func testLiveCircuitAndClockAreNotCapturedByTheSharedCatalog() throws {
    let original = select()
    let id = try XCTUnwrap(original.selected.first?.id)
    let health = AgentIOSWebSourceHealth(sourceID: id, consecutiveFailures: 3, circuitOpenUntilMillis: 10_000)
    let blocked = select(health: [id: health], now: 1)
    XCTAssertFalse(blocked.selected.contains { $0.id == id })
    XCTAssertEqual(blocked.skipped.map(\.sourceID), [id])
    let expired = select(health: [id: health], now: 10_000)
    XCTAssertTrue(expired.selected.contains { $0.id == id }); XCTAssertTrue(expired.skipped.isEmpty)
    XCTAssertEqual(select(), original)
  }
  func testEachRequestUsesItsCurrentHealthScoresAndKeepsStableTies() {
    let baseline = select()
    let improved = AgentIOSWebSourceHealth(sourceID: "bing", attempts: 100, successes: 100,
      ewmaLatencyMillis: 1, ewmaResultCount: 24)
    XCTAssertEqual(select(health: ["bing": improved]).selected.first?.id, "bing")
    XCTAssertEqual(select(), baseline)
    let ties = ["brave", "mojeek", "qwant", "yahoo", "yandex", "ecosia", "startpage"]
    XCTAssertEqual(baseline.selected.map(\.id).filter { ties.contains($0) }, ties)
  }
  func testLearnedSourcesAppearDisappearAndDisableBetweenRequests() {
    let host = "synthetic-research-source.example"
    let id = AgentIOSWebSourceLearningPolicy.sourceID(host: host, vertical: "knowledge")
    var source = AgentIOSLearnedWebSource(sourceID: id, host: host, vertical: "knowledge", categoryTags: ["knowledge"],
      status: "verified", observations: 4, queryFingerprints: [String(repeating: "a", count: 24),
        String(repeating: "b", count: 24), String(repeating: "c", count: 24)], firstSeenAtMillis: 1, lastSeenAtMillis: 2)
    XCTAssertTrue(source.isSearchEligible)
    XCTAssertTrue(select(ids: [id]).selected.isEmpty)
    XCTAssertEqual(select(learned: [source], ids: [id]).selected.map(\.id), [id])
    XCTAssertTrue(select(ids: [id]).selected.isEmpty)
    source.status = "disabled"
    XCTAssertTrue(select(learned: [source], ids: [id]).selected.isEmpty)
    source.status = "verified"
    XCTAssertEqual(select(learned: [source], ids: [id]).selected.map(\.id), [id])
  }
  func testExplicitDisabledAndOpenSourcesRetainOrderAndValueIsolation() {
    let health = AgentIOSWebSourceHealth(sourceID: "bing", consecutiveFailures: 3, circuitOpenUntilMillis: 10_000)
    var first = select(health: ["bing": health], now: 1, ids: ["google", "bing", "google", "missing"])
    XCTAssertEqual(first.selected.map(\.id), ["google", "bing"])
    XCTAssertTrue(first.skipped.isEmpty)
    first.selected[0].title = "Changed local copy"
    first.selected[0].allowedHosts.append("foreign.example")
    let next = select(ids: ["google"])
    XCTAssertEqual(next.selected.first?.title, "Google")
    XCTAssertEqual(next.selected.first?.allowedHosts, [])
  }
  func testRepeatedSelectionRetainsFanoutBoundsAndUnknownExplicitNoFallback() {
    let expected = select()
    for _ in 0..<32 { XCTAssertEqual(select(), expected) }
    XCTAssertEqual(select(fanout: 0).selected.count, 1)
    XCTAssertEqual(select(fanout: 1).selected.count, 1)
    XCTAssertLessThanOrEqual(select(fanout: Int.max).selected.count, 32)
    XCTAssertEqual(select(fanout: Int.max), expected)
    XCTAssertTrue(select(ids: ["not-installed"]).selected.isEmpty)
  }
}
