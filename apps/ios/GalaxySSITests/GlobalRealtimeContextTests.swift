import XCTest
@testable import GalaxySSI

final class GlobalRealtimeContextTests: XCTestCase {
  func testProjectionKeepsLiveAndRecentStateWhileExcludingStaleOrDeletedWork() {
    let now = 10 * hour
    let liveCognition = cognition("cognition-live", "conversation-a", "Runtime architecture", now - 1_000)
    let deletedResearch = research("research-deleted", "conversation-deleted", "Deleted topic", now - 2_000)
    let recentRun = run(
      id: "run-recent",
      conversationId: "conversation-a",
      goal: "Build the Android runtime",
      status: .completed,
      updatedAtMillis: now - hour
    )
    let staleRun = run(
      id: "run-stale",
      conversationId: "conversation-a",
      goal: "Old completed work",
      status: .completed,
      updatedAtMillis: now - 7 * hour
    )
    let invalidatedRun = run(
      id: "run-invalidated",
      conversationId: "conversation-a",
      goal: "Retracted work",
      status: .paused,
      updatedAtMillis: now
    ).with(lastError: GlobalAgentEvidenceLifecyclePolicy.invalidatedReason)
    let blockedGoal = goal("goal-blocked", "conversation-a", .blocked, now)

    let projected = GlobalRealtimeContextPolicy.project(
      cognitionTasks: [liveCognition],
      researchTasks: [deletedResearch],
      autonomousRuns: [recentRun, staleRun, invalidatedRun],
      longHorizonGoals: [blockedGoal],
      excludedConversationIds: ["conversation-deleted"],
      nowMillis: now
    )

    XCTAssertEqual(
      Set(projected.map(\.key)),
      ["cognition:cognition-live", "run:run-recent", "goal:goal-blocked"]
    )
    XCTAssertTrue(projected.first { $0.key == "goal:goal-blocked" }?.needsAttention == true)
  }

  func testSelectionIsConversationScopedAndQueryRelevant() {
    let now = 20 * hour
    let items = [
      item("same", "Android runtime", "GalaxySSI", ["conversation-a"], now),
      item("related", "Android package verification", "GalaxySSI", ["conversation-b"], now - 1_000),
      item("unrelated", "Travel booking", "Holiday", ["conversation-c"], now - 2_000)
    ]

    let selected = GlobalRealtimeContextPolicy.select(
      items: items,
      query: "Check the Android runtime status",
      currentConversationId: "conversation-a",
      nowMillis: now
    )

    XCTAssertEqual(selected.map(\.key), ["same", "related"])
  }

  func testGlobalStatusQueryCanSurfaceActiveWorkFromOtherConversations() {
    let now = 30 * hour
    let items = [
      item("one", "Android build", "GalaxySSI", ["conversation-a"], now),
      item("two", "Research memory design", "Memory", ["conversation-b"], now - 1_000)
    ]

    let selected = GlobalRealtimeContextPolicy.select(
      items: items,
      query: "Show all tasks and current status",
      currentConversationId: "conversation-c",
      nowMillis: now
    )

    XCTAssertEqual(Set(selected.map(\.key)), ["one", "two"])
  }

  func testCurrentWorkCanBeExcludedFromRelatedRealtimeContext() {
    let now = 40 * hour
    let items = [
      item("run:current", "Current run", "GalaxySSI", ["conversation-a"], now),
      item("run:other", "Related run", "GalaxySSI", ["conversation-a"], now - 1_000)
    ]

    let selected = GlobalRealtimeContextPolicy.select(
      items: items,
      query: "Continue GalaxySSI",
      currentConversationId: "conversation-a",
      excludedKeys: ["run:current"],
      nowMillis: now
    )

    XCTAssertEqual(selected.map(\.key), ["run:other"])
  }

  func testRenderExposesBoundedHostStateWithoutInternalKeysOrSecrets() {
    let rendered = GlobalRealtimeContextPolicy.render(
      [
        GlobalRealtimeContextItem(
          key: "run:internal-uuid",
          kind: .autonomousRun,
          status: "waiting_for_resource",
          title: "Build release with api_key=top-secret",
          topic: "GalaxySSI at https://internal.example/path",
          detail: "workspace=C:\\Users\\agent\\private; cache=/data/user/0/com.galaxyssi.chat; steps=1/3"
        )
      ],
      maximumCharacters: 500
    )

    XCTAssertTrue(rendered.hasPrefix("Host-observed realtime state"))
    XCTAssertTrue(rendered.contains("[autonomous_run/waiting_for_resource]"))
    XCTAssertTrue(rendered.contains("api_key=<redacted>"))
    XCTAssertTrue(rendered.contains("<endpoint>"))
    XCTAssertTrue(rendered.contains("<path>"))
    XCTAssertFalse(rendered.contains("com.galaxyssi.chat"))
    XCTAssertFalse(rendered.contains("top-secret"))
    XCTAssertFalse(rendered.contains("internal-uuid"))
    XCTAssertLessThanOrEqual(rendered.count, 500)
  }

  func testRunProjectionReportsProgressButNotResourceRoutingIdentifiers() {
    let now = 50 * hour
    let action = GlobalAutonomousAction(
      id: "action-1",
      kind: .analyze,
      goal: "Inspect the build",
      status: .running,
      resourceId: "codex-secret-route"
    )
    let source = run(
      id: "run-1",
      conversationId: "conversation-a",
      goal: "Verify GalaxySSI",
      status: .running,
      updatedAtMillis: now,
      actions: [action]
    )

    let rendered = GlobalRealtimeContextPolicy.build(
      cognitionTasks: [],
      researchTasks: [],
      autonomousRuns: [source],
      longHorizonGoals: [],
      query: "GalaxySSI status",
      currentConversationId: "conversation-a",
      nowMillis: now
    )

    XCTAssertTrue(rendered.contains("steps=0/1"))
    XCTAssertTrue(rendered.contains("running=Inspect the build"))
    XCTAssertFalse(rendered.contains("codex-secret-route"))
    XCTAssertFalse(rendered.contains("run-1"))
    XCTAssertFalse(rendered.contains("action-1"))
  }

  func testGlobalStatusQueryIncludesAuthoritativeCognitionPipelineHealth() {
    let rendered = GlobalRealtimeContextPolicy.build(
      cognitionTasks: [],
      researchTasks: [],
      autonomousRuns: [],
      longHorizonGoals: [],
      query: "Show the global Agent status",
      currentConversationId: "conversation-a",
      nowMillis: 60 * hour,
      continuitySnapshot: GlobalAgentContinuitySnapshot(
        pendingEventCount: 3,
        retryingEvents: [failure("retrying-event")],
        quarantinedEvents: [],
        nextRetryAtMillis: 60 * hour + 30_000
      )
    )

    XCTAssertTrue(rendered.contains("[continuity/retrying]"))
    XCTAssertTrue(rendered.contains("pending_events=3"))
    XCTAssertTrue(rendered.contains("retrying_events=1"))
    XCTAssertFalse(rendered.contains("retrying-event"))
  }

  func testContinuityHealthStaysOutOfUnrelatedConversationContext() {
    let rendered = GlobalRealtimeContextPolicy.build(
      cognitionTasks: [],
      researchTasks: [],
      autonomousRuns: [],
      longHorizonGoals: [],
      query: "Translate this sentence",
      currentConversationId: "conversation-a",
      nowMillis: 70 * hour,
      continuitySnapshot: GlobalAgentContinuitySnapshot(
        pendingEventCount: 0,
        retryingEvents: [],
        quarantinedEvents: [],
        nextRetryAtMillis: 0
      )
    )

    XCTAssertEqual(rendered, "")
  }

  func testQuarantinedPipelineStateRequestsAttentionWithoutLeakingFailureDetails() {
    let failedEvent = GlobalConversationEvent(
      id: "secret-event-id",
      type: .messageCreated,
      conversationId: "private-routing-id",
      actor: .user,
      content: "sensitive content"
    )
    let failed = failure("secret-event-id")
      .with(reason: "api_key=secret-value at C:\\private\\path")
    let projectedItems = GlobalRealtimeContextPolicy.project(
      cognitionTasks: [],
      researchTasks: [],
      autonomousRuns: [],
      longHorizonGoals: [],
      nowMillis: 80 * hour,
      continuitySnapshot: GlobalAgentContinuitySnapshot(
        pendingEventCount: 1,
        retryingEvents: [],
        quarantinedEvents: [GlobalDeadLetterEvent(event: failedEvent, failure: failed, quarantinedAtMillis: 80 * hour)],
        nextRetryAtMillis: 0
      )
    )
    XCTAssertEqual(projectedItems.count, 1)
    guard let projected = projectedItems.first else { return }

    XCTAssertEqual(projected.kind, .continuity)
    XCTAssertEqual(projected.status, "attention_required")
    XCTAssertTrue(projected.needsAttention)
    XCTAssertFalse(projected.detail.contains("secret"))
    XCTAssertFalse(projected.detail.contains("private"))
  }

  private func cognition(
    _ id: String,
    _ conversationId: String,
    _ topic: String,
    _ updatedAtMillis: Int64
  ) -> GlobalCognitionTask {
    GlobalCognitionTask(
      id: id,
      sourceEvent: GlobalConversationEvent(
        id: "event-\(id)",
        type: .messageCreated,
        conversationId: conversationId,
        actor: .user,
        timestampMillis: updatedAtMillis,
        content: topic,
        conversationTitle: topic
      ),
      baselineUnderstanding: GlobalUnderstanding(topic: topic, project: ""),
      baselineIntent: "status_tracking",
      updatedAtMillis: updatedAtMillis
    )
  }

  private func research(
    _ id: String,
    _ conversationId: String,
    _ question: String,
    _ updatedAtMillis: Int64
  ) -> GlobalResearchTask {
    GlobalResearchTask(
      id: id,
      sourceEventId: "event-\(id)",
      sourceConversationId: conversationId,
      topic: question,
      question: question,
      depth: .deepResearch,
      preferredSources: ["official"],
      updatedAtMillis: updatedAtMillis
    )
  }

  private func run(
    id: String,
    conversationId: String,
    goal: String,
    status: GlobalAutonomousRunStatus,
    updatedAtMillis: Int64,
    actions: [GlobalAutonomousAction] = []
  ) -> GlobalAutonomousRun {
    GlobalAutonomousRun(
      id: id,
      sourceCognitionTaskId: "cognition-\(id)",
      sourceEventId: "event-\(id)",
      sourceConversationId: conversationId,
      topic: "GalaxySSI",
      goal: goal,
      actions: actions,
      status: status,
      updatedAtMillis: updatedAtMillis
    )
  }

  private func goal(
    _ id: String,
    _ conversationId: String,
    _ status: GlobalLongHorizonGoalStatus,
    _ updatedAtMillis: Int64
  ) -> GlobalLongHorizonGoal {
    GlobalLongHorizonGoal(
      id: id,
      stableKey: "stable-\(id)",
      topic: "GalaxySSI",
      title: "Complete the super-agent runtime",
      status: status,
      sourceConversationIds: [conversationId],
      blocker: "Waiting for verified evidence",
      updatedAtMillis: updatedAtMillis
    )
  }

  private func item(
    _ key: String,
    _ title: String,
    _ topic: String,
    _ conversationIds: Set<String>,
    _ updatedAtMillis: Int64
  ) -> GlobalRealtimeContextItem {
    GlobalRealtimeContextItem(
      key: key,
      kind: .autonomousRun,
      status: "running",
      title: title,
      topic: topic,
      conversationIds: conversationIds,
      updatedAtMillis: updatedAtMillis
    )
  }

  private func failure(_ eventId: String) -> GlobalEventProcessingFailure {
    GlobalEventProcessingFailure(
      eventId: eventId,
      attemptCount: 1,
      firstFailedAtMillis: 1_000,
      lastFailedAtMillis: 2_000,
      nextAttemptAtMillis: 32_000,
      errorFingerprint: "fingerprint",
      reason: "temporary failure"
    )
  }

  private let hour: Int64 = 60 * 60 * 1_000
}

private extension GlobalAutonomousRun {
  func with(lastError: String) -> GlobalAutonomousRun {
    var copy = self
    copy.lastError = lastError
    return copy
  }
}

private extension GlobalEventProcessingFailure {
  func with(reason: String) -> GlobalEventProcessingFailure {
    var copy = self
    copy.reason = reason
    return copy
  }
}
