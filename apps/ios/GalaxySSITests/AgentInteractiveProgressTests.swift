import XCTest
@testable import GalaxySSI

final class AgentInteractiveProgressTests: XCTestCase {
  func testSimpleChatTaskDoesNotShowProgress() {
    let result = AgentInteractiveProgressPolicy.project(
      task: task(goal: "Hello", phase: .completed),
      fallbackSteps: fallbackSteps
    )

    XCTAssertEqual(result, .hidden)
  }

  func testProjectsRealActionStatesForComplexTask() {
    let completed = action(id: "inspect", status: .completed, description: "Inspect repository")
    let running = action(id: "implement", status: .running, description: "Implement the feature")
    let pending = action(id: "verify", status: .proposed, description: "Verify the result")
    var record = task(goal: "Implement and verify this feature", phase: .executing)
    record.pendingActions = [completed, running, pending]
    record.executionLog = ["Repository inspected", "Editing iOS files"]

    let result = AgentInteractiveProgressPolicy.project(
      task: record,
      fallbackSteps: fallbackSteps
    )

    XCTAssertTrue(result.visible)
    XCTAssertEqual(result.steps.map(\.state), [.completed, .active, .pending])
    XCTAssertEqual(result.currentStep, 2)
    XCTAssertEqual(result.totalSteps, 3)
    XCTAssertEqual(result.summary, "Implement the feature")
    XCTAssertEqual(result.recentActivity, ["Repository inspected", "Editing iOS files"])
  }

  func testComplexTaskShowsFiveFallbackStagesBeforePlanArrives() {
    let record = task(
      goal: "Build the iOS app and open a pull request",
      phase: .planning
    )

    let result = AgentInteractiveProgressPolicy.project(
      task: record,
      fallbackSteps: fallbackSteps
    )

    XCTAssertTrue(result.visible)
    XCTAssertEqual(result.steps.map(\.state), [.active, .pending, .pending, .pending, .pending])
    XCTAssertEqual(result.currentStep, 1)
    XCTAssertEqual(result.totalSteps, 5)
    XCTAssertEqual(result.summary, "Understand request")
  }

  func testMultilineModelPlanBecomesIndividualProgressSteps() {
    var record = task(
      goal: "Analyze this complex design and verify the result",
      phase: .planning
    )
    record.executionLog = ["1. Confirm requirements\n2. Compare implementations\n3. Verify conclusion"]

    let result = AgentInteractiveProgressPolicy.project(
      task: record,
      fallbackSteps: fallbackSteps
    )

    XCTAssertTrue(result.visible)
    XCTAssertEqual(
      result.steps.map(\.text),
      ["Confirm requirements", "Compare implementations", "Verify conclusion"]
    )
    XCTAssertEqual(result.steps.map(\.state), [.active, .pending, .pending])
    XCTAssertEqual(result.counter, "1/3")
  }

  func testSingleActionSupervisedProjectStillShowsProgress() {
    let waiting = action(id: "delegate", status: .waitingResponse, description: "Ask Codex Agent")
    var record = task(goal: "Execute this task", phase: .waitingResponse)
    record.pendingActions = [waiting]
    record.planContext = planContext(actions: [waiting], plannerProfile: "phone-supervised-project")

    let result = AgentInteractiveProgressPolicy.project(
      task: record,
      fallbackSteps: fallbackSteps
    )

    XCTAssertTrue(result.visible)
    XCTAssertEqual(result.counter, "1/1")
    XCTAssertEqual(result.steps.count, 1)
    XCTAssertEqual(result.steps.first?.state, .active)
  }

  func testCompletedTaskMarksEveryFallbackStageComplete() {
    let record = task(
      goal: "Implement a repository change",
      phase: .completed
    )

    let result = AgentInteractiveProgressPolicy.project(
      task: record,
      fallbackSteps: fallbackSteps
    )

    XCTAssertTrue(result.visible)
    XCTAssertFalse(result.running)
    XCTAssertEqual(
      result.steps.map(\.state),
      [.completed, .completed, .completed, .completed, .completed]
    )
    XCTAssertEqual(result.completedSteps, 5)
  }

  private var fallbackSteps: [String] {
    ["Understand request", "Prepare plan", "Run task", "Verify result", "Finish task"]
  }

  private func task(goal: String, phase: AgentPhase) -> AgentTaskRecord {
    AgentTaskRecord(
      taskId: "task-1",
      sessionId: "session-1",
      goal: goal,
      phase: phase,
      routeKind: .localModel,
      targetTitle: "GalaxySSI Agent",
      risk: .low,
      blocked: false
    )
  }

  private func action(
    id: String,
    status: AgentActionStatus,
    description: String
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: .draftPlan,
      target: "GalaxySSI Agent",
      risk: .low,
      status: status,
      description: description,
      requiresConfirmation: false
    )
  }

  private func planContext(
    actions: [AgentAction],
    plannerProfile: String
  ) -> AgentTaskPlanContext {
    AgentTaskPlanContext(
      plan: AgentPlan(
        goal: "Execute this task",
        screen: AgentScreenContext(foregroundApp: ""),
        steps: [],
        actions: actions,
        confirmationRequired: false,
        plannerProfile: plannerProfile
      )
    )
  }
}
