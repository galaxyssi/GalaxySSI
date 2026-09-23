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

  func testRetrievalAdmissionFallsBackInsteadOfQueueingBehindOwner() throws {
    let admission = AgentKnowledgeRetrievalAdmission()
    let first = try XCTUnwrap(admission.acquire(timeoutMillis: 0))

    XCTAssertNil(admission.acquire(timeoutMillis: 0))
    first.release()
    first.release()

    let next = try XCTUnwrap(admission.acquire(timeoutMillis: 0))
    XCTAssertNil(admission.acquire(timeoutMillis: 0))
    next.release()
  }
}
