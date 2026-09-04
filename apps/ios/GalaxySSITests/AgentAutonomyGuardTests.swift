import XCTest
@testable import GalaxySSI

final class AgentAutonomyGuardTests: XCTestCase {
  func testAgentAutonomyGuardStopsWhenToolCallBudgetIsReached() {
    let completed = (0..<AgentModelPlannerSettings.minimumToolCalls).map {
      agentAutonomyAction(id: "completed-\($0)", status: .completed, package: "com.galaxyssi.\($0)")
    }
    let pending = agentAutonomyAction(id: "pending", status: .pendingConfirmation)
    let plan = agentAutonomyPlan(actions: [pending], actionHistory: completed)

    let decision = AgentAutonomyGuard.review(
      plan: plan,
      action: pending,
      settings: AgentModelPlannerSettings(maxToolCalls: AgentModelPlannerSettings.minimumToolCalls)
    )

    XCTAssertFalse(decision.allowed)
    XCTAssertEqual(decision.reason, "Autonomous tool-call budget reached")
    XCTAssertEqual(decision.completedToolCalls, AgentModelPlannerSettings.minimumToolCalls)
    XCTAssertEqual(decision.repeatedCalls, 0)
  }

  func testAgentAutonomyGuardIgnoresReadScreenDraftAndPendingActionsForBudget() {
    let history = [
      agentAutonomyAction(id: "screen", kind: .readScreen, status: .completed),
      agentAutonomyAction(id: "draft", kind: .draftPlan, status: .failed),
      agentAutonomyAction(id: "pending", kind: .openApp, status: .pendingConfirmation),
      agentAutonomyAction(id: "blocked", kind: .openApp, status: .blocked, package: "com.galaxyssi.blocked")
    ]
    let next = agentAutonomyAction(id: "next", kind: .callConnector, status: .pendingConfirmation, connectorId: "calendar")
    let plan = agentAutonomyPlan(actions: [next], actionHistory: history)

    let decision = AgentAutonomyGuard.review(
      plan: plan,
      action: next,
      settings: AgentModelPlannerSettings(maxToolCalls: 8)
    )

    XCTAssertTrue(decision.allowed)
    XCTAssertEqual(AgentAutonomyGuard.completedToolCalls(plan: plan), 1)
    XCTAssertEqual(decision.completedToolCalls, 1)
  }

  func testAgentAutonomyGuardBlocksRepeatedLoopSensitiveToolCalls() {
    let repeated = [
      agentAutonomyAction(id: "first", kind: .openApp, status: .completed, package: "com.galaxyssi.chat"),
      agentAutonomyAction(id: "second", kind: .openApp, status: .failed, package: "com.galaxyssi.chat")
    ]
    let pending = agentAutonomyAction(
      id: "third",
      kind: .openApp,
      status: .pendingConfirmation,
      package: "com.galaxyssi.chat"
    )
    let plan = agentAutonomyPlan(actions: [pending], actionHistory: repeated)

    let decision = AgentAutonomyGuard.review(
      plan: plan,
      action: pending,
      settings: AgentModelPlannerSettings(maxToolCalls: 8)
    )

    XCTAssertFalse(decision.allowed)
    XCTAssertEqual(decision.reason, "Repeated autonomous tool-call loop blocked")
    XCTAssertEqual(decision.completedToolCalls, 2)
    XCTAssertEqual(decision.repeatedCalls, AgentAutonomyGuard.maxRepeatedToolCalls)
  }

  func testAgentAutonomyGuardAllowsDistinctPromptSignaturesAndNonLoopActions() {
    let first = agentAutonomyAction(
      id: "first",
      kind: .callConnector,
      status: .completed,
      connectorId: "research",
      prompt: "Find the latest note"
    )
    let second = agentAutonomyAction(
      id: "second",
      kind: .callConnector,
      status: .failed,
      connectorId: "research",
      prompt: "Find the latest note"
    )
    let distinctPrompt = agentAutonomyAction(
      id: "distinct",
      kind: .callConnector,
      status: .pendingConfirmation,
      connectorId: "research",
      prompt: "Find the latest note again"
    )
    let nonLoopRepeated = agentAutonomyAction(
      id: "type",
      kind: .typeText,
      status: .pendingConfirmation,
      prompt: "Find the latest note"
    )
    let plan = agentAutonomyPlan(actions: [distinctPrompt], actionHistory: [first, second])

    XCTAssertTrue(
      AgentAutonomyGuard.review(
        plan: plan,
        action: distinctPrompt,
        settings: AgentModelPlannerSettings(maxToolCalls: 8)
      ).allowed
    )
    XCTAssertTrue(
      AgentAutonomyGuard.review(
        plan: agentAutonomyPlan(actions: [nonLoopRepeated], actionHistory: [first, second]),
        action: nonLoopRepeated,
        settings: AgentModelPlannerSettings(maxToolCalls: 8)
      ).allowed
    )
  }

  func testAgentAutonomyGuardModelsUseAndroidWireNames() throws {
    let decoded = try JSONDecoder.galaxySSI.decode(
      AgentAutonomyDecision.self,
      from: Data(
        #"{"allowed":false,"reason":"Repeated autonomous tool-call loop blocked","completed_tool_calls":2,"repeated_calls":2}"#.utf8
      )
    )
    let encoded = String(
      decoding: try JSONEncoder.galaxySSI.encode(decoded),
      as: UTF8.self
    )

    XCTAssertFalse(decoded.allowed)
    XCTAssertEqual(decoded.completedToolCalls, 2)
    XCTAssertEqual(decoded.repeatedCalls, 2)
    XCTAssertTrue(encoded.contains(#""completed_tool_calls":2"#))
    XCTAssertTrue(encoded.contains(#""repeated_calls":2"#))
  }

  private func agentAutonomyAction(
    id: String,
    kind: AgentActionKind = .openApp,
    status: AgentActionStatus,
    package: String = "com.galaxyssi.chat",
    connectorId: String = "",
    url: String = "",
    prompt: String = ""
  ) -> AgentAction {
    var parameters: [String: String] = [:]
    if !package.isEmpty { parameters["package"] = package }
    if !connectorId.isEmpty { parameters["connector_id"] = connectorId }
    if !url.isEmpty { parameters["url"] = url }
    if !prompt.isEmpty { parameters["prompt"] = prompt }
    return AgentAction(
      id: id,
      kind: kind,
      target: "GalaxySSI",
      risk: .low,
      status: status,
      description: id,
      parameters: parameters
    )
  }

  private func agentAutonomyPlan(
    actions: [AgentAction],
    actionHistory: [AgentAction] = []
  ) -> AgentPlan {
    AgentPlan(
      goal: "Review autonomy guard",
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent"),
      steps: [],
      actions: actions,
      actionHistory: actionHistory
    )
  }

}
