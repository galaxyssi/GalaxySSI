import XCTest
@testable import GalaxySSI

final class GlobalProactiveDiscoveryTests: XCTestCase {
  func testAccumulatedCrossTopicConflictBecomesOneDiscoveryCandidate() {
    let world = PersonalWorldModel(items: [
      worldItem(
        stableKey: "decision-a",
        value: "Bundle every model in the app",
        conversationId: "conversation-a",
        eventId: "event-a",
        status: .conflicted,
        conflictGroupId: "packaging-conflict",
        kind: .decision
      ),
      worldItem(
        stableKey: "decision-b",
        value: "Download large models after installation",
        conversationId: "conversation-b",
        eventId: "event-b",
        status: .conflicted,
        conflictGroupId: "packaging-conflict",
        kind: .decision
      )
    ])

    let candidates = GlobalProactiveDiscoveryPolicy.scan(
      world: world,
      goals: [],
      excludedConversationIds: [],
      nowMillis: 10_000
    )

    XCTAssertEqual(candidates.count, 1)
    XCTAssertEqual(candidates.single?.kind, .crossTopicConflict)
    XCTAssertEqual(candidates.single?.sourceConversationIds, Set(["conversation-a", "conversation-b"]))
    XCTAssertEqual(candidates.single?.causalEventIds, Set(["event-a", "event-b"]))
  }

  func testLocalOnlyAndDeletedConversationEvidenceNeverEntersDiscovery() {
    let localOnly = worldItem(
      stableKey: "private-risk",
      value: "Private risk",
      conversationId: "private",
      eventId: "private-event",
      kind: .risk,
      visibility: .localOnly
    )
    let deleted = worldItem(
      stableKey: "deleted-risk",
      value: "Deleted risk",
      conversationId: "deleted",
      eventId: "deleted-event",
      kind: .risk
    )

    let candidates = GlobalProactiveDiscoveryPolicy.scan(
      world: PersonalWorldModel(items: [localOnly, deleted]),
      goals: [],
      excludedConversationIds: ["deleted"],
      nowMillis: 10_000
    )

    XCTAssertTrue(candidates.isEmpty)
  }

  func testRepeatedRiskAndCrossConversationOpportunityCrossDiscoveryThreshold() {
    var risk = worldItem(
      stableKey: "risk",
      value: "A platform change may break native libraries",
      conversationId: "conversation-a",
      eventId: "risk-a",
      kind: .risk,
      confidence: 0.76,
      evidenceCount: 2
    )
    risk.evidenceEventIds = ["risk-a", "risk-b"]
    var opportunity = worldItem(
      stableKey: "opportunity",
      value: "Reuse one runtime across several topic workspaces",
      conversationId: "conversation-a",
      eventId: "opportunity-a",
      kind: .opportunity,
      confidence: 0.80,
      evidenceCount: 2
    )
    opportunity.conversationIds = ["conversation-a", "conversation-b"]
    opportunity.evidenceEventIds = ["opportunity-a", "opportunity-b"]

    let kinds = Set(GlobalProactiveDiscoveryPolicy.scan(
      world: PersonalWorldModel(items: [risk, opportunity]),
      goals: [],
      excludedConversationIds: [],
      nowMillis: 10_000
    ).map(\.kind))

    XCTAssertEqual(kinds, Set([GlobalDiscoveryKind.materialRisk, .highValueOpportunity]))
  }

  func testOrdinaryEvidenceAcrossTopicWorkspacesCreatesProactiveSynthesis() {
    let goal = worldItem(
      id: "goal-id",
      stableKey: "goal",
      value: "Keep the iOS Agent runtime available offline",
      conversationId: "conversation-a",
      eventId: "goal-event",
      kind: .goal
    )
    let decision = worldItem(
      id: "decision-id",
      stableKey: "decision",
      value: "Bundle the base runtime image in the app",
      conversationId: "conversation-b",
      eventId: "decision-event",
      kind: .decision
    )
    let fact = worldItem(
      id: "fact-id",
      stableKey: "fact",
      value: "Large runtime payloads increase installation size",
      conversationId: "conversation-b",
      eventId: "fact-event",
      kind: .fact
    )
    let graph = GlobalTopicProjectGraph(nodes: [
      GlobalTopicNode(
        stableKey: "project-runtime",
        name: "iOS Agent runtime",
        kind: .project,
        conversationIds: ["conversation-a", "conversation-b"],
        worldItemIds: [goal.id, decision.id, fact.id],
        evidenceEventIds: ["goal-event", "decision-event", "fact-event"],
        confidence: 0.86
      )
    ])

    let candidate = GlobalProactiveDiscoveryPolicy.scan(
      world: PersonalWorldModel(items: [goal, decision, fact]),
      goals: [],
      excludedConversationIds: [],
      nowMillis: 10_000,
      topicGraph: graph
    ).single

    XCTAssertEqual(candidate?.kind, .crossTopicSynthesis)
    XCTAssertEqual(candidate?.sourceConversationIds, Set(["conversation-a", "conversation-b"]))
    XCTAssertTrue(candidate?.summary.contains("installation size") == true)
  }

  func testBlockedDurableGoalBecomesReviewTaskWithoutNewChatEvent() {
    let source = worldItem(
      stableKey: "goal-world",
      value: "Ship the on-device runtime",
      conversationId: "runtime-topic",
      eventId: "goal-event",
      kind: .goal,
      confidence: 0.90
    )
    let goal = GlobalLongHorizonGoal(
      id: "goal-id",
      stableKey: "goal-stable",
      topic: "On-device runtime",
      title: "Ship the on-device runtime",
      status: .blocked,
      sourceConversationIds: ["runtime-topic"],
      sourceEventIds: ["goal-event"],
      blocker: "The runtime package is unavailable",
      createdAtMillis: 1_000,
      updatedAtMillis: 2_000
    )

    let candidate = GlobalProactiveDiscoveryPolicy.scan(
      world: PersonalWorldModel(items: [source]),
      goals: [goal],
      excludedConversationIds: [],
      nowMillis: 100_000
    ).single
    let task = candidate.map { GlobalProactiveDiscoveryPolicy.task($0, nowMillis: 100_000) }

    XCTAssertEqual(candidate?.kind, .stalledGoal)
    XCTAssertEqual(task?.sourceEvent.metadata["long_horizon_goal_id"], "goal-id")
    XCTAssertEqual(task?.baselineIntent, "proactive_world_review")
  }

  func testUnchangedCompletedFindingIsNotQueuedTwice() {
    let candidate = discoveryCandidate(fingerprint: "fingerprint-a")
    var task = GlobalProactiveDiscoveryPolicy.task(candidate, nowMillis: 1_000)
    task.status = .completed
    task.updatedAtMillis = 2_000
    let state = GlobalProactiveDiscoveryState(records: [
      GlobalDiscoveryRecord(
        stableKey: candidate.stableKey,
        fingerprint: candidate.fingerprint,
        cognitionTaskId: task.id,
        emittedAtMillis: 1_000
      )
    ])

    let selected = GlobalProactiveDiscoveryPolicy.selectForDeliberation(
      candidates: [candidate],
      state: state,
      existingTasks: [task],
      settings: GlobalAgentSettings(),
      nowMillis: 100_000_000
    )

    XCTAssertTrue(selected.isEmpty)
  }

  func testMateriallyChangedEvidenceCanBeReconsideredAfterCooldown() {
    let previous = discoveryCandidate(fingerprint: "fingerprint-a")
    let changed = discoveryCandidate(fingerprint: "fingerprint-b")
    let state = GlobalProactiveDiscoveryState(records: [
      GlobalDiscoveryRecord(
        stableKey: previous.stableKey,
        fingerprint: previous.fingerprint,
        cognitionTaskId: GlobalProactiveDiscoveryPolicy.cognitionTaskId(previous),
        emittedAtMillis: 1_000
      )
    ])

    let selected = GlobalProactiveDiscoveryPolicy.selectForDeliberation(
      candidates: [changed],
      state: state,
      existingTasks: [],
      settings: GlobalAgentSettings(discoveryIntervalMillis: 60 * 60 * 1_000),
      nowMillis: 2 * 60 * 60 * 1_000
    )

    XCTAssertEqual(selected, [changed])
  }

  func testDailyDiscoveryBudgetBoundsAutonomousDeliberation() {
    let now: Int64 = 100_000_000
    let state = GlobalProactiveDiscoveryState(
      recentEmissionTimestamps: [now - 1_000, now - 2_000, now - 3_000]
    )

    let selected = GlobalProactiveDiscoveryPolicy.selectForDeliberation(
      candidates: [discoveryCandidate(fingerprint: "new")],
      state: state,
      existingTasks: [],
      settings: GlobalAgentSettings(dailyDiscoveryTaskBudget: 3),
      nowMillis: now
    )

    XCTAssertTrue(selected.isEmpty)
  }

  func testExpiredScanLeaseIsRecoverableWhileActiveLeaseIsExclusive() throws {
    let state = GlobalProactiveDiscoveryState(
      nextScanAtMillis: 10,
      scanLeaseExpiresAtMillis: 100
    )

    XCTAssertFalse(GlobalProactiveDiscoveryPolicy.canClaim(state, nowMillis: 99))
    XCTAssertTrue(GlobalProactiveDiscoveryPolicy.canClaim(state, nowMillis: 100))

    let claimed = try XCTUnwrap(GlobalProactiveDiscoveryPolicy.claim(state: state, nowMillis: 100))
    XCTAssertEqual(claimed.1.sequence, 1)
    XCTAssertEqual(claimed.0.scanLeaseExpiresAtMillis, 100 + GlobalProactiveDiscoveryPolicy.scanLeaseMillis)
  }

  func testDiscoveryStateSurvivesBackupCodecRoundTrip() {
    let state = GlobalProactiveDiscoveryState(
      nextScanAtMillis: 20,
      scanLeaseExpiresAtMillis: 30,
      lastStartedAtMillis: 10,
      lastCompletedAtMillis: 15,
      scanSequence: 4,
      recentEmissionTimestamps: [12],
      records: [GlobalDiscoveryRecord(
        stableKey: "key",
        fingerprint: "fingerprint",
        cognitionTaskId: "task",
        emittedAtMillis: 12
      )],
      lastError: "temporary"
    )

    let restored = GlobalProactiveDiscoveryCodec.decode(GlobalProactiveDiscoveryCodec.encode(state))

    XCTAssertEqual(state, restored)
  }

  func testContributingConversationEvidenceStaysCausalForDeletion() {
    let candidate = GlobalDiscoveryCandidate(
      stableKey: "risk:key",
      fingerprint: "fingerprint",
      kind: .materialRisk,
      topic: "GalaxySSI",
      summary: "A material risk needs review",
      sourceConversationIds: ["conversation-a", "conversation-b"],
      causalEventIds: ["event-a", "event-b"],
      score: 0.85,
      urgency: 0.80,
      externalResearchUseful: true
    )

    let task = GlobalProactiveDiscoveryPolicy.task(candidate, nowMillis: 1_000)

    XCTAssertEqual(task.sourceEvent.causalEventIds, Set(["event-a", "event-b"]))
    XCTAssertEqual(task.sourceEvent.metadata["source_conversation_ids"], "conversation-a,conversation-b")
  }

  func testEmptyPeriodicInferenceRemainsSilentWhileMaterialFindingMaySurface() {
    let source = GlobalProactiveDiscoveryPolicy.task(discoveryCandidate(fingerprint: "fingerprint"), nowMillis: 1_000)

    XCTAssertFalse(GlobalProactiveDiscoveryPolicy.shouldSurfaceResult(task: source))
    XCTAssertTrue(GlobalProactiveDiscoveryPolicy.shouldSurfaceResult(task: source, risks: ["A newly validated risk"]))
  }

  private func worldItem(
    id: String = UUID().uuidString,
    stableKey: String,
    value: String,
    conversationId: String,
    eventId: String,
    status: GlobalWorldItemStatus = .active,
    conflictGroupId: String = "",
    kind: GlobalWorldItemKind,
    visibility: GlobalWorldContextVisibility = .shareable,
    confidence: Double = 0.90,
    evidenceCount: Int = 1
  ) -> GlobalWorldItem {
    GlobalWorldItem(
      id: id,
      stableKey: stableKey,
      kind: kind,
      layer: .topic,
      topic: "GalaxySSI",
      value: value,
      confidence: confidence,
      contextVisibility: visibility,
      evidenceCount: evidenceCount,
      conversationIds: [conversationId],
      evidenceEventIds: [eventId],
      status: status,
      conflictGroupId: conflictGroupId
    )
  }

  private func discoveryCandidate(fingerprint: String) -> GlobalDiscoveryCandidate {
    GlobalDiscoveryCandidate(
      stableKey: "risk:key",
      fingerprint: fingerprint,
      kind: .materialRisk,
      topic: "GalaxySSI",
      summary: "A material risk needs review",
      sourceConversationIds: ["conversation-a"],
      causalEventIds: ["event-a"],
      score: 0.85,
      urgency: 0.80,
      externalResearchUseful: true
    )
  }
}

private extension Array {
  var single: Element? {
    count == 1 ? first : nil
  }
}
