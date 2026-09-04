import XCTest
@testable import GalaxySSI

final class AgentGoalSegmentationPolicyTests: XCTestCase {
  func testMultilineAndSemicolonRequirementsRemainOneGoal() {
    let goal = """
      Create a title and subtitle for the offline phone Agent.
      The reply must contain the required marker; do not explain its purpose.
      The content must also mention offline or phone operation.
      """

    XCTAssertEqual(AgentGoalSegmentationPolicy.split(goal), [goal])
  }

  func testExplicitEnglishSequenceCreatesOrderedGoals() {
    XCTAssertEqual(
      AgentGoalSegmentationPolicy.split("Read the current battery and then report the result"),
      ["Read the current battery", "report the result"]
    )
  }

  func testExplicitChineseSequenceCreatesOrderedGoals() {
    let goal = "\u{8bfb}\u{53d6}\u{5f53}\u{524d}\u{7535}\u{91cf}\u{ff0c}\u{7136}\u{540e}" +
      "\u{628a}\u{7ed3}\u{679c}\u{544a}\u{8bc9}\u{6211}\u{ff0c}\u{63a5}\u{7740}" +
      "\u{8bb0}\u{5f55}\u{5230}\u{4efb}\u{52a1}\u{91cc}"
    XCTAssertEqual(AgentGoalSegmentationPolicy.split(goal), [
      "\u{8bfb}\u{53d6}\u{5f53}\u{524d}\u{7535}\u{91cf}",
      "\u{628a}\u{7ed3}\u{679c}\u{544a}\u{8bc9}\u{6211}",
      "\u{8bb0}\u{5f55}\u{5230}\u{4efb}\u{52a1}\u{91cc}"
    ])
  }

  func testDirectPlannerBuildsAnOrderedNativeToolSequence() throws {
    let request = AgentPlanRequest(
      goal: "Read the current battery and then check phone storage",
      screen: AgentScreenContext(foregroundApp: "com.galaxyssi.chat", pageTitle: "GalaxySSI"),
      nativeTools: readyTools()
    )

    let plan = try XCTUnwrap(AgentDirectNativeToolPlanner.plan(request: request))

    XCTAssertEqual(plan.actions.count, 2)
    XCTAssertEqual(plan.plannerProfile, "rule-based-direct-native-tool-sequence")
    XCTAssertEqual(plan.actions[1].parameters["depends_on"], plan.actions[0].id)
  }

  func testPlannerFallsBackToWholeGoalWhenOneSegmentIsNotRoutable() throws {
    let request = AgentPlanRequest(
      goal: "Read the current battery and then summarize it poetically",
      screen: AgentScreenContext(foregroundApp: "com.galaxyssi.chat", pageTitle: "GalaxySSI"),
      nativeTools: readyTools()
    )

    let plan = try XCTUnwrap(AgentDirectNativeToolPlanner.plan(request: request))

    XCTAssertEqual(plan.actions.count, 1)
    XCTAssertEqual(plan.plannerProfile, "rule-based-direct-native-tool")
  }

  func testCompoundPhoneOperationsBypassShortcutButStillPlanPerSegment() throws {
    let request = AgentPlanRequest(
      goal: "Read the current battery and then check phone storage",
      screen: AgentScreenContext(foregroundApp: "com.galaxyssi.chat", pageTitle: "GalaxySSI"),
      nativeTools: readyTools()
    )

    XCTAssertNil(AgentDirectNativeToolPlanner.shortcutPlan(request: request))
    XCTAssertEqual(try XCTUnwrap(AgentDirectNativeToolPlanner.plan(request: request)).actions.count, 2)
  }

  func testRepositoryAuditCannotBeHijackedByMemoryShortcut() {
    let request = AgentPlanRequest(
      goal: "Audit this repository, inspect available memory, Git, builds, tests, and replan from the evidence.",
      screen: AgentScreenContext(foregroundApp: "com.galaxyssi.chat", pageTitle: "GalaxySSI"),
      nativeTools: readyTools()
    )

    XCTAssertFalse(AgentDeterministicLocalShortcutPolicy.isEligible(request: request))
    XCTAssertNil(AgentDirectNativeToolPlanner.shortcutPlan(request: request))
  }

  func testAttachmentsAndExplicitAgentCoordinationBypassShortcut() {
    let battery = AgentPlanRequest(
      goal: "Read the current battery",
      screen: AgentScreenContext(foregroundApp: "com.galaxyssi.chat", pageTitle: "GalaxySSI"),
      nativeTools: readyTools()
    )
    var coordinated = battery
    coordinated.goal = "Ask two agents to read the current battery"

    XCTAssertNotNil(AgentDirectNativeToolPlanner.shortcutPlan(request: battery))
    XCTAssertNil(AgentDirectNativeToolPlanner.shortcutPlan(request: battery, hasAttachments: true))
    XCTAssertNil(AgentDirectNativeToolPlanner.shortcutPlan(request: coordinated))
  }

  private func readyTools() -> [AgentNativeToolDescriptor] {
    AgentPhoneNativeToolCatalog.descriptors(
      capabilityStatuses: AgentPhoneCapabilityCatalog.capabilities.map { boundary in
        AgentPhoneCapabilityStatus(
          boundary: boundary,
          availability: .ready,
          evidence: "Ready for test"
        )
      }
    )
  }
}
