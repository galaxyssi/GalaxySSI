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
    XCTAssertEqual(result.status, .waitingResponse)
    XCTAssertTrue(result.running)
    XCTAssertEqual(result.steps.first?.state, .waiting)
  }

  func testCompletedNarrationIsProcessHistoryNotVerifiedWork() {
    var record = task(goal: "Research and compare several sources", phase: .completed)
    record.executionLog = ["Define scope", "Compare sources", "Verify conclusion"]

    let result = AgentInteractiveProgressPolicy.project(task: record)

    XCTAssertTrue(result.visible)
    XCTAssertFalse(result.running)
    XCTAssertEqual(result.counter, "3/3")
    XCTAssertEqual(result.status, .completed)
    XCTAssertEqual(result.steps.map(\.state), [.recorded, .recorded, .recorded])
    XCTAssertEqual(result.completedSteps, 0)
  }

  func testStoppedPhasesDoNotPromoteAStaleActionOrUnexecutedPlan() {
    let cases: [(AgentPhase, AgentInteractiveProgressStatus, AgentInteractiveProgressStepState, AgentInteractiveProgressStepState)] = [
      (.waitingConfirmation, .waitingConfirmation, .waiting, .pending),
      (.paused, .paused, .paused, .pending),
      (.blocked, .blocked, .waiting, .pending),
      (.failed, .failed, .stopped, .notExecuted),
      (.cancelled, .cancelled, .stopped, .notExecuted),
      (.completed, .completed, .recorded, .notExecuted)
    ]
    for (phase, status, current, future) in cases {
      var record = task(goal: "Research and compare several sources", phase: phase)
      record.pendingActions = [
        action(id: "done", status: .completed, description: "Read one source"),
        action(id: "stale", status: .running, description: "Read another source"),
        action(id: "later", status: .proposed, description: "Verify the conclusion")
      ]
      let progress = AgentInteractiveProgressPolicy.project(task: record)
      XCTAssertEqual(progress.status, status)
      XCTAssertFalse(progress.running)
      XCTAssertEqual(progress.steps.map(\.state), [.completed, current, future])
      XCTAssertEqual(progress.completedSteps, 1)
    }
  }

  func testTerminalNarrationListDoesNotClaimUnexecutedSteps() {
    var record = task(goal: "Research and compare several sources", phase: .completed)
    record.executionLog = ["1. Gather sources\n2. Compare findings\n3. Verify conclusion"]
    XCTAssertEqual(AgentInteractiveProgressPolicy.project(task: record).steps.map(\.state),
      [.recorded, .notExecuted, .notExecuted])
    record.phase = .cancelled
    XCTAssertEqual(AgentInteractiveProgressPolicy.project(task: record).steps.map(\.state),
      [.stopped, .notExecuted, .notExecuted])
  }

  func testOwnedRuntimeAndStableFinalDeliveryResolveCachedPhase() {
    let waiting = AgentTranscriptExecutionProgress(status: .waitingResponse, startedAt: 1_000, updatedAt: 20_000)
    let completed = AgentTranscriptExecutionProgress(status: .completed, startedAt: 1_000, updatedAt: 44_000)
    XCTAssertEqual(AgentTranscriptExecutionProgress.resolve(owned: waiting, cached: completed, deliveredAt: 44_000),
      waiting)
    XCTAssertEqual(AgentTranscriptExecutionProgress.resolve(owned: nil, cached: waiting, deliveredAt: 44_000),
      completed)
    XCTAssertEqual(AgentTranscriptExecutionProgress.resolve(owned: nil, cached: waiting, deliveredAt: 19_000),
      waiting)
    let explicitStates: [AgentInteractiveProgressStatus] = [.failed, .cancelled, .paused, .blocked, .waitingConfirmation]
    for status in explicitStates {
      let state = AgentTranscriptExecutionProgress(status: status, startedAt: 1_000, updatedAt: 40_000)
      XCTAssertEqual(AgentTranscriptExecutionProgress.resolve(owned: nil, cached: state, deliveredAt: 44_000), state)
    }
  }

  func testFinalDeliveryIsScopedAndDoesNotUseStreamsOrMilestones() {
    func message(conversation: String = "first", time: TimeInterval, remoteId: String = "",
                 trace: String = "received", status: ChatDeliveryStatus = .delivered) -> ChatMessage {
      ChatMessage(contactId: "hermes", content: "Reply", isMine: false,
        createdAt: Date(timeIntervalSince1970: time), deliveryStatus: status,
        deliveryTrace: [DeliveryTraceEvent(stage: trace)], conversationId: conversation, turnId: "same-turn",
        remoteMessageId: remoteId)
    }
    let reply = message(time: 44)
    let other = message(conversation: "second", time: 51)
    let snapshots = AgentTranscriptExecutionProgress.finalDeliveryTimes([
      message(time: 8, remoteId: "agent-stream-42"),
      message(time: 9, trace: "collaboration_interim_milestone"),
      message(time: 12, trace: "local_agent_task_cancelled_received"),
      message(time: 13, status: .failed), reply, message(time: 49), other
    ])
    XCTAssertEqual(snapshots[.init(reply)], 44_000)
    XCTAssertEqual(snapshots[.init(other)], 51_000)
    XCTAssertEqual(snapshots.count, 2)
  }

  func testRollingPlanPreservesBatchesAndMarksRecoveredFailureAsAdjusted() {
    let previous = [
      action(id: "inspect", status: .completed, description: "Inspect project structure"),
      action(id: "r2-1-build", status: .failed, description: "Run the first build"),
      action(id: "r2-2-stale", status: .running, description: "Retired active action")
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
    XCTAssertEqual(result.steps.count, 6)
    XCTAssertEqual(
      result.steps.first { $0.actionId == "r2-1-build" }?.state,
      .superseded
    )
    XCTAssertEqual(result.counter, "2/3")
    XCTAssertEqual(result.planRevision, 3)
    XCTAssertEqual(result.summary, "Run tests again")
    XCTAssertEqual(result.steps.first { $0.actionId == "r2-2-stale" }?.state, .superseded)
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
