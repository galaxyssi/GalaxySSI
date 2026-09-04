import XCTest
@testable import SignalASI

final class AgentIOSPr2627To2633RegressionCorpusTests: XCTestCase {
  func testCorpusContainsExactlyOneThousandTraceableCases() {
    let corpus = AgentIOSPr2627To2633RegressionCorpus.cases

    XCTAssertEqual(AgentIOSPr2627To2633RegressionCorpus.suites.count, 50)
    XCTAssertEqual(AgentIOSPr2627To2633RegressionCorpus.profiles.count, 20)
    XCTAssertEqual(corpus.count, 1_000)
    XCTAssertEqual(Set(corpus.map(\.id)).count, 1_000)
    XCTAssertEqual(Set(corpus.map(\.riskID)).count, 1_000)
    XCTAssertEqual(Set(corpus.map(\.conversationID)).count, 1_000)
    XCTAssertEqual(corpus.map(\.ordinal), Array(1...1_000))
    XCTAssertEqual(Set(corpus.map(\.pullRequest)), Set(2627...2633))
  }

  func testEverySuiteHasTwentyProfilesAndAnExecutableOracle() {
    let corpus = AgentIOSPr2627To2633RegressionCorpus.cases
    let grouped = Dictionary(grouping: corpus, by: \.suiteID)

    XCTAssertEqual(grouped.count, 50)
    for suite in AgentIOSPr2627To2633RegressionCorpus.suites {
      let cases = grouped[suite.id] ?? []
      XCTAssertEqual(cases.count, 20, suite.id)
      XCTAssertEqual(Set(cases.map(\.profileID)), Set(AgentIOSPr2627To2633RegressionCorpus.profiles), suite.id)
      XCTAssertEqual(Set(cases.map(\.oracle)), Set([suite.oracle]), suite.id)
    }
    XCTAssertEqual(
      Set(AgentIOSPr2627To2633RegressionCorpus.suites.map(\.oracle)),
      Set(AgentIOSPr2627To2633Oracle.allCases)
    )
  }

  func testAllCasesExerciseIOSProductionContracts() {
    for testCase in AgentIOSPr2627To2633RegressionCorpus.cases {
      XCTContext.runActivity(named: testCase.id) { _ in
        XCTAssertNoThrow(try AgentIOSPr2627To2633RegressionOracles.verify(testCase))
      }
    }
  }
}
