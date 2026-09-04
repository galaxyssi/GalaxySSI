import XCTest
@testable import GalaxySSI

final class GlobalAutonomousReplanPolicyTests: XCTestCase {
  func testPlanReviewParserAcceptsBoundedSupportedActions() throws {
    let decision = try XCTUnwrap(GlobalRunReplanParser.parse(
      """
      ```json
      {
        "goal_state":"ACTIVE",
        "summary":"A platform constraint changed the next step.",
        "cancel_action_ids":["obsolete"],
        "actions":[
          {"kind":"READ_ONLY_CHECK","goal":"Verify the current platform limit","priority":0.9},
          {"kind":"PAY","goal":"Buy more capacity","priority":1.0}
        ],
        "next_check_hours":6,
        "confidence":0.86
      }
      ```
      """
    ))

    XCTAssertEqual(decision.goalState, .active)
    XCTAssertEqual(decision.summary, "A platform constraint changed the next step.")
    XCTAssertEqual(decision.cancelActionIds, ["obsolete"])
    XCTAssertEqual(decision.actions.count, 1)
    XCTAssertEqual(decision.actions.first?.kind, .readOnlyCheck)
    XCTAssertEqual(decision.nextCheckHours, 6)
    XCTAssertEqual(decision.confidence, 0.86)
  }

  func testInvalidPlanReviewProseCannotReviseRun() {
    XCTAssertNil(GlobalRunReplanParser.parse("The plan probably needs another step."))
  }

  func testShouldReviewDiscoveryOutcomeWhenWorkRemains() {
    let current = action(.readOnlyCheck, "Inspect constraints", id: "inspect")
    let pending = action(.draft, "Draft implementation", id: "draft")

    XCTAssertTrue(GlobalAutonomousReplanPolicy.shouldReview(
      run: run([current, pending]),
      action: current,
      succeeded: true,
      result: "The constraints were verified",
      enabled: true,
      maxReplans: 3
    ))
  }

  func testOrdinarySuccessfulFinalDraftDoesNotSpendReview() {
    let draft = action(.draft, "Draft implementation", id: "draft")

    XCTAssertFalse(GlobalAutonomousReplanPolicy.shouldReview(
      run: run([draft]),
      action: draft,
      succeeded: true,
      result: "Draft completed",
      enabled: true,
      maxReplans: 3
    ))
  }

  func testFailedStepTriggersReview() {
    let draft = action(.draft, "Draft implementation", id: "draft")

    XCTAssertTrue(GlobalAutonomousReplanPolicy.shouldReview(
      run: run([draft]),
      action: draft,
      succeeded: false,
      result: "The selected resource failed",
      enabled: true,
      maxReplans: 3
    ))
  }

  func testReplanPreservesCompletedEvidenceAndNormalizesLocalWork() throws {
    let completed = action(
      .analyze,
      "Analyze constraints",
      id: "completed",
      status: .completed,
      result: "Verified evidence",
      verificationStatus: .supported
    )
    let obsolete = action(.draft, "Draft obsolete design", id: "obsolete")
    let source = GlobalAutonomousReplanPolicy.requestReview(
      run: run([completed, obsolete]),
      reason: "New evidence",
      nowMillis: 100
    )

    let revised = GlobalAutonomousReplanPolicy.applyDecision(
      run: source,
      decision: GlobalRunReplanDecision(
        summary: "Use the verified constraint in a revised design.",
        cancelActionIds: [obsolete.id],
        actions: [
          GlobalAutonomousAction(
            kind: .createTopic,
            goal: "Create an external project workspace",
            externalEffect: true
          )
        ],
        confidence: 0.9
      ),
      nowMillis: 200
    )

    XCTAssertEqual(revised.actions.first { $0.id == completed.id }?.result, "Verified evidence")
    XCTAssertEqual(revised.actions.first { $0.id == obsolete.id }?.status, .skipped)
    let addition = try XCTUnwrap(revised.actions.last)
    XCTAssertEqual(addition.status, .pending)
    XCTAssertFalse(addition.externalEffect)
    XCTAssertTrue(addition.reversible)
    XCTAssertEqual(revised.status, .queued)
    XCTAssertEqual(revised.revision, 2)
    XCTAssertEqual(revised.replanCount, 1)
  }

  func testExpiredPlanReviewLeaseIsRecoverable() {
    let completed = action(
      .analyze,
      "Analyze",
      status: .completed,
      result: "done",
      verificationStatus: .supported
    )
    let source = run(
      [completed],
      status: .replanning,
      review: GlobalAutonomousRunReview(
        status: .running,
        resourceId: "codex",
        sourceMessageId: 42,
        leaseExpiresAtMillis: 100
      )
    )

    let recovered = GlobalAutonomousReplanPolicy.recoverIfStale(run: source, nowMillis: 101)

    XCTAssertEqual(recovered.review.status, .waitingForResource)
    XCTAssertEqual(recovered.review.attemptedResourceIds, ["codex"])
    XCTAssertEqual(recovered.review.sourceMessageId, 0)
    XCTAssertEqual(recovered.review.lastError, "The plan review lease expired before a result arrived")
    XCTAssertEqual(recovered.actions.single?.result, "done")
  }

  func testUnsupportedCompletionClaimIsKeptActiveWithExplanation() {
    let completed = action(
      .analyze,
      "Analyze",
      status: .completed,
      result: "done",
      verificationStatus: .pending
    )

    let revised = GlobalAutonomousReplanPolicy.applyDecision(
      run: run([completed], status: .replanning),
      decision: GlobalRunReplanDecision(
        goalState: .completed,
        summary: "Looks complete"
      ),
      nowMillis: 300
    )

    XCTAssertEqual(revised.status, .completed)
    XCTAssertEqual(revised.review.decision.goalState, .active)
    XCTAssertTrue(revised.outcomeSummary.contains("Completion was not accepted"))
    XCTAssertEqual(revised.lastError, "The completion claim did not have sufficient action evidence")
  }

  func testRunPolicyRecoversExpiredActionLease() {
    let running = action(
      .invokeTool,
      "Read workspace",
      id: "tool",
      status: .running,
      resourceId: "local",
      leaseExpiresAtMillis: 100
    )

    let recovered = GlobalAutonomousRunPolicy.recoverIfStale(
      run: run([running], status: .running),
      nowMillis: 101
    )

    XCTAssertEqual(recovered.status, .waitingForResource)
    XCTAssertEqual(recovered.actions.single?.status, .pending)
    XCTAssertEqual(recovered.actions.single?.attemptedResourceIds, ["local"])
    XCTAssertEqual(recovered.actions.single?.lastError, "The delegated action lease expired before a result arrived")
  }
}

private func action(
  _ kind: GlobalAutonomousActionKind,
  _ goal: String,
  id: String = UUID().uuidString,
  status: GlobalAutonomousActionStatus = .pending,
  result: String = "",
  verificationStatus: GlobalActionVerificationStatus = .pending,
  resourceId: String = "",
  leaseExpiresAtMillis: Int64 = 0
) -> GlobalAutonomousAction {
  GlobalAutonomousAction(
    id: id,
    kind: kind,
    goal: goal,
    status: status,
    resourceId: resourceId,
    leaseExpiresAtMillis: leaseExpiresAtMillis,
    result: result,
    verificationStatus: verificationStatus
  )
}

private func run(
  _ actions: [GlobalAutonomousAction],
  status: GlobalAutonomousRunStatus = .queued,
  review: GlobalAutonomousRunReview = GlobalAutonomousRunReview(),
  replanCount: Int = 0
) -> GlobalAutonomousRun {
  GlobalAutonomousRun(
    id: "run",
    sourceCognitionTaskId: "cognition",
    sourceEventId: "event",
    sourceConversationId: "conversation",
    topic: "GalaxySSI runtime",
    goal: "Ship iOS parity",
    actions: actions,
    status: status,
    replanCount: replanCount,
    review: review,
    createdAtMillis: 100,
    updatedAtMillis: 100
  )
}

private extension Array {
  var single: Element? {
    count == 1 ? first : nil
  }
}
