import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthCareActiveRevocationTests: XCTestCase {
  func testWithdrawalPersistsExactCancellationBeforeAnyReconciliation() throws {
    let f = try HealthModelReviewFixture(paired: true)
    let binding = try bind(f)
    XCTAssertNotNil(f.records.currentLocalCareDesktopResearch(binding.identity,
      contact: binding.route.connector.contactId, source: binding.source, now: f.now))
    try f.records.setHealthOnlinePermission(false)
    // Deliberately do not run the lifecycle or reconciliation before reopening.
    let reopened = reopen(f)
    let archive = try reopened.load()
    XCTAssertNil(archive.healthOnlinePermission)
    XCTAssertNil(archive.localCareResearch?.authorizations[f.concern.id.uuidString])
    XCTAssertEqual(archive.localCareResearch?.jobs[f.concern.id.uuidString]?.state, .cancelled)
    XCTAssertNil(archive.localCareResearch?.desktopTransport?.active[binding.job.uuidString])
    let cancellation = try XCTUnwrap(reopened.pendingLocalCareDesktopCancellations().first)
    XCTAssertEqual(cancellation.binding, binding)
    XCTAssertEqual(cancellation.payload.string("task_id"), binding.identity.taskId)
    XCTAssertEqual(cancellation.payload.string("source_message_id"), String(binding.source))
    XCTAssertEqual(cancellation.payload.string("conversation_id"), binding.identity.conversationId)
    XCTAssertEqual(cancellation.payload.string("turn_id"), binding.identity.turnId)
    try assertRetained(f, records: reopened)
  }

  func testRepeatedWithdrawalAndRecoveryDoNotReplaceTheCancellation() throws {
    let f = try HealthModelReviewFixture(paired: true)
    _ = try bind(f)
    try f.records.setHealthOnlinePermission(false)
    let first = try f.records.pendingLocalCareDesktopCancellations()
    XCTAssertEqual(first.count, 1)
    for _ in 0..<3 {
      let reopened = reopen(f)
      try reopened.setHealthOnlinePermission(false)
      XCTAssertTrue(try reopened.reconcileLocalCareResearch(now: f.now).isEmpty)
      XCTAssertEqual(try reopened.pendingLocalCareDesktopCancellations(), first)
    }
  }

  func testReenablingOnlineAnalysisDoesNotRestoreStandingConsentOrDispatch() throws {
    let f = try HealthModelReviewFixture(paired: true)
    let binding = try bind(f)
    let oldPermission = try XCTUnwrap(f.records.load().healthOnlinePermission)
    try f.records.setHealthOnlinePermission(false)
    let reopened = reopen(f)
    try reopened.setHealthOnlinePermission(true)
    XCTAssertNotEqual(try reopened.load().healthOnlinePermission, oldPermission)
    XCTAssertTrue(try reopened.reconcileLocalCareResearch(now: f.now).isEmpty)
    XCTAssertNil(reopened.currentLocalCareDesktopResearch(binding.identity,
      contact: binding.route.connector.contactId, source: binding.source, now: f.now))
    XCTAssertThrowsError(try reopened.validateLocalCareDiscussionTurn(f.approval, now: f.now))
    XCTAssertEqual(try reopened.load().localCareResearch?.jobs.count, 1)
    try assertRetained(f, records: reopened)
  }

  func testSyntheticLateFinalCannotBeRetainedBeforeOrAfterReopenAndReenable() throws {
    let f = try HealthModelReviewFixture(paired: true)
    let binding = try bind(f)
    try f.records.setHealthOnlinePermission(false)
    let sentinel = "SYNTHETIC_REVOKED_HEALTH_FINAL"
    let envelope = AgentMcpJSONCodec.stringify(["assessment": .object(try f.arguments()),
      "plan": .null, "answer": .string(sentinel)])
    for records in [f.records, reopen(f)] {
      XCTAssertNil(records.currentLocalCareDesktopResearch(binding.identity,
        contact: binding.route.connector.contactId, source: binding.source, now: f.now))
      XCTAssertThrowsError(try GalaxySSIHealthDesktopResearch.retainStructuredReview(envelope,
        approval: f.approval, records: records, now: f.now))
      try assertRetained(f, records: records)
    }
    let reenabled = reopen(f)
    try reenabled.setHealthOnlinePermission(true)
    XCTAssertThrowsError(try GalaxySSIHealthDesktopResearch.retainStructuredReview(envelope,
      approval: f.approval, records: reenabled, now: f.now))
    XCTAssertFalse(try reenabled.load().localCareDiscussions?[f.concern.id.uuidString]?.turns.contains {
      $0.answer?.contains(sentinel) == true
    } ?? true)
    try assertRetained(f, records: reenabled)
  }

  func testCancellationHandoffIsExactAndDurableWithoutRevivingTheTask() throws {
    let f = try HealthModelReviewFixture(paired: true)
    _ = try bind(f)
    try f.records.setHealthOnlinePermission(false)
    let reopened = reopen(f)
    let pending = try XCTUnwrap(reopened.pendingLocalCareDesktopCancellations().first)
    let different = GalaxySSIHealthDesktopResearch.Cancellation(binding: pending.binding,
      createdAtMillis: pending.createdAtMillis + 1)
    XCTAssertThrowsError(try reopened.markLocalCareDesktopCancellationQueued(different))
    XCTAssertEqual(try reopened.pendingLocalCareDesktopCancellations(), [pending])
    try reopened.markLocalCareDesktopCancellationQueued(pending)
    let after = reopen(f)
    XCTAssertTrue(try after.pendingLocalCareDesktopCancellations().isEmpty)
    XCTAssertThrowsError(try after.markLocalCareDesktopCancellationQueued(pending))
    XCTAssertTrue(try after.dispatchedLocalCareDesktopResearch().isEmpty)
    try assertRetained(f, records: after)
  }

  func testCompletedAssessmentsAndRepliesAreNotDeletedOnWithdrawal() throws {
    let f = try HealthModelReviewFixture(paired: true)
    _ = try bind(f)
    let review = try f.records.recordLocalCareModelReview(f.approval, arguments: f.arguments(), now: f.now)
    try f.records.finishLocalCareDiscussionTurn(f.approval, answer: "Synthetic retained historical assessment", now: f.now)
    try f.records.setHealthOnlinePermission(false)
    let archive = try reopen(f).load()
    XCTAssertEqual(archive.localCareModelReviews?[review.id], review)
    XCTAssertEqual(archive.localCareDiscussions?[f.concern.id.uuidString]?.turns.last?.answer,
      "Synthetic retained historical assessment")
    XCTAssertEqual(archive.localCareResearch?.jobs[f.concern.id.uuidString]?.state, .completed)
    XCTAssertTrue(try reopen(f).pendingLocalCareDesktopCancellations().isEmpty)
  }

  private func bind(_ f: HealthModelReviewFixture) throws -> GalaxySSIHealthDesktopResearch.Binding {
    let auth = try XCTUnwrap(f.records.load().localCareResearch?.authorizations[f.concern.id.uuidString])
    return try f.records.bindLocalCareDesktopResearch(auth, job: f.approval.id, sender: "synthetic-phone",
      reviewedAt: f.approval.reviewedAt, now: f.now)
  }

  private func reopen(_ f: HealthModelReviewFixture) -> GalaxySSIHealthRecords {
    GalaxySSIHealthRecords(owner: f.records.owner, secrets: f.secrets, isolatedFile: f.file)
  }

  private func assertRetained(_ f: HealthModelReviewFixture, records: GalaxySSIHealthRecords) throws {
    let archive = try records.load()
    XCTAssertFalse(archive.current.isEmpty)
    XCTAssertEqual(archive.localCareDiscussions?[f.concern.id.uuidString]?.id, f.approval.threadID)
    XCTAssertEqual(archive.localCareDiscussions?[f.concern.id.uuidString]?.turns.map(\.id), [f.approval.id])
    XCTAssertEqual(archive.localCareDiscussions?[f.concern.id.uuidString]?.turns.last?.question, f.approval.question)
    XCTAssertNil(archive.localCareDiscussions?[f.concern.id.uuidString]?.turns.last?.answer)
    XCTAssertNil(archive.localCareModelReviews?[f.approval.id])
    XCTAssertNil(archive.localCareModelAttention?[f.concern.id])
    XCTAssertTrue(archive.localCarePlans?.isEmpty ?? true)
    XCTAssertTrue(archive.localCareFollowUps?.isEmpty ?? true)
    XCTAssertTrue(archive.localCare?.current["glucose"]?.adoptedActions?.isEmpty ?? true)
    XCTAssertNil(archive.localCare?.current["glucose"]?.target)
  }
}
