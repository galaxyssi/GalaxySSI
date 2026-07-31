import XCTest
@testable import SignalASI

final class GlobalLongHorizonGoalPolicyTests: XCTestCase {
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
      topic: "SignalASI",
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
      topic: "SignalASI",
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
      topic: "SignalASI",
      value: "Build the persistent global Agent",
      confidence: 0.8
    )
    let unverified = goal(
      "goal-unverified",
      title: "Build the persistent global Agent",
      topic: "SignalASI",
      status: .completed,
      confidence: 0.9,
      verifiedAtMillis: 0
    )
    let lowConfidence = goal(
      "goal-low",
      title: "Build the persistent global Agent",
      topic: "SignalASI",
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
      topic: "SignalASI iOS",
      status: .inProgress
    )
    let completed = worldItem(
      "completed",
      kind: .task,
      topic: "SignalASI iOS",
      value: "Ship iOS native executor integration",
      confidence: 0.7,
      evidenceEventIds: ["event-completed"],
      status: .completed
    )
    let fact = worldItem(
      "fact",
      kind: .fact,
      topic: "SignalASI iOS",
      value: "Native executor receipt is verified",
      confidence: 0.88,
      evidenceEventIds: ["event-fact"]
    )
    let lowConfidenceFact = worldItem(
      "low-fact",
      kind: .fact,
      topic: "SignalASI iOS",
      value: "Executor is maybe verified",
      confidence: 0.5,
      evidenceEventIds: ["event-low"]
    )
    let noEvidence = worldItem(
      "no-evidence",
      kind: .fact,
      topic: "SignalASI iOS",
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
      topic: "SignalASI iOS"
    )
    let items = (0..<20).map {
      worldItem(
        "item-\($0)",
        kind: .fact,
        topic: "SignalASI iOS",
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
    topic: String = "SignalASI",
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
      evidenceEventIds: evidenceEventIds,
      status: status
    )
  }
}
