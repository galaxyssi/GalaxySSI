import XCTest
@testable import GalaxySSI

final class GlobalLongHorizonGoalPolicyTests: XCTestCase {
  func testDurableCognitionCreatesPersistentLongHorizonGoal() {
    let task = cognition(
      durable: true,
      goal: "Ship a reliable on-device Agent runtime",
      result: GlobalModelUnderstanding(
        topic: "GalaxySSI runtime",
        goals: ["Ship a reliable on-device Agent runtime"],
        actions: [GlobalAutonomousAction(kind: .createTopic, goal: "Create project workspace", priority: 0.9)],
        confidence: 0.82
      )
    )

    let goals = GlobalLongHorizonGoalPolicy.mergeCognition(
      task: task,
      current: [],
      nowMillis: 1_000
    )

    XCTAssertEqual(goals.count, 1)
    XCTAssertEqual(goals.first?.title, "Ship a reliable on-device Agent runtime")
    XCTAssertEqual(goals.first?.topic, "GalaxySSI runtime")
    XCTAssertEqual(goals.first?.priority, 0.9)
    XCTAssertEqual(goals.first?.checkpointIntervalMillis, 60 * 60 * 1_000)
    XCTAssertTrue((goals.first?.nextCheckAtMillis ?? 0) > 1_000)
  }

  func testNonDurableConversationDoesNotBecomeLongHorizonGoal() {
    let task = cognition(
      durable: false,
      goal: "Answer this one question",
      result: GlobalModelUnderstanding(
        goals: ["Answer this one question"],
        confidence: 0.9
      )
    )

    XCTAssertTrue(
      GlobalLongHorizonGoalPolicy.mergeCognition(
        task: task,
        current: [],
        nowMillis: 1_000
      ).isEmpty
    )
  }

  func testSimilarDurableCognitionUpdatesOneGoalInsteadOfDuplicatingIt() {
    let first = cognition(
      id: "cognition-1",
      eventId: "event-1",
      durable: true,
      goal: "Build a reliable on-device Agent runtime",
      result: GlobalModelUnderstanding(
        topic: "GalaxySSI runtime",
        goals: ["Build a reliable on-device Agent runtime"],
        confidence: 0.75
      )
    )
    let current = GlobalLongHorizonGoalPolicy.mergeCognition(
      task: first,
      current: [],
      nowMillis: 1_000
    )
    let second = cognition(
      id: "cognition-2",
      eventId: "event-2",
      durable: true,
      goal: "Build a reliable on-device Agent runtime",
      result: GlobalModelUnderstanding(
        topic: "GalaxySSI runtime",
        goals: ["Build a reliable on-device Agent runtime"],
        confidence: 0.9
      )
    )

    let merged = GlobalLongHorizonGoalPolicy.mergeCognition(
      task: second,
      current: current,
      nowMillis: 2_000
    )

    XCTAssertEqual(merged.count, 1)
    XCTAssertEqual(merged.first?.sourceEventIds, ["event-1", "event-2"])
    XCTAssertEqual(merged.first?.confidence, 0.9)
  }

  func testCognitionDependencyProposalsFeedGoalGraph() {
    let task = cognition(
      durable: true,
      goal: "Ship mobile Agent",
      result: GlobalModelUnderstanding(
        topic: "GalaxySSI",
        goals: ["Build runtime", "Ship mobile Agent"],
        goalDependencies: [
          GlobalGoalDependencyProposal(goal: "Ship mobile Agent", dependsOn: "Build runtime")
        ],
        confidence: 0.82
      )
    )

    let goals = GlobalLongHorizonGoalPolicy.mergeCognition(
      task: task,
      current: [],
      nowMillis: 1_000
    )
    let prerequisite = goals.first { $0.title == "Build runtime" }
    let dependent = goals.first { $0.title == "Ship mobile Agent" }

    XCTAssertEqual(goals.count, 2)
    XCTAssertEqual(dependent?.dependencyGoalIds, Set([prerequisite?.id ?? ""]))
    XCTAssertEqual(dependent?.status, .waitingDependency)
  }

  func testRepeatedLowCostWorldEvidenceCreatesGoalWithoutModelAvailability() {
    let world = PersonalWorldModel(items: [
      worldItem(
        "world-goal",
        kind: .goal,
        topic: "GalaxySSI runtime",
        value: "Build a reliable on-device Agent runtime",
        confidence: 0.82,
        evidenceCount: 2,
        conversationIds: ["conversation-a", "conversation-b"],
        evidenceEventIds: ["event-a", "event-b"]
      )
    ])

    let goals = GlobalLongHorizonGoalPolicy.mergeWorld(
      world: world,
      current: [],
      nowMillis: 1_000
    )

    XCTAssertEqual(goals.count, 1)
    XCTAssertEqual(goals.first?.sourceConversationIds, Set(["conversation-a", "conversation-b"]))
    XCTAssertEqual(goals.first?.sourceEventIds, ["event-a", "event-b"])
    XCTAssertEqual(goals.first?.nextCheckAtMillis, 1_000 + 5 * 60 * 1_000)
  }

  func testUnchangedWorldEvidenceDoesNotChurnDurableGoalStore() {
    let world = PersonalWorldModel(items: [
      worldItem(
        "world-goal",
        kind: .goal,
        topic: "GalaxySSI runtime",
        value: "Build the persistent global Agent",
        confidence: 0.84,
        evidenceCount: 2,
        conversationIds: ["conversation-a"],
        evidenceEventIds: ["event-a", "event-b"]
      )
    ])
    let first = GlobalLongHorizonGoalPolicy.mergeWorld(
      world: world,
      current: [],
      nowMillis: 1_000
    )

    let second = GlobalLongHorizonGoalPolicy.mergeWorld(
      world: world,
      current: first,
      nowMillis: 2_000
    )

    XCTAssertEqual(first, second)
  }

  func testGoalSchedulerChoosesUrgentDueGoalsBeforeRoutineGoals() {
    let routine = goal("routine", title: "routine", priority: 0.4, nextCheckAtMillis: 100)
    let urgent = goal("urgent", title: "urgent", priority: 0.95, nextCheckAtMillis: 100)
    let paused = goal("paused", title: "paused", status: .paused, priority: 1.0, nextCheckAtMillis: 50)
    let future = goal("future", title: "future", priority: 1.0, nextCheckAtMillis: 200)

    let due = GlobalLongHorizonGoalPolicy.nextDue(
      goals: [routine, paused, future, urgent],
      nowMillis: 101
    )

    XCTAssertEqual(due.map(\.title), ["urgent", "routine"])
  }

  func testOrphanedInProgressGoalReturnsToDueQueue() {
    let orphaned = goal(
      "orphaned",
      title: "orphaned",
      status: .inProgress,
      priority: 0.8,
      nextCheckAtMillis: 100
    )
    let activelyRunning = goal(
      "running",
      title: "running",
      status: .inProgress,
      priority: 0.9,
      activeRunId: "run-id",
      nextCheckAtMillis: 100
    )
    let activelyThinking = goal(
      "thinking",
      title: "thinking",
      status: .active,
      priority: 1.0,
      activeCognitionTaskId: "cognition-id",
      nextCheckAtMillis: 100
    )

    let due = GlobalLongHorizonGoalPolicy.nextDue(
      goals: [activelyRunning, orphaned, activelyThinking],
      nowMillis: 101
    )

    XCTAssertEqual(due.map(\.title), ["orphaned"])
  }

  func testVerifiedLongHorizonCompletionClosesMatchingWorldGoal() {
    let item = worldItem(
      "world-goal",
      kind: .goal,
      topic: "GalaxySSI",
      value: "Build the persistent global Agent",
      confidence: 0.8
    )
    let unrelated = worldItem(
      "world-other",
      kind: .goal,
      topic: "Travel",
      value: "Book tickets",
      confidence: 0.9
    )
    let completed = goal(
      "goal-completed",
      title: "Build the persistent global Agent",
      topic: "GalaxySSI",
      status: .completed,
      confidence: 0.9,
      verifiedAtMillis: 1_500
    )

    let world = GlobalLongHorizonGoalPolicy.applyGoalStatesToWorld(
      world: PersonalWorldModel(items: [item, unrelated]),
      goals: [completed],
      nowMillis: 2_000
    )

    XCTAssertEqual(world.items.first { $0.id == item.id }?.status, .completed)
    XCTAssertEqual(world.items.first { $0.id == item.id }?.lastSeenAtMillis, 2_000)
    XCTAssertEqual(world.items.first { $0.id == unrelated.id }?.status, .active)
    XCTAssertEqual(world.updatedAtMillis, 2_000)
  }

  func testWorldGoalCompletionRequiresVerificationAndConfidence() {
    let item = worldItem(
      "world-goal",
      kind: .goal,
      topic: "GalaxySSI",
      value: "Build the persistent global Agent",
      confidence: 0.8
    )
    let unverified = goal(
      "goal-unverified",
      title: "Build the persistent global Agent",
      topic: "GalaxySSI",
      status: .completed,
      confidence: 0.9,
      verifiedAtMillis: 0
    )
    let lowConfidence = goal(
      "goal-low",
      title: "Build the persistent global Agent",
      topic: "GalaxySSI",
      status: .completed,
      confidence: 0.64,
      verifiedAtMillis: 1_500
    )

    let world = PersonalWorldModel(items: [item])

    XCTAssertEqual(
      GlobalLongHorizonGoalPolicy.applyGoalStatesToWorld(
        world: world,
        goals: [unverified, lowConfidence],
        nowMillis: 2_000
      ),
      world
    )
  }

  func testCompletionEvidenceSelectsVerifiedOrHighConfidenceFactEvidence() {
    let goal = self.goal(
      "goal",
      title: "Ship iOS native executor",
      topic: "GalaxySSI iOS",
      status: .inProgress
    )
    let completed = worldItem(
      "completed",
      kind: .task,
      topic: "GalaxySSI iOS",
      value: "Ship iOS native executor integration",
      confidence: 0.7,
      evidenceEventIds: ["event-completed"],
      status: .completed
    )
    let fact = worldItem(
      "fact",
      kind: .fact,
      topic: "GalaxySSI iOS",
      value: "Native executor receipt is verified",
      confidence: 0.88,
      evidenceEventIds: ["event-fact"]
    )
    let lowConfidenceFact = worldItem(
      "low-fact",
      kind: .fact,
      topic: "GalaxySSI iOS",
      value: "Executor is maybe verified",
      confidence: 0.5,
      evidenceEventIds: ["event-low"]
    )
    let noEvidence = worldItem(
      "no-evidence",
      kind: .fact,
      topic: "GalaxySSI iOS",
      value: "Native executor integration",
      confidence: 0.99
    )

    let evidence = GlobalLongHorizonGoalPolicy.completionEvidence(
      world: PersonalWorldModel(items: [lowConfidenceFact, noEvidence, completed, fact]),
      goal: goal,
      progressSummary: "executor verified",
      limit: 8
    )

    XCTAssertEqual(Set(evidence.map(\.id)), ["completed", "fact"])
    XCTAssertFalse(evidence.contains { $0.id == "low-fact" })
    XCTAssertFalse(evidence.contains { $0.id == "no-evidence" })
  }

  func testCompletionEvidenceLimitIsClampedToAndroidBounds() {
    let goal = self.goal(
      "goal",
      title: "Ship iOS native executor",
      topic: "GalaxySSI iOS"
    )
    let items = (0..<20).map {
      worldItem(
        "item-\($0)",
        kind: .fact,
        topic: "GalaxySSI iOS",
        value: "Ship iOS native executor evidence \($0)",
        confidence: 0.9,
        evidenceEventIds: ["event-\($0)"]
      )
    }

    let evidence = GlobalLongHorizonGoalPolicy.completionEvidence(
      world: PersonalWorldModel(items: items),
      goal: goal,
      limit: 80
    )

    XCTAssertEqual(evidence.count, 16)
  }

  private func goal(
    _ id: String,
    title: String,
    topic: String = "GalaxySSI",
    status: GlobalLongHorizonGoalStatus = .active,
    priority: Double = 0.5,
    confidence: Double = 0.8,
    activeCognitionTaskId: String = "",
    activeRunId: String = "",
    nextCheckAtMillis: Int64 = 0,
    verifiedAtMillis: Int64 = 0
  ) -> GlobalLongHorizonGoal {
    GlobalLongHorizonGoal(
      id: id,
      stableKey: "stable-\(id)",
      topic: topic,
      title: title,
      status: status,
      priority: priority,
      confidence: confidence,
      nextCheckAtMillis: nextCheckAtMillis,
      activeCognitionTaskId: activeCognitionTaskId,
      activeRunId: activeRunId,
      verifiedAtMillis: verifiedAtMillis
    )
  }

  private func worldItem(
    _ id: String,
    kind: GlobalWorldItemKind,
    topic: String,
    value: String,
    confidence: Double,
    evidenceCount: Int = 1,
    conversationIds: Set<String> = [],
    evidenceEventIds: [String] = [],
    status: GlobalWorldItemStatus = .active
  ) -> GlobalWorldItem {
    GlobalWorldItem(
      id: id,
      stableKey: "stable-\(id)",
      kind: kind,
      layer: .topic,
      topic: topic,
      value: value,
      confidence: confidence,
      evidenceCount: evidenceCount,
      conversationIds: conversationIds,
      evidenceEventIds: evidenceEventIds,
      status: status
    )
  }

  private func cognition(
    id: String = "cognition",
    eventId: String = "event",
    durable: Bool,
    goal: String,
    result: GlobalModelUnderstanding
  ) -> GlobalCognitionTask {
    GlobalCognitionTask(
      id: id,
      sourceEvent: GlobalConversationEvent(
        id: eventId,
        type: .messageCreated,
        conversationId: "conversation-a",
        actor: .user,
        content: goal,
        conversationTitle: "GalaxySSI"
      ),
      baselineUnderstanding: GlobalUnderstanding(
        topic: "GalaxySSI",
        goalCandidates: [goal],
        urgency: 0.6,
        durableFollowUpUseful: durable
      ),
      result: result
    )
  }
}
