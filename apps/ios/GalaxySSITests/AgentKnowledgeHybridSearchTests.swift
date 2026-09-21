import XCTest
@testable import GalaxySSI

final class AgentKnowledgeHybridSearchTests: XCTestCase {
  func testReciprocalRankFusionRewardsAgreementAndKeepsUniqueResults() {
    let ranked = AgentKnowledgeHybridRanking.reciprocalRankFusion(
      lexicalIds: ["shared", "lexical", "shared"],
      semanticIds: ["semantic", "shared", "semantic"]
    )

    XCTAssertEqual(ranked.first?.id, "shared")
    XCTAssertEqual(Set(ranked.map(\.id)), ["shared", "lexical", "semantic"])
  }

  func testReciprocalRankFusionUsesStableTieBreak() {
    let ranked = AgentKnowledgeHybridRanking.reciprocalRankFusion(
      lexicalIds: ["b"],
      semanticIds: ["a"]
    )

    XCTAssertEqual(ranked.map(\.id), ["a", "b"])
  }
}
