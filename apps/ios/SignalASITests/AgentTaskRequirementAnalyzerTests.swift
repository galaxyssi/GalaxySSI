import XCTest
@testable import SignalASI

final class AgentTaskRequirementAnalyzerTests: XCTestCase {
  func testAgentTaskRequirementAnalyzerDetectsRestrictedChineseIdentityAndPaymentGoals() {
    let identity = AgentTaskRequirementAnalyzer.analyze(
      "\u{8bf7}\u{8bfb}\u{53d6}\u{6211}\u{7684}\u{8eab}\u{4efd}\u{8bc1}\u{5e76}\u{5b8c}\u{6210}\u{652f}\u{4ed8}"
    )

    XCTAssertEqual(identity.dataSensitivity, .restricted)
  }

  func testAgentTaskRequirementAnalyzerDetectsChineseBackgroundAndLongRunningGoals() {
    let background = AgentTaskRequirementAnalyzer.analyze(
      "\u{5728}\u{540e}\u{53f0}\u{76d1}\u{63a7}\u{4efb}\u{52a1}\u{72b6}\u{6001}"
    )
    let longRunning = AgentTaskRequirementAnalyzer.analyze(
      "\u{6301}\u{7eed}\u{8fd0}\u{884c}\u{76f4}\u{5230}\u{5b8c}\u{6210}"
    )

    XCTAssertEqual(background.executionHorizon, .background)
    XCTAssertEqual(longRunning.executionHorizon, .longRunning)
  }

  func testAgentTaskRequirementAnalyzerKeepsOfflineGoalsPrivate() {
    let requirements = AgentTaskRequirementAnalyzer.analyze("Keep this offline and local only")

    XCTAssertEqual(requirements.mode, .private)
    XCTAssertTrue(requirements.localOnly)
    XCTAssertEqual(requirements.dataSensitivity, .confidential)
  }

  func testAgentTaskRequirementAnalyzerLeavesWebDecisionToModelAndClassifiesCodeNeeds() {
    let live = AgentTaskRequirementAnalyzer.analyze("What is the current weather in Shanghai today?")
    let code = AgentTaskRequirementAnalyzer.analyze("Debug C:\\Temp\\next.py and test the program")

    XCTAssertFalse(live.liveDataRequired)
    XCTAssertTrue(live.capabilities.isDisjoint(with: Set([.liveData, .research, .toolUse])))
    XCTAssertGreaterThan(live.estimatedInputTokens, 0)
    XCTAssertTrue(code.complexReasoning)
    XCTAssertTrue(code.capabilities.isSuperset(of: Set([.code, .taskExecution, .reasoning])))
  }
}
