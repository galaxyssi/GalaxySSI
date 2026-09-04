import XCTest
@testable import SignalASI

final class GlobalAgentDeliberationStoreTests: XCTestCase {
  private var fileURL: URL!

  override func setUp() {
    super.setUp()
    fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("signalasi-deliberation-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("state.json", isDirectory: false)
  }

  override func tearDown() {
    if let fileURL = fileURL {
      try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }
    fileURL = nil
    super.tearDown()
  }

  func testFileStorePersistsCognitionTasksAndAutonomousRuns() throws {
    let store = GlobalAgentDeliberationStore(fileURL: fileURL)
    store.saveCognitionTasks([task("task-a", status: .queued)])
    store.saveAutonomousRuns([run("run-a", actions: [action("step-a")])])

    let restored = GlobalAgentDeliberationStore(fileURL: fileURL)

    XCTAssertEqual(restored.cognitionTasks().map(\.id), ["task-a"])
    XCTAssertEqual(restored.autonomousRuns().map(\.id), ["run-a"])
  }

  func testClaimCognitionRecoversExpiredLeaseAndClaimsReadyTask() throws {
    let expired = task(
      "expired",
      status: .running,
      resourceId: "cloud",
      leaseExpiresAtMillis: 100,
      createdAtMillis: 100
    )
    let ready = task(
      "ready",
      status: .queued,
      nextAttemptAtMillis: 50,
      createdAtMillis: 200
    )
    let store = GlobalAgentDeliberationStore(fileURL: fileURL)
    store.saveCognitionTasks([expired, ready])

    let claimed = try XCTUnwrap(store.claimCognitionTask(nowMillis: 200))
    let tasksById = Dictionary(uniqueKeysWithValues: store.cognitionTasks().map { ($0.id, $0) })

    XCTAssertEqual(claimed.id, "ready")
    XCTAssertEqual(claimed.status, .running)
    XCTAssertEqual(claimed.attemptCount, 1)
    XCTAssertEqual(claimed.leaseExpiresAtMillis, 200 + GlobalCognitionTaskPolicy.leaseMillis)
    XCTAssertEqual(tasksById["expired"]?.status, .waitingForResource)
    XCTAssertEqual(tasksById["expired"]?.attemptedResourceIds, ["cloud"])
    XCTAssertEqual(tasksById["expired"]?.lastError, "The previous cognition lease expired before a result arrived")
  }

  func testClaimCognitionPrioritizesFreshHighValueUserEvent() throws {
    var routine = task("routine", status: .queued, createdAtMillis: 100)
    routine.baselineUnderstanding = GlobalUnderstanding(
      eventId: routine.sourceEvent.id,
      topic: "Routine",
      intent: "background_review",
      complexity: 0.2,
      urgency: 0.1
    )
    var urgent = task("urgent", status: .queued, createdAtMillis: 9_900)
    urgent.sourceEvent.actor = .user
    urgent.sourceEvent.type = .messageCreated
    urgent.baselineUnderstanding = GlobalUnderstanding(
      eventId: urgent.sourceEvent.id,
      topic: "Release risk",
      intent: "resolve_release_blocker",
      riskCandidates: ["Launch is blocked"],
      complexity: 0.9,
      urgency: 0.95,
      externalResearchUseful: true,
      durableFollowUpUseful: true
    )
    let store = GlobalAgentDeliberationStore(fileURL: fileURL)
    store.saveCognitionTasks([routine, urgent])

    XCTAssertEqual(store.claimCognitionTask(nowMillis: 10_000)?.id, "urgent")
  }

  func testClaimAutonomousWorkReservesReadyAction() throws {
    let ready = action("step-ready", priority: 0.9)
    let store = GlobalAgentDeliberationStore(fileURL: fileURL)
    store.saveAutonomousRuns([
      run("run-ready", actions: [ready], status: .queued, nextAttemptAtMillis: 100)
    ])

    let claim = try XCTUnwrap(store.claimAutonomousWork(nowMillis: 200))

    XCTAssertFalse(claim.planReview)
    XCTAssertEqual(claim.run.id, "run-ready")
    XCTAssertEqual(claim.actionId, ready.id)
    XCTAssertEqual(claim.run.status, .running)
    XCTAssertEqual(claim.run.actions.single?.status, .running)
    XCTAssertEqual(claim.run.actions.single?.leaseExpiresAtMillis, 200 + GlobalAutonomousRunPolicy.leaseMillis)
    XCTAssertEqual(store.autonomousRuns().single?.actions.single?.status, .running)
  }

  func testClaimAutonomousWorkTakesPlanReviewBeforeActions() throws {
    let pendingAction = action("step-ready")
    let review = GlobalAutonomousRunReview(
      status: .pending,
      nextAttemptAtMillis: 100
    )
    let store = GlobalAgentDeliberationStore(fileURL: fileURL)
    store.saveAutonomousRuns([
      run(
        "run-review",
        actions: [pendingAction],
        status: .replanning,
        review: review,
        nextAttemptAtMillis: 100
      )
    ])

    let claim = try XCTUnwrap(store.claimAutonomousWork(nowMillis: 200))

    XCTAssertTrue(claim.planReview)
    XCTAssertEqual(claim.actionId, "")
    XCTAssertEqual(claim.run.status, .replanning)
    XCTAssertEqual(claim.run.review.status, .running)
    XCTAssertEqual(claim.run.review.attemptCount, 1)
    XCTAssertEqual(claim.run.review.leaseExpiresAtMillis, 200 + GlobalAutonomousRunPolicy.leaseMillis)
    XCTAssertEqual(claim.run.actions.single?.status, .pending)
  }

  func testExpiredActionLeaseIsRecoveredAndReclaimed() throws {
    let running = action(
      "step-running",
      status: .running,
      resourceId: "local",
      leaseExpiresAtMillis: 100
    )
    let store = GlobalAgentDeliberationStore(fileURL: fileURL)
    store.saveAutonomousRuns([
      run("run-future", actions: [running], status: .running, nextAttemptAtMillis: 10_000)
    ])

    let claim = try XCTUnwrap(store.claimAutonomousWork(nowMillis: 200))
    let restored = try XCTUnwrap(store.autonomousRuns().single)

    XCTAssertEqual(claim.run.status, .running)
    XCTAssertEqual(claim.run.actions.single?.status, .running)
    XCTAssertEqual(claim.run.actions.single?.attemptedResourceIds, ["local"])
    XCTAssertEqual(restored.actions.single?.status, .running)
    XCTAssertEqual(restored.actions.single?.leaseExpiresAtMillis, 200 + GlobalAutonomousRunPolicy.leaseMillis)
  }

  func testRestoreMaintainsSeparateCognitionAndRunCollections() {
    let store = GlobalAgentDeliberationStore(fileURL: fileURL)

    store.restoreCognitionTasks([task("task-restore", status: .waitingForResource)])
    store.restoreAutonomousRuns([run("run-restore", actions: [action("step")], status: .waitingForResource)])

    XCTAssertEqual(store.exportCognitionTasks().single?.id, "task-restore")
    XCTAssertEqual(store.exportAutonomousRuns().single?.id, "run-restore")
  }
}

private func task(
  _ id: String,
  status: GlobalCognitionTaskStatus,
  resourceId: String = "",
  nextAttemptAtMillis: Int64 = 0,
  leaseExpiresAtMillis: Int64 = 0,
  createdAtMillis: Int64 = 100
) -> GlobalCognitionTask {
  GlobalCognitionTask(
    id: id,
    sourceEvent: GlobalConversationEvent(
      id: "event-\(id)",
      type: .taskUpdated,
      conversationId: "conversation",
      actor: .tool,
      timestampMillis: createdAtMillis,
      content: "Review"
    ),
    baselineUnderstanding: GlobalUnderstanding(
      eventId: "event-\(id)",
      topic: "SignalASI runtime",
      intent: "deliberation_store_test",
      goalCandidates: ["Ship iOS parity"],
      durableFollowUpUseful: true
    ),
    status: status,
    resourceId: resourceId,
    nextAttemptAtMillis: nextAttemptAtMillis,
    leaseExpiresAtMillis: leaseExpiresAtMillis,
    createdAtMillis: createdAtMillis,
    updatedAtMillis: createdAtMillis
  )
}

private func action(
  _ id: String,
  status: GlobalAutonomousActionStatus = .pending,
  priority: Double = 0.5,
  resourceId: String = "",
  leaseExpiresAtMillis: Int64 = 0
) -> GlobalAutonomousAction {
  GlobalAutonomousAction(
    id: id,
    kind: .analyze,
    goal: "Analyze next step",
    priority: priority,
    status: status,
    resourceId: resourceId,
    leaseExpiresAtMillis: leaseExpiresAtMillis
  )
}

private func run(
  _ id: String,
  actions: [GlobalAutonomousAction],
  status: GlobalAutonomousRunStatus = .queued,
  review: GlobalAutonomousRunReview = GlobalAutonomousRunReview(),
  nextAttemptAtMillis: Int64 = 0
) -> GlobalAutonomousRun {
  GlobalAutonomousRun(
    id: id,
    sourceCognitionTaskId: "cognition-\(id)",
    sourceEventId: "event-\(id)",
    sourceConversationId: "conversation",
    topic: "SignalASI runtime",
    goal: "Ship iOS parity",
    actions: actions,
    status: status,
    review: review,
    nextAttemptAtMillis: nextAttemptAtMillis,
    createdAtMillis: 100,
    updatedAtMillis: 100
  )
}

private extension Array {
  var single: Element? {
    count == 1 ? first : nil
  }
}
