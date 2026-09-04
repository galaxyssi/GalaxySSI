import XCTest
@testable import GalaxySSI

final class AgentPlanEditorTests: XCTestCase {
  func testUpdatePendingActionEditsAndroidInputKeyAndRevalidatesPlan() throws {
    let original = plan(
      actions: [
        action(
          "connector",
          kind: .callConnector,
          description: "Ask old question",
          parameters: ["prompt": "old prompt"]
        )
      ],
      route: AgentRoute(kind: .cloudModel, targetTitle: "Cloud"),
      routeRationale: "Model route. User edit: stale.",
      revision: 4
    )

    let result = AgentPlanEditor.updatePendingAction(
      plan: original,
      actionId: "connector",
      description: "  Ask refined question  ",
      input: "  refined prompt  "
    )
    let edited = try XCTUnwrap(result.plan)
    let editedAction = try XCTUnwrap(edited.actions.first)

    XCTAssertTrue(result.success)
    XCTAssertEqual(edited.revision, 5)
    XCTAssertEqual(edited.routeRationale, "Model route. User edit: updated:connector.")
    XCTAssertEqual(edited.actions.count, 1)
    XCTAssertEqual(editedAction.description, "Ask refined question")
    XCTAssertEqual(editedAction.parameters["prompt"], "refined prompt")
    XCTAssertEqual(AgentPlanEditor.inputValue(action: editedAction), "refined prompt")
    XCTAssertTrue(edited.validation.valid)
  }

  func testUpdatePendingActionRejectsCompletedAndBlankInputEdits() {
    let completed = plan(actions: [
      action("done", kind: .typeText, status: .completed, parameters: ["text": "old"])
    ])
    let blank = plan(actions: [
      action("type", kind: .typeText, parameters: ["text": "old"])
    ])

    XCTAssertEqual(
      AgentPlanEditor.updatePendingAction(
        plan: completed,
        actionId: "done",
        description: "New text",
        input: "updated"
      ).error,
      "Only pending actions can be edited"
    )
    XCTAssertEqual(
      AgentPlanEditor.updatePendingAction(
        plan: blank,
        actionId: "type",
        description: "New text",
        input: "   "
      ).error,
      "Action input cannot be empty"
    )
  }

  func testRemovePendingActionProtectsDependenciesAndRevalidatesPlan() throws {
    let original = plan(actions: [
      action("read", description: "Read source"),
      action("summarize", description: "Summarize source", parameters: ["depends_on": " read "])
    ])

    let blocked = AgentPlanEditor.removePendingAction(plan: original, actionId: "read")
    let removed = AgentPlanEditor.removePendingAction(plan: original, actionId: "summarize")
    let edited = try XCTUnwrap(removed.plan)

    XCTAssertEqual(blocked.error, "Remove dependent action Summarize source first")
    XCTAssertTrue(removed.success)
    XCTAssertEqual(edited.actions.map(\.id), ["read"])
    XCTAssertEqual(edited.revision, 2)
    XCTAssertEqual(edited.routeRationale, " User edit: removed:summarize.")
    XCTAssertTrue(edited.validation.valid)
  }

  func testMovePendingActionMatchesAndroidBoundariesAndStatuses() throws {
    let movable = plan(actions: [
      action("first"),
      action("second"),
      action("third")
    ])
    let moved = AgentPlanEditor.movePendingAction(plan: movable, actionId: "third", offset: -1)
    let edited = try XCTUnwrap(moved.plan)

    XCTAssertEqual(edited.actions.map(\.id), ["first", "third", "second"])
    XCTAssertEqual(edited.routeRationale, " User edit: moved:third:-1.")
    XCTAssertEqual(
      AgentPlanEditor.movePendingAction(plan: movable, actionId: "first", offset: -1).error,
      "Action is already at the plan boundary"
    )
    XCTAssertEqual(
      AgentPlanEditor.movePendingAction(plan: movable, actionId: "first", offset: 2).error,
      "Unsupported move"
    )

    let blockedByCompletedNeighbor = plan(actions: [
      action("first"),
      action("done", status: .completed)
    ])
    XCTAssertEqual(
      AgentPlanEditor.movePendingAction(
        plan: blockedByCompletedNeighbor,
        actionId: "first",
        offset: 1
      ).error,
      "Completed or running actions cannot be reordered"
    )
  }

  private func plan(
    actions: [AgentAction],
    route: AgentRoute = AgentRoute(),
    routeRationale: String = "",
    revision: Int = 1
  ) -> AgentPlan {
    var value = AgentPlan(
      goal: "Complete task",
      screen: AgentScreenContext(foregroundApp: "GalaxySSI"),
      steps: [],
      actions: actions,
      confirmationRequired: true,
      routeRationale: routeRationale,
      route: route,
      revision: revision
    )
    value.validation = AgentPlanValidator.validate(value)
    return value
  }

  private func action(
    _ id: String,
    kind: AgentActionKind = .draftPlan,
    status: AgentActionStatus = .proposed,
    description: String = "Do \(UUID().uuidString)",
    parameters: [String: String] = [:]
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: kind,
      target: "GalaxySSI",
      risk: .low,
      status: status,
      description: description,
      parameters: parameters,
      requiresConfirmation: false
    )
  }
}
