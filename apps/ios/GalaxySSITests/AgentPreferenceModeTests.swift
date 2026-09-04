import Foundation
import XCTest
@testable import GalaxySSI

final class AgentPreferenceModeTests: XCTestCase {
  func testWireValuesRoundTripAndUnknownValuesStayCautious() throws {
    for mode in AgentPreferenceMode.allCases {
      XCTAssertEqual(mode, AgentPreferenceMode.fromWireValue(mode.wireValue))
      XCTAssertEqual(mode, try JSONDecoder().decode(AgentPreferenceMode.self, from: Data("\"\(mode.wireValue)\"".utf8)))
    }

    XCTAssertEqual(AgentPreferenceMode.fromWireValue("FEWER-QUESTIONS"), .fewerQuestions)
    XCTAssertEqual(AgentPreferenceMode.fromWireValue("future-mode"), .cautious)
    XCTAssertEqual(String(decoding: try JSONEncoder().encode(AgentPreferenceMode.developer), as: UTF8.self), "\"developer\"")
  }

  func testEveryPresetKeepsTheHighRiskGuardEnabled() {
    for mode in AgentPreferenceMode.allCases {
      XCTAssertTrue(AgentPreferenceModePolicy.profile(mode).highRiskGuard, mode.androidName)
    }
  }

  func testAutomationRunsLowRiskActionsWhileCautiousModeAsksFirst() {
    let automation = AgentPreferenceModePolicy.profile(.automation)
    let cautious = AgentPreferenceModePolicy.profile(.cautious)

    XCTAssertEqual(automation.permissionMode, .autoLowRisk)
    XCTAssertEqual(cautious.permissionMode, .askBeforeAction)
    XCTAssertEqual(automation.taskExecutionMode, .autoComplete)
  }

  func testDeveloperModeExpandsStructuredDetailsWithoutDisablingSafety() {
    let profile = AgentPreferenceModePolicy.profile(.developer)

    XCTAssertTrue(profile.expandStructuredDetails)
    XCTAssertTrue(profile.highRiskGuard)
    XCTAssertFalse(profile.minimizeClarifications)
  }

  func testClarificationResolutionMinimizesLocalQuestionsForExplicitGoals() {
    let baseline = AgentClarificationDecision(mode: .askLocally, question: .taskGoal)

    XCTAssertEqual(
      AgentPreferenceModePolicy.resolveClarification(
        mode: .fewerQuestions,
        goal: "Build the app",
        baseline: baseline
      ),
      AgentClarificationDecision(mode: .execute)
    )
    XCTAssertEqual(
      AgentPreferenceModePolicy.resolveClarification(
        mode: .cautious,
        goal: "Build the app",
        baseline: baseline
      ),
      baseline
    )
    XCTAssertEqual(
      AgentPreferenceModePolicy.resolveClarification(
        mode: .automation,
        goal: "   ",
        baseline: baseline
      ),
      baseline
    )
  }

  func testStorePersistsWireValue() throws {
    let suiteName = "AgentPreferenceModeTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let store = AgentPreferenceModeStore(defaults: defaults)

    XCTAssertEqual(store.load(), .cautious)
    store.save(.developer)

    XCTAssertEqual(defaults.string(forKey: "galaxyssi_agent_preference.mode"), "developer")
    XCTAssertEqual(AgentPreferenceModeStore(defaults: defaults).load(), .developer)
  }
}
