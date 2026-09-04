import XCTest
@testable import GalaxySSI

final class AgentInteractiveProgressTests: XCTestCase {
  func testSimpleChatTaskDoesNotShowProgress() {
    let result = AgentInteractiveProgressPolicy.project(
      task: task(goal: "Hello", phase: .completed)
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

    let result = AgentInteractiveProgressPolicy.project(task: record)

    XCTAssertTrue(result.visible)
    XCTAssertEqual(result.steps.map(\.state), [.completed, .active, .pending])
    XCTAssertEqual(result.currentStep, 2)
    XCTAssertEqual(result.totalSteps, 3)
    XCTAssertEqual(result.summary, "Implement the feature")
    XCTAssertEqual(result.recentActivity, ["Repository inspected", "Editing iOS files"])
  }

  func testComplexTaskDoesNotInventStagesBeforePlanArrives() {
    let record = task(
      goal: "Build the iOS app and open a pull request",
      phase: .planning
    )

    let result = AgentInteractiveProgressPolicy.project(task: record)

    XCTAssertFalse(result.visible)
  }

  func testMultilineModelPlanBecomesIndividualProgressSteps() {
    var record = task(
      goal: "Analyze this complex design and verify the result",
      phase: .planning
    )
    record.executionLog = ["1. Confirm requirements\n2. Compare implementations\n3. Verify conclusion"]

    let result = AgentInteractiveProgressPolicy.project(task: record)

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

    let result = AgentInteractiveProgressPolicy.project(task: record)

    XCTAssertTrue(result.visible)
    XCTAssertEqual(result.counter, "1/1")
    XCTAssertEqual(result.steps.count, 1)
    XCTAssertEqual(result.steps.first?.state, .active)
  }

  func testCompletedNarrationPlanReportsFinalStep() {
    var record = task(goal: "Research and compare several sources", phase: .completed)
    record.executionLog = ["Define scope", "Compare sources", "Verify conclusion"]

    let result = AgentInteractiveProgressPolicy.project(task: record)

    XCTAssertTrue(result.visible)
    XCTAssertFalse(result.running)
    XCTAssertEqual(result.counter, "3/3")
    XCTAssertEqual(result.completedSteps, 3)
  }

  func testRollingPlanPreservesBatchesAndMarksRecoveredFailureAsAdjusted() {
    let previous = [
      action(id: "inspect", status: .completed, description: "Inspect project structure"),
      action(id: "r2-1-build", status: .failed, description: "Run the first build")
    ]
    let current = [
      action(id: "r3-1-repair", status: .completed, description: "Repair build settings"),
      action(id: "r3-2-test", status: .running, description: "Run tests again"),
      action(id: "r3-3-publish", status: .proposed, description: "Publish the result")
    ]
    var plan = AgentPlan(
      goal: "Improve the project until release",
      screen: AgentScreenContext(foregroundApp: "GalaxySSI"),
      steps: [],
      actions: current,
      confirmationRequired: false,
      revision: 3,
      replanCount: 2,
      actionHistory: previous,
      checkpoints: [
        AgentExecutionCheckpoint(
          id: "checkpoint-inspect",
          actionId: "inspect",
          planRevision: 1,
          foregroundApp: "GalaxySSI",
          screenDigest: "verified"
        )
      ]
    )
    plan.plannerProfile = "phone-supervised-project"
    var record = task(goal: plan.goal, phase: .executing)
    record.activePlan = plan
    record.executionLog = ["The failed build now uses compatible settings"]

    let result = AgentInteractiveProgressPolicy.project(task: record)

    XCTAssertEqual(result.batches.map(\.planRevision), [1, 2, 3])
    XCTAssertEqual(result.steps.count, 5)
    XCTAssertEqual(
      result.steps.first { $0.actionId == "r2-1-build" }?.state,
      .superseded
    )
    XCTAssertEqual(result.counter, "2/3")
    XCTAssertEqual(result.planRevision, 3)
    XCTAssertEqual(result.summary, "Run tests again")
  }

  func testRepeatedDescriptionsAcrossPlanRevisionsRemainVisible() {
    let previous = action(id: "initial-test", status: .completed, description: "Run tests")
    let current = action(id: "r2-1-test", status: .running, description: "Run tests")
    let plan = AgentPlan(
      goal: "Implement and continuously verify the project",
      screen: AgentScreenContext(foregroundApp: "GalaxySSI"),
      steps: [],
      actions: [current],
      confirmationRequired: false,
      revision: 2,
      actionHistory: [previous]
    )
    var record = task(goal: plan.goal, phase: .executing)
    record.activePlan = plan

    let result = AgentInteractiveProgressPolicy.project(task: record)

    XCTAssertEqual(result.steps.count, 2)
    XCTAssertEqual(result.batches.map(\.planRevision), [1, 2])
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
