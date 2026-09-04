import XCTest
@testable import GalaxySSI

final class GlobalLongHorizonCoordinatorTests: XCTestCase {
  func testDisabledSettingsSkipLongHorizonCycle() {
    let runtime = MockLongHorizonRuntime(
      settings: GlobalAgentSettings(enabled: false, longHorizonPlanningEnabled: true)
    )
    let goalStore = InMemoryGlobalLongHorizonGoalStore(goals: [
      goal("goal-disabled", title: "Do not run while disabled", nextCheckAtMillis: 100)
    ])
    let coordinator = GlobalLongHorizonCoordinator(runtimeStore: runtime, goalStore: goalStore)

    let result = coordinator.processDue(nowMillis: 1_000)

    XCTAssertEqual(result, GlobalLongHorizonCycleResult(
      reconciledGoalCount: 0,
      queuedCheckpointCount: 0,
      nextWakeAtMillis: 0
    ))
    XCTAssertTrue(runtime.cognition.isEmpty)
    XCTAssertEqual(coordinator.goals().first?.status, .active)
  }

  func testDueGoalQueuesCheckpointCognitionAndDeduplicatesActiveWork() throws {
    let runtime = MockLongHorizonRuntime()
    let source = goal(
      "goal-due",
      title: "Review durable iOS Agent work",
      priority: 0.9,
      sourceConversationIds: ["conversation-a"],
      sourceEventIds: ["event-a"],
      nextCheckAtMillis: 900,
      checkpointIntervalMillis: 3_600_000
    )
    let goalStore = InMemoryGlobalLongHorizonGoalStore(goals: [source])
    let coordinator = GlobalLongHorizonCoordinator(runtimeStore: runtime, goalStore: goalStore)

    let first = coordinator.processDue(nowMillis: 1_000)

    XCTAssertEqual(first.queuedCheckpointCount, 1)
    XCTAssertEqual(runtime.cognition.count, 1)
    let task = try XCTUnwrap(runtime.cognition.first)
    XCTAssertEqual(task.longHorizonGoalId, source.id)
    XCTAssertEqual(task.sourceEvent.id, "long-horizon-checkpoint:\(source.id):1")
    XCTAssertEqual(task.sourceEvent.metadata["origin"], "global_long_horizon_scheduler")
    XCTAssertEqual(task.sourceEvent.causalEventIds, ["event-a"])

    let updated = try XCTUnwrap(coordinator.goals().first)
    XCTAssertEqual(updated.status, .inProgress)
    XCTAssertEqual(updated.activeCognitionTaskId, task.id)
    XCTAssertEqual(updated.lastCheckAtMillis, 1_000)
    XCTAssertEqual(updated.checkpointCount, 0)
    XCTAssertEqual(updated.nextCheckAtMillis, 3_601_000)

    let second = coordinator.processDue(nowMillis: 1_001)
    XCTAssertEqual(second.queuedCheckpointCount, 0)
    XCTAssertEqual(runtime.cognition.count, 1)
  }

  func testWorldEvidenceCreatesStoredGoalWithoutImmediateCheckpoint() throws {
    let runtime = MockLongHorizonRuntime()
    runtime.world = PersonalWorldModel(items: [
      GlobalWorldItem(
        stableKey: "world-goal",
        kind: .goal,
        layer: .topic,
        topic: "GalaxySSI runtime",
        value: "Maintain the iOS Agent parity roadmap",
        confidence: 0.86,
        evidenceCount: 3,
        conversationIds: ["conversation-a", "conversation-b"],
        evidenceEventIds: ["event-a", "event-b"],
        lastSeenAtMillis: 900
      )
    ])
    let goalStore = InMemoryGlobalLongHorizonGoalStore()
    let coordinator = GlobalLongHorizonCoordinator(runtimeStore: runtime, goalStore: goalStore)

    let result = coordinator.processDue(nowMillis: 1_000)

    XCTAssertEqual(result.reconciledGoalCount, 1)
    XCTAssertEqual(result.queuedCheckpointCount, 0)
    let stored = try XCTUnwrap(coordinator.goals().first)
    XCTAssertEqual(stored.title, "Maintain the iOS Agent parity roadmap")
    XCTAssertGreaterThan(stored.nextCheckAtMillis, 1_000)
    XCTAssertEqual(runtime.cognition.count, 0)
    XCTAssertEqual(result.nextWakeAtMillis, stored.nextCheckAtMillis)
  }

  func testFailedCheckpointBlocksGoalAndEmitsLifecycleMessage() throws {
    let failedTask = cognition(
      id: "cognition-failed",
      goalId: "goal-blocked",
      status: .failed,
      lastError: "No authorized model resource"
    )
    let runtime = MockLongHorizonRuntime(cognition: [failedTask])
    let source = goal(
      "goal-blocked",
      title: "Track release readiness",
      status: .inProgress,
      priority: 0.6,
      activeCognitionTaskId: failedTask.id,
      nextCheckAtMillis: 900
    )
    let goalStore = InMemoryGlobalLongHorizonGoalStore(goals: [source])
    let coordinator = GlobalLongHorizonCoordinator(runtimeStore: runtime, goalStore: goalStore)

    let result = coordinator.processDue(nowMillis: 2_000)

    XCTAssertEqual(result.queuedCheckpointCount, 0)
    let blocked = try XCTUnwrap(coordinator.goals().first)
    XCTAssertEqual(blocked.status, .blocked)
    XCTAssertEqual(blocked.previousStatus, .inProgress)
    XCTAssertEqual(blocked.activeCognitionTaskId, "")
    XCTAssertEqual(blocked.blocker, "No authorized model resource")
    XCTAssertEqual(blocked.nextCheckAtMillis, 3_602_000)
    XCTAssertEqual(runtime.messages.count, 1)
    XCTAssertEqual(runtime.messages.first?.target, .globalDigest)
  }

  func testCompletedRunClosesGoalAndWorldGoal() throws {
    let action = GlobalAutonomousAction(
      kind: .analyze,
      goal: "Verify completion",
      status: .completed,
      result: "Native execution receipt verified",
      verificationStatus: .supported,
      completedAtMillis: 1_900
    )
    let run = GlobalAutonomousRun(
      id: "run-complete",
      sourceCognitionTaskId: "cognition-complete",
      sourceEventId: "event-a",
      sourceConversationId: "conversation-a",
      topic: "GalaxySSI runtime",
      goal: "Ship iOS long horizon coordinator",
      actions: [action],
      status: .completed,
      outcomeSummary: "Coordinator checkpoint satisfied",
      review: GlobalAutonomousRunReview(
        decision: GlobalRunReplanDecision(
          goalState: .completed,
          summary: "Coordinator checkpoint satisfied",
          confidence: 0.9
        )
      ),
      updatedAtMillis: 2_000
    )
    let runtime = MockLongHorizonRuntime(runs: [run])
    runtime.world = PersonalWorldModel(items: [
      GlobalWorldItem(
        stableKey: "world-goal",
        kind: .goal,
        layer: .topic,
        topic: "GalaxySSI runtime",
        value: "Ship iOS long horizon coordinator",
        confidence: 0.9,
        evidenceCount: 2,
        conversationIds: ["conversation-a"],
        evidenceEventIds: ["event-a"]
      )
    ])
    let source = goal(
      "goal-complete",
      title: "Ship iOS long horizon coordinator",
      status: .inProgress,
      activeRunId: run.id,
      sourceConversationIds: ["conversation-a"],
      sourceEventIds: ["event-a"]
    )
    let goalStore = InMemoryGlobalLongHorizonGoalStore(goals: [source])
    let coordinator = GlobalLongHorizonCoordinator(runtimeStore: runtime, goalStore: goalStore)

    let result = coordinator.processDue(nowMillis: 2_000)

    XCTAssertEqual(result.queuedCheckpointCount, 0)
    let completed = try XCTUnwrap(coordinator.goals().first)
    XCTAssertEqual(completed.status, .completed)
    XCTAssertEqual(completed.previousStatus, .inProgress)
    XCTAssertEqual(completed.activeRunId, "")
    XCTAssertEqual(completed.verifiedAtMillis, 2_000)
    XCTAssertTrue(completed.verificationSummary.contains("1 action evidence"))
    XCTAssertEqual(runtime.world.items.first?.status, .completed)
    XCTAssertEqual(runtime.messages.count, 1)
    XCTAssertEqual(runtime.messages.first?.target, .newConversation)
  }

  func testPauseAndResumeAdjustGoalScheduling() throws {
    let runtime = MockLongHorizonRuntime()
    let source = goal("goal-pause", title: "Pause and resume me", nextCheckAtMillis: 500)
    let goalStore = InMemoryGlobalLongHorizonGoalStore(goals: [source])
    let coordinator = GlobalLongHorizonCoordinator(runtimeStore: runtime, goalStore: goalStore)

    XCTAssertTrue(coordinator.pause(goalId: source.id, nowMillis: 1_000))
    let paused = try XCTUnwrap(coordinator.goals().first)
    XCTAssertEqual(paused.status, .paused)
    XCTAssertEqual(paused.previousStatus, .active)
    XCTAssertEqual(paused.nextCheckAtMillis, 0)

    XCTAssertTrue(coordinator.resume(goalId: source.id, nowMillis: 2_000))
    let resumed = try XCTUnwrap(coordinator.goals().first)
    XCTAssertEqual(resumed.status, .active)
    XCTAssertEqual(resumed.previousStatus, .paused)
    XCTAssertEqual(resumed.nextCheckAtMillis, 2_000)
  }
}

private final class MockLongHorizonRuntime: GlobalLongHorizonRuntimeStore {
  var settingsValue: GlobalAgentSettings
  var world: PersonalWorldModel
  var graph: GlobalTopicProjectGraph
  var cognition: [GlobalCognitionTask]
  var runs: [GlobalAutonomousRun]
  var messages: [GlobalProactiveMessage]

  init(
    settings: GlobalAgentSettings = GlobalAgentSettings(),
    world: PersonalWorldModel = PersonalWorldModel(),
    graph: GlobalTopicProjectGraph = GlobalTopicProjectGraph(),
    cognition: [GlobalCognitionTask] = [],
    runs: [GlobalAutonomousRun] = [],
    messages: [GlobalProactiveMessage] = []
  ) {
    self.settingsValue = settings
    self.world = world
    self.graph = graph
    self.cognition = cognition
    self.runs = runs
    self.messages = messages
  }

  func settings() -> GlobalAgentSettings {
    settingsValue
  }

  func loadWorld() -> PersonalWorldModel {
    world
  }

  func saveWorld(_ world: PersonalWorldModel) {
    self.world = world
  }

  func topicGraph() -> GlobalTopicProjectGraph {
    graph
  }

  func cognitionTasks() -> [GlobalCognitionTask] {
    cognition
  }

  func upsertCognitionTask(_ task: GlobalCognitionTask) {
    cognition.removeAll { $0.id == task.id }
    cognition.append(task)
  }

  func autonomousRuns() -> [GlobalAutonomousRun] {
    runs
  }

  func appendProactiveMessage(_ message: GlobalProactiveMessage) {
    guard !messages.contains(where: { $0.id == message.id }) else {
      return
    }
    messages.append(message)
  }
}

private func goal(
  _ id: String,
  title: String,
  status: GlobalLongHorizonGoalStatus = .active,
  priority: Double = 0.8,
  activeCognitionTaskId: String = "",
  activeRunId: String = "",
  sourceConversationIds: Set<String> = ["conversation"],
  sourceEventIds: [String] = ["event"],
  nextCheckAtMillis: Int64 = 1_000,
  checkpointIntervalMillis: Int64 = 86_400_000
) -> GlobalLongHorizonGoal {
  GlobalLongHorizonGoal(
    id: id,
    stableKey: GlobalAgentText.stableKey("coordinator-test", title),
    topic: "GalaxySSI runtime",
    title: title,
    status: status,
    priority: priority,
    sourceConversationIds: sourceConversationIds,
    sourceEventIds: sourceEventIds,
    checkpointIntervalMillis: checkpointIntervalMillis,
    nextCheckAtMillis: nextCheckAtMillis,
    activeCognitionTaskId: activeCognitionTaskId,
    activeRunId: activeRunId,
    createdAtMillis: 100,
    updatedAtMillis: 100
  )
}

private func cognition(
  id: String,
  goalId: String,
  status: GlobalCognitionTaskStatus,
  lastError: String = ""
) -> GlobalCognitionTask {
  GlobalCognitionTask(
    id: id,
    sourceEvent: GlobalConversationEvent(
      id: "event-\(id)",
      type: .taskUpdated,
      conversationId: "conversation",
      actor: .tool,
      timestampMillis: 1_000,
      content: "Checkpoint"
    ),
    baselineUnderstanding: GlobalUnderstanding(
      eventId: "event-\(id)",
      topic: "GalaxySSI runtime",
      intent: "long_horizon_checkpoint",
      goalCandidates: ["Track release readiness"],
      durableFollowUpUseful: true
    ),
    status: status,
    lastError: lastError,
    longHorizonGoalId: goalId,
    createdAtMillis: 1_000,
    updatedAtMillis: 1_500
  )
}
