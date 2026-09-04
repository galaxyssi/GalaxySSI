import XCTest
@testable import GalaxySSI

final class GlobalLongHorizonLifecycleTests: XCTestCase {
  func testStampTransitionInitializesNewGoalStatusTime() {
    let stamped = GlobalLongHorizonLifecyclePolicy.stampTransition(
      previous: nil,
      next: goal("goal-new", title: "Track release", createdAtMillis: 1_000),
      nowMillis: 2_000
    )

    XCTAssertNil(stamped.previousStatus)
    XCTAssertEqual(stamped.statusChangedAtMillis, 1_000)
  }

  func testStampTransitionPreservesExistingStatusTimingWhenStatusIsUnchanged() {
    let previous = goal(
      "goal-existing",
      title: "Track release",
      status: .blocked,
      previousStatus: .inProgress,
      statusChangedAtMillis: 1_500,
      updatedAtMillis: 1_700
    )
    let next = goal(
      "goal-existing",
      title: "Track release",
      status: .blocked,
      blocker: "Still waiting",
      updatedAtMillis: 2_000
    )

    let stamped = GlobalLongHorizonLifecyclePolicy.stampTransition(
      previous: previous,
      next: next,
      nowMillis: 3_000
    )

    XCTAssertEqual(stamped.previousStatus, .inProgress)
    XCTAssertEqual(stamped.statusChangedAtMillis, 1_500)
  }

  func testStampTransitionsMatchesPreviousGoalsById() {
    let previous = goal("goal-a", title: "A", status: .active, updatedAtMillis: 1_000)
    let next = goal("goal-a", title: "A", status: .blocked, updatedAtMillis: 2_000)

    let stamped = GlobalLongHorizonLifecyclePolicy.stampTransitions(
      previous: [previous],
      next: [next]
    ).first

    XCTAssertEqual(stamped?.previousStatus, .active)
    XCTAssertEqual(stamped?.statusChangedAtMillis, 2_000)
  }

  func testMaterialLifecycleTransitionCreatesOneStableProactiveMessage() {
    let previous = goal(
      "goal-id",
      title: "Ship the durable Agent",
      status: .inProgress,
      sourceConversationIds: ["conversation"],
      sourceEventIds: ["event"]
    )
    let completed = GlobalLongHorizonLifecyclePolicy.stampTransition(
      previous: previous,
      next: previous.with(
        status: .completed,
        verificationSummary: "Verified by a native execution receipt",
        checkpointCount: 3,
        updatedAtMillis: 2_000
      ),
      nowMillis: 2_000
    )

    let first = GlobalLongHorizonLifecyclePolicy.proactiveMessage(goal: completed)
    let replay = GlobalLongHorizonLifecyclePolicy.proactiveMessage(goal: completed)

    XCTAssertNotNil(first)
    XCTAssertEqual(first?.id, replay?.id)
    XCTAssertEqual(first?.sourceEventId, replay?.sourceEventId)
    XCTAssertEqual(first?.target, .newConversation)
    XCTAssertTrue(first?.content.contains("Verified by a native execution receipt") == true)
    XCTAssertEqual(first?.causalEventIds, Set(["event"]))
  }

  func testRoutineCheckpointCompletionRemainsSilent() {
    let previous = goal(
      "goal-routine",
      title: "Monitor runtime health",
      status: .inProgress
    )
    let active = GlobalLongHorizonLifecyclePolicy.stampTransition(
      previous: previous,
      next: previous.with(
        status: .active,
        progressSummary: "No material change",
        updatedAtMillis: 2_000
      ),
      nowMillis: 2_000
    )

    XCTAssertNil(GlobalLongHorizonLifecyclePolicy.proactiveMessage(goal: active))
  }

  func testBlockedGoalRecoveryProducesContinuationUpdate() {
    let blocked = goal(
      "goal-blocked",
      title: "Track release readiness",
      status: .blocked,
      previousStatus: .inProgress,
      statusChangedAtMillis: 1_000
    )
    let recovered = GlobalLongHorizonLifecyclePolicy.stampTransition(
      previous: blocked,
      next: blocked.with(status: .active, blocker: "", updatedAtMillis: 2_000),
      nowMillis: 2_000
    )

    let message = GlobalLongHorizonLifecyclePolicy.proactiveMessage(goal: recovered)

    XCTAssertNotNil(message)
    XCTAssertEqual(message?.target, .newConversation)
    XCTAssertTrue(message?.content.contains("resumed") == true)
  }

  func testWaitingStatesUseTheRightInterruptionLevel() {
    let source = goal(
      "goal-waiting",
      title: "Complete account migration",
      status: .inProgress,
      priority: 0.8
    )
    let dependency = GlobalLongHorizonLifecyclePolicy.stampTransition(
      previous: source,
      next: source.with(
        status: .waitingDependency,
        blocker: "Waiting for one prerequisite goal",
        updatedAtMillis: 2_000
      ),
      nowMillis: 2_000
    )
    let confirmation = GlobalLongHorizonLifecyclePolicy.stampTransition(
      previous: source,
      next: source.with(status: .waitingConfirmation, updatedAtMillis: 3_000),
      nowMillis: 3_000
    )

    XCTAssertEqual(
      GlobalLongHorizonLifecyclePolicy.proactiveMessage(goal: dependency)?.target,
      .globalDigest
    )
    XCTAssertEqual(
      GlobalLongHorizonLifecyclePolicy.proactiveMessage(goal: confirmation)?.target,
      .currentConversation
    )
    XCTAssertEqual(GlobalLongHorizonLifecyclePolicy.proactiveMessage(goal: confirmation)?.urgent, true)
  }

  func testHighPriorityBlockedGoalTargetsCurrentConversation() {
    let source = goal(
      "goal-blocked-high",
      title: "Fix account migration",
      status: .inProgress,
      priority: 0.95
    )
    let blocked = GlobalLongHorizonLifecyclePolicy.stampTransition(
      previous: source,
      next: source.with(
        status: .blocked,
        blocker: "The migration API is unavailable",
        updatedAtMillis: 4_000
      ),
      nowMillis: 4_000
    )

    let message = GlobalLongHorizonLifecyclePolicy.proactiveMessage(goal: blocked)

    XCTAssertEqual(message?.target, .currentConversation)
    XCTAssertEqual(message?.urgent, true)
    XCTAssertTrue(message?.content.contains("The migration API is unavailable") == true)
  }

  func testChineseGoalUsesLocalizedLifecycleCopy() {
    let previous = goal(
      "goal-cn",
      title: "\u{5b8c}\u{6210} iOS \u{7248}",
      topic: "\u{9879}\u{76ee}",
      status: .inProgress
    )
    let completed = GlobalLongHorizonLifecyclePolicy.stampTransition(
      previous: previous,
      next: previous.with(
        status: .completed,
        verificationSummary: "\u{5df2}\u{9a8c}\u{8bc1}",
        updatedAtMillis: 5_000
      ),
      nowMillis: 5_000
    )

    let message = GlobalLongHorizonLifecyclePolicy.proactiveMessage(goal: completed)

    XCTAssertEqual(message?.title, "\u{76ee}\u{6807}\u{5df2}\u{5b8c}\u{6210}")
    XCTAssertTrue(message?.content.contains("\u{5df2}\u{9a8c}\u{8bc1}") == true)
  }

  private func goal(
    _ id: String,
    title: String,
    topic: String = "GalaxySSI",
    status: GlobalLongHorizonGoalStatus = .active,
    previousStatus: GlobalLongHorizonGoalStatus? = nil,
    statusChangedAtMillis: Int64 = 0,
    priority: Double = 0.5,
    sourceConversationIds: Set<String> = ["conversation-a"],
    sourceEventIds: [String] = [],
    blocker: String = "",
    createdAtMillis: Int64 = 0,
    updatedAtMillis: Int64 = 0
  ) -> GlobalLongHorizonGoal {
    GlobalLongHorizonGoal(
      id: id,
      stableKey: "stable-\(id)",
      topic: topic,
      title: title,
      status: status,
      previousStatus: previousStatus,
      statusChangedAtMillis: statusChangedAtMillis,
      priority: priority,
      sourceConversationIds: sourceConversationIds,
      sourceEventIds: sourceEventIds,
      blocker: blocker,
      createdAtMillis: createdAtMillis,
      updatedAtMillis: updatedAtMillis
    )
  }
}

private extension GlobalLongHorizonGoal {
  func with(
    status: GlobalLongHorizonGoalStatus,
    blocker: String? = nil,
    progressSummary: String? = nil,
    verificationSummary: String? = nil,
    checkpointCount: Int? = nil,
    updatedAtMillis: Int64
  ) -> GlobalLongHorizonGoal {
    var copy = self
    copy.status = status
    if let blocker {
      copy.blocker = blocker
    }
    if let progressSummary {
      copy.progressSummary = progressSummary
    }
    if let verificationSummary {
      copy.verificationSummary = verificationSummary
    }
    if let checkpointCount {
      copy.checkpointCount = checkpointCount
    }
    copy.updatedAtMillis = updatedAtMillis
    return copy
  }
}
