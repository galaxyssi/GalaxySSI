import XCTest
@testable import GalaxySSI

final class GlobalAgentEvidenceLifecycleTests: XCTestCase {
  func testEvidenceIdsForConversationCollectsAllAndroidBackedSources() {
    let cognition = cognition(
      id: "cognition-a",
      source: event(
        id: "event-a",
        conversationId: "conversation-a",
        metadata: ["source_conversation_ids": "conversation-b, conversation-c"],
        causalEventIds: ["root-a", "root-b"]
      )
    )
    let research = research(
      id: "research-a",
      conversationId: "conversation-b",
      sourceEventId: "research-source"
    )
    let run = run(
      id: "run-a",
      conversationId: "conversation-b",
      sourceEventId: "run-source",
      causalEventIds: ["run-root"]
    )
    let proactive = proactive(
      id: "message-a",
      conversationId: "conversation-b",
      sourceEventId: "proactive-source",
      causalEventIds: ["proactive-root"]
    )
    let goal = goal(
      id: "goal-a",
      conversations: ["conversation-b"],
      sourceEventIds: ["goal-root"]
    )
    let unrelated = research(
      id: "research-other",
      conversationId: "conversation-z",
      sourceEventId: "other-source"
    )

    let evidence = GlobalAgentEvidenceLifecyclePolicy.evidenceIdsForConversation(
      conversationId: " conversation-b ",
      cognitionTasks: [cognition],
      researchTasks: [research, unrelated],
      autonomousRuns: [run],
      proactiveMessages: [proactive],
      longHorizonGoals: [goal]
    )

    XCTAssertEqual(
      evidence,
      ["root-a", "root-b", "research-source", "run-root", "proactive-root", "goal-root"]
    )
  }

  func testInvalidatesRunningWorkThatReferencesDeletedEvidence() {
    let cognition = cognition(
      id: "cognition-a",
      source: event(id: "event-a", conversationId: "conversation-a", causalEventIds: ["deleted-event"]),
      sourceMessageId: 7,
      nextAttemptAtMillis: 8,
      leaseExpiresAtMillis: 9
    )
    let research = research(
      id: "research-a",
      conversationId: "conversation-a",
      sourceEventId: "research-source",
      causalEventIds: ["deleted-event"],
      sourceMessageId: 10,
      nextAttemptAtMillis: 11,
      leaseExpiresAtMillis: 12,
      researchPlan: GlobalResearchPlan(
        units: [
          GlobalResearchUnit(status: .pending, sourceMessageId: 13, leaseExpiresAtMillis: 14),
          GlobalResearchUnit(status: .running, sourceMessageId: 15, leaseExpiresAtMillis: 16),
          GlobalResearchUnit(status: .completed, sourceMessageId: 17, leaseExpiresAtMillis: 18)
        ],
        synthesisSourceMessageId: 19,
        synthesisLeaseExpiresAtMillis: 20
      )
    )
    let actions = [
      action(status: .pending, sourceMessageId: 21, leaseExpiresAtMillis: 22),
      action(status: .running, sourceMessageId: 23, leaseExpiresAtMillis: 24),
      action(status: .waitingConfirmation, sourceMessageId: 25, leaseExpiresAtMillis: 26),
      action(status: .completed, sourceMessageId: 27, leaseExpiresAtMillis: 28)
    ]
    let autonomousRun = run(
      id: "run-a",
      conversationId: "conversation-a",
      sourceEventId: "run-source",
      causalEventIds: ["deleted-event"],
      actions: actions,
      nextAttemptAtMillis: 30,
      leaseExpiresAtMillis: 31
    )
    let proactiveMessage = proactive(
      id: "message-a",
      conversationId: "conversation-a",
      sourceEventId: "proactive-source",
      causalEventIds: ["deleted-event"],
      status: .delivering,
      deliveryLeaseExpiresAtMillis: 32
    )

    let invalidatedCognition = GlobalAgentEvidenceLifecyclePolicy.invalidateCognitionTasks(
      [cognition],
      eventIds: ["deleted-event"],
      nowMillis: 50_000
    ).first
    let invalidatedResearch = GlobalAgentEvidenceLifecyclePolicy.invalidateResearchTasks(
      [research],
      eventIds: ["deleted-event"],
      nowMillis: 50_000
    ).first
    let invalidatedRun = GlobalAgentEvidenceLifecyclePolicy.invalidateAutonomousRuns(
      [autonomousRun],
      eventIds: ["deleted-event"],
      nowMillis: 50_000
    ).first
    let invalidatedMessage = GlobalAgentEvidenceLifecyclePolicy.invalidateProactiveMessages(
      [proactiveMessage],
      eventIds: ["deleted-event"]
    ).first

    XCTAssertEqual(invalidatedCognition?.status, .failed)
    XCTAssertEqual(invalidatedCognition?.sourceMessageId, 0)
    XCTAssertEqual(invalidatedCognition?.nextAttemptAtMillis, 0)
    XCTAssertEqual(invalidatedCognition?.leaseExpiresAtMillis, 0)
    XCTAssertEqual(invalidatedCognition?.lastError, GlobalAgentEvidenceLifecyclePolicy.invalidatedReason)
    XCTAssertEqual(invalidatedCognition?.updatedAtMillis, 50_000)

    XCTAssertEqual(invalidatedResearch?.status, .failed)
    XCTAssertEqual(invalidatedResearch?.sourceMessageId, 0)
    XCTAssertEqual(invalidatedResearch?.researchPlan.synthesisSourceMessageId, 0)
    XCTAssertEqual(invalidatedResearch?.researchPlan.synthesisLeaseExpiresAtMillis, 0)
    XCTAssertEqual(invalidatedResearch?.researchPlan.units.map(\.status), [.failed, .failed, .completed])
    XCTAssertEqual(invalidatedResearch?.researchPlan.units.prefix(2).map(\.completedAtMillis), [50_000, 50_000])
    XCTAssertEqual(invalidatedResearch?.researchPlan.units.last?.sourceMessageId, 17)

    XCTAssertEqual(invalidatedRun?.status, .paused)
    XCTAssertEqual(invalidatedRun?.nextAttemptAtMillis, 0)
    XCTAssertEqual(invalidatedRun?.leaseExpiresAtMillis, 0)
    XCTAssertEqual(invalidatedRun?.actions.map(\.status), [.skipped, .skipped, .skipped, .completed])
    XCTAssertEqual(invalidatedRun?.actions.prefix(3).map(\.completedAtMillis), [50_000, 50_000, 50_000])
    XCTAssertEqual(invalidatedRun?.actions.last?.sourceMessageId, 27)

    XCTAssertEqual(invalidatedMessage?.status, .dismissed)
    XCTAssertEqual(invalidatedMessage?.deliveryLeaseExpiresAtMillis, 0)
    XCTAssertEqual(invalidatedMessage?.lastDeliveryError, GlobalAgentEvidenceLifecyclePolicy.invalidatedReason)
  }

  func testLongHorizonInvalidationDropsFullyInvalidatedGoalsAndReconcilesDependents() {
    let removed = goal(
      id: "goal-removed",
      conversations: ["conversation-a"],
      sourceEventIds: ["deleted-event"]
    )
    let retained = goal(
      id: "goal-retained",
      conversations: ["conversation-a"],
      sourceEventIds: ["deleted-event", "retained-event"],
      status: .waitingDependency,
      dependencyGoalIds: ["goal-removed", "missing-goal"],
      activeCognitionTaskId: "cognition-a",
      activeRunId: "run-a",
      blocker: "Waiting for deleted evidence"
    )

    let invalidated = GlobalAgentEvidenceLifecyclePolicy.invalidateLongHorizonGoals(
      [removed, retained],
      eventIds: ["deleted-event"],
      nowMillis: 80_000
    )

    XCTAssertEqual(invalidated.map(\.id), ["goal-retained"])
    XCTAssertEqual(invalidated.first?.sourceEventIds, ["retained-event"])
    XCTAssertEqual(invalidated.first?.dependencyGoalIds, Set<String>())
    XCTAssertEqual(invalidated.first?.activeCognitionTaskId, "")
    XCTAssertEqual(invalidated.first?.activeRunId, "")
    XCTAssertEqual(invalidated.first?.status, .active)
    XCTAssertEqual(invalidated.first?.blocker, "")
    XCTAssertEqual(invalidated.first?.nextCheckAtMillis, 80_000)
    XCTAssertEqual(invalidated.first?.updatedAtMillis, 80_000)
  }

  func testUnmatchedAndTerminalProactiveWorkIsRetained() {
    let researchTask = research(
      id: "research-a",
      conversationId: "conversation-a",
      sourceEventId: "research-source",
      causalEventIds: ["kept-event"],
      status: .running,
      sourceMessageId: 9
    )
    let delivered = proactive(
      id: "message-delivered",
      conversationId: "conversation-a",
      sourceEventId: "deleted-event",
      status: .delivered,
      deliveryLeaseExpiresAtMillis: 123
    )

    XCTAssertEqual(
      GlobalAgentEvidenceLifecyclePolicy.invalidateResearchTasks(
        [researchTask],
        eventIds: ["deleted-event"],
        nowMillis: 90_000
      ).first,
      researchTask
    )
    XCTAssertEqual(
      GlobalAgentEvidenceLifecyclePolicy.invalidateProactiveMessages(
        [delivered],
        eventIds: ["deleted-event"]
      ).first,
      delivered
    )
  }

  private func event(
    id: String,
    conversationId: String,
    metadata: [String: String] = [:],
    causalEventIds: Set<String> = []
  ) -> GlobalConversationEvent {
    GlobalConversationEvent(
      id: id,
      type: .messageCreated,
      conversationId: conversationId,
      actor: .user,
      content: "Build GalaxySSI",
      metadata: metadata,
      causalEventIds: causalEventIds
    )
  }

  private func cognition(
    id: String,
    source: GlobalConversationEvent,
    sourceMessageId: Int64 = 0,
    nextAttemptAtMillis: Int64 = 0,
    leaseExpiresAtMillis: Int64 = 0
  ) -> GlobalCognitionTask {
    GlobalCognitionTask(
      id: id,
      sourceEvent: source,
      baselineUnderstanding: GlobalUnderstanding(topic: "GalaxySSI"),
      sourceMessageId: sourceMessageId,
      nextAttemptAtMillis: nextAttemptAtMillis,
      leaseExpiresAtMillis: leaseExpiresAtMillis
    )
  }

  private func research(
    id: String,
    conversationId: String,
    sourceEventId: String,
    causalEventIds: Set<String> = [],
    status: GlobalResearchTaskStatus = .queued,
    sourceMessageId: Int64 = 0,
    nextAttemptAtMillis: Int64 = 0,
    leaseExpiresAtMillis: Int64 = 0,
    researchPlan: GlobalResearchPlan = GlobalResearchPlan()
  ) -> GlobalResearchTask {
    GlobalResearchTask(
      id: id,
      sourceEventId: sourceEventId,
      sourceConversationId: conversationId,
      topic: "GalaxySSI",
      question: "Verify parity",
      depth: .deepResearch,
      preferredSources: ["official"],
      causalEventIds: causalEventIds,
      status: status,
      sourceMessageId: sourceMessageId,
      nextAttemptAtMillis: nextAttemptAtMillis,
      leaseExpiresAtMillis: leaseExpiresAtMillis,
      researchPlan: researchPlan
    )
  }

  private func run(
    id: String,
    conversationId: String,
    sourceEventId: String,
    causalEventIds: Set<String> = [],
    actions: [GlobalAutonomousAction] = [],
    nextAttemptAtMillis: Int64 = 0,
    leaseExpiresAtMillis: Int64 = 0
  ) -> GlobalAutonomousRun {
    GlobalAutonomousRun(
      id: id,
      sourceCognitionTaskId: "cognition-\(id)",
      sourceEventId: sourceEventId,
      sourceConversationId: conversationId,
      topic: "GalaxySSI",
      goal: "Build iOS parity",
      actions: actions,
      causalEventIds: causalEventIds,
      status: .running,
      nextAttemptAtMillis: nextAttemptAtMillis,
      leaseExpiresAtMillis: leaseExpiresAtMillis
    )
  }

  private func proactive(
    id: String,
    conversationId: String,
    sourceEventId: String,
    causalEventIds: Set<String> = [],
    status: GlobalProactiveMessageStatus = .pending,
    deliveryLeaseExpiresAtMillis: Int64 = 0
  ) -> GlobalProactiveMessage {
    GlobalProactiveMessage(
      id: id,
      sourceEventId: sourceEventId,
      sourceConversationId: conversationId,
      target: .currentConversation,
      title: "Insight",
      content: "Evidence changed",
      topic: "GalaxySSI",
      urgent: false,
      causalEventIds: causalEventIds,
      status: status,
      deliveryLeaseExpiresAtMillis: deliveryLeaseExpiresAtMillis
    )
  }

  private func action(
    status: GlobalAutonomousActionStatus,
    sourceMessageId: Int64,
    leaseExpiresAtMillis: Int64
  ) -> GlobalAutonomousAction {
    GlobalAutonomousAction(
      kind: .draft,
      goal: "Prepare update",
      status: status,
      sourceMessageId: sourceMessageId,
      leaseExpiresAtMillis: leaseExpiresAtMillis
    )
  }

  private func goal(
    id: String,
    conversations: Set<String>,
    sourceEventIds: [String],
    status: GlobalLongHorizonGoalStatus = .active,
    dependencyGoalIds: Set<String> = [],
    activeCognitionTaskId: String = "",
    activeRunId: String = "",
    blocker: String = ""
  ) -> GlobalLongHorizonGoal {
    GlobalLongHorizonGoal(
      id: id,
      stableKey: "stable-\(id)",
      topic: "GalaxySSI",
      title: "Keep parity moving",
      status: status,
      sourceConversationIds: conversations,
      sourceEventIds: sourceEventIds,
      dependencyGoalIds: dependencyGoalIds,
      activeCognitionTaskId: activeCognitionTaskId,
      activeRunId: activeRunId,
      blocker: blocker
    )
  }
}
