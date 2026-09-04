import XCTest
@testable import GalaxySSI

final class AgentToolCoordinationTests: XCTestCase {
  func testDependencyParsingAndRemapMatchAndroidDistinctMappedOnlySemantics() {
    let original = action(
      "old",
      parameters: [
        "depends_on": " a, b, a, , c ",
        "use_outputs_from": "a, d, d"
      ]
    )
    let remapped = AgentToolCoordination.remapToolGraphIds(
      action: original,
      newId: "new",
      idMap: ["a": "A", "c": "C"]
    )

    XCTAssertEqual(AgentToolCoordination.dependencyIds(original), ["a", "b", "c"])
    XCTAssertEqual(AgentToolCoordination.outputSourceIds(original), ["a", "d"])
    XCTAssertEqual(remapped.id, "new")
    XCTAssertEqual(remapped.parameters["depends_on"], "A,C")
    XCTAssertEqual(remapped.parameters["use_outputs_from"], "A")
  }

  func testNextRunnableActionAndFailedDependencyBlocking() throws {
    let completedHistory = action("prepare", status: .completed, result: "done")
    let failedHistory = action("fetch", status: .failed, result: "network failed")
    let ready = action("ready", parameters: ["depends_on": "prepare"])
    let blocked = action("blocked", parameters: ["depends_on": "fetch"])
    let waiting = action("waiting", parameters: ["depends_on": "missing"])
    let plan = self.plan(
      actions: [ready, blocked, waiting],
      actionHistory: [completedHistory, failedHistory]
    )

    let next = try XCTUnwrap(AgentToolCoordination.nextRunnableAction(plan))
    let blockedPlan = AgentToolCoordination.blockActionsWithFailedDependencies(plan)

    XCTAssertEqual(next.id, "ready")
    XCTAssertEqual(blockedPlan.actions.map(\.status), [.proposed, .blocked, .proposed])
    XCTAssertEqual(blockedPlan.actions[1].result, "Dependency fetch did not complete")
  }

  func testMaterializeToolInputInjectsCompletedOutputsOnlyWhenAllowed() {
    let source = action(
      "source",
      target: "Research Agent",
      status: .completed,
      result: "Primary result",
      parameters: ["node_ref": "research"]
    )
    let failed = action("failed", target: "Verifier", status: .failed, result: "Should not appear")
    let target = action(
      "target",
      kind: .callConnector,
      description: "Synthesize",
      parameters: [
        "prompt": "Review",
        "use_outputs_from": "source,failed,missing"
      ]
    )
    let plan = self.plan(actions: [source, failed, target])

    let materialized = AgentToolCoordination.materializeToolInput(
      plan: plan,
      action: target,
      allowOutputHandoff: true
    )
    let unchanged = AgentToolCoordination.materializeToolInput(
      plan: plan,
      action: target,
      allowOutputHandoff: false
    )
    let prompt = materialized.parameters["prompt"] ?? ""

    XCTAssertTrue(prompt.hasPrefix("Review\n\nDependency outputs follow."))
    XCTAssertTrue(prompt.contains("[research] Research Agent:\nPrimary result"))
    XCTAssertFalse(prompt.contains("Should not appear"))
    XCTAssertEqual(unchanged.parameters["prompt"], "Review")
    XCTAssertTrue(AgentToolCoordination.hasOutputHandoff(from: "source", in: plan))
    XCTAssertFalse(AgentToolCoordination.hasOutputHandoff(from: "missing", in: plan))
  }

  func testToolGraphDepthHandlesChainsAndCycles() {
    let chain = plan(actions: [
      action("prepare"),
      action("analyze", parameters: ["depends_on": "prepare"]),
      action("write", parameters: ["depends_on": "analyze"])
    ])
    let cycle = plan(actions: [
      action("a", parameters: ["depends_on": "b"]),
      action("b", parameters: ["depends_on": "a"])
    ])

    XCTAssertEqual(AgentToolCoordination.toolGraphDepth(chain), 3)
    XCTAssertEqual(AgentToolCoordination.toolGraphDepth(cycle), Int.max)
  }

  private func plan(
    actions: [AgentAction],
    actionHistory: [AgentAction] = []
  ) -> AgentPlan {
    AgentPlan(
      goal: "Coordinate tools",
      screen: AgentScreenContext(foregroundApp: "GalaxySSI"),
      steps: [],
      actions: actions,
      confirmationRequired: true,
      actionHistory: actionHistory
    )
  }

  private func action(
    _ id: String,
    kind: AgentActionKind = .draftPlan,
    target: String = "GalaxySSI",
    status: AgentActionStatus = .proposed,
    result: String = "",
    parameters: [String: String] = [:]
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: kind,
      target: target,
      risk: .low,
      status: status,
      description: "Action \(id)",
      parameters: parameters,
      requiresConfirmation: false,
      result: result
    )
  }
}
