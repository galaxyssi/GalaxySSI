import Foundation
import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthCareTaskRuntimeTests: XCTestCase {
  func testApprovedSubmissionUsesDurableSupervisorAndEncryptedRedactedWorkspace() async throws {
    let f = try HealthDiscussionRecoveryFixture()
    let runtime = GalaxySSIHealthCareTaskRuntime.shared(records: f.records)
    XCTAssertTrue(runtime === GalaxySSIHealthCareTaskRuntime.shared(records: f.records))
    let handle = try runtime.submit(f.approval) { _ in
      try f.records.dispatchLocalCareDiscussionTurn(f.approval, now: f.now)
      try f.records.retainLocalCareDiscussionResponse(f.approval, response: f.response("Synthetic private result"), now: f.now)
      try f.records.applySavedLocalCareDiscussionReply(f.approval, now: f.now)
    }
    await handle.join()
    let workspace = try XCTUnwrap(runtime.persistedWorkspace(f.approval))
    XCTAssertEqual(workspace.status, .completed)
    XCTAssertEqual(workspace.sessionId, f.approval.threadID.uuidString)
    XCTAssertEqual(workspace.conversationId, f.approval.threadID.uuidString)
    XCTAssertEqual(workspace.taskId, handle.taskId)
    XCTAssertTrue(workspace.goal.isEmpty)
    XCTAssertEqual(workspace.resultJson, "{}")
    XCTAssertEqual(try f.turn().execution?.state, .applied)
    XCTAssertTrue(workspace.eventJournal.contains { $0.kind == AgentTaskEventKinds.running })
    let json = try JSONEncoder().encode(workspace)
    for sensitive in [f.approval.question, "Synthetic private result", "fixture-api-key"] {
      XCTAssertNil(json.range(of: Data(sensitive.utf8)))
    }
    let encrypted = try Data(contentsOf: GalaxySSIHealthCareTaskStore.fileURL(records: f.records))
    XCTAssertNil(encrypted.range(of: json))
    let reopened = GalaxySSIHealthCareTaskStore.make(records: f.records)
    XCTAssertEqual(reopened.find(workspace.workspaceId), workspace)
  }

  func testSecondSubmissionDoesNotCreateASecondExecutor() async throws {
    let f = try HealthDiscussionRecoveryFixture()
    let runtime = GalaxySSIHealthCareTaskRuntime.shared(records: f.records)
    var calls = 0
    let handle = try runtime.submit(f.approval) { _ in
      calls += 1
      try f.records.dispatchLocalCareDiscussionTurn(f.approval, now: f.now)
      try f.records.retainLocalCareDiscussionResponse(f.approval, response: f.response("Single result"), now: f.now)
      try f.records.applySavedLocalCareDiscussionReply(f.approval, now: f.now)
    }
    XCTAssertThrowsError(try runtime.submit(f.approval) { _ in calls += 1 })
    var conflicting = f.approval
    conflicting.payload += "changed"
    XCTAssertFalse(runtime.cancel(conflicting))
    await handle.join()
    try await runtime.restore(f.approval, mayApply: { true })
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(try f.records.load().localCareDiscussions?[f.concern.id.uuidString]?.turns.count, 1)
  }

  func testInterruptedDispatchBecomesBlockedWithoutResending() async throws {
    let f = try HealthDiscussionRecoveryFixture()
    let runtime = GalaxySSIHealthCareTaskRuntime.shared(records: f.records)
    var requests = 0
    let handle = try runtime.submit(f.approval) { _ in
      requests += 1
      try f.records.dispatchLocalCareDiscussionTurn(f.approval, now: f.now)
      throw CancellationError()
    }
    await handle.join()
    XCTAssertEqual(runtime.persistedWorkspace(f.approval)?.status, .paused)
    try await runtime.restore(f.approval, mayApply: { true })
    XCTAssertEqual(requests, 1)
    XCTAssertEqual(runtime.persistedWorkspace(f.approval)?.status, .blocked)
    XCTAssertEqual(try f.turn().execution?.state, .interrupted)
    XCTAssertNil(try f.turn().answer)
  }

  func testLegacySavedFinalReceiptMigratesWithoutRunningSubmission() async throws {
    let f = try HealthDiscussionRecoveryFixture()
    try f.records.dispatchLocalCareDiscussionTurn(f.approval, now: f.now)
    try f.records.retainLocalCareDiscussionResponse(f.approval, response: f.response("Restored local-only answer"), now: f.now)
    let runtime = GalaxySSIHealthCareTaskRuntime.shared(records: f.records)
    XCTAssertNil(runtime.persistedWorkspace(f.approval))
    try await runtime.restore(f.approval, mayApply: { true })
    let completed = try XCTUnwrap(runtime.persistedWorkspace(f.approval))
    XCTAssertEqual(completed.status, .completed)
    XCTAssertEqual(try f.turn().answer, "Restored local-only answer")
    try await runtime.restore(f.approval, mayApply: { true })
    XCTAssertEqual(runtime.persistedWorkspace(f.approval), completed)
  }

  func testUserCancellationInWorkspaceFencesAnUnsettledHealthReceipt() async throws {
    let f = try HealthDiscussionRecoveryFixture()
    try f.records.dispatchLocalCareDiscussionTurn(f.approval, now: f.now)
    try f.records.retainLocalCareDiscussionResponse(f.approval, response: f.response("Cancelled pending reply"), now: f.now)
    let runtime = GalaxySSIHealthCareTaskRuntime.shared(records: f.records)
    // Simulate cancellation surviving even if the separate Health write did not finish.
    XCTAssertTrue(runtime.cancel(f.approval))
    XCTAssertEqual(try f.turn().execution?.state, .received)
    XCTAssertEqual(runtime.persistedWorkspace(f.approval)?.status, .cancelled)
    try await runtime.restore(f.approval, mayApply: { true })
    XCTAssertEqual(try f.turn().execution?.state, .interrupted)
    XCTAssertNil(try f.turn().answer)
    XCTAssertNotNil(try f.turn().execution?.response)
  }

  func testInterruptedPostCommitBookkeepingReconcilesWithoutApplyingTwice() async throws {
    let f = try HealthDiscussionRecoveryFixture()
    let runtime = GalaxySSIHealthCareTaskRuntime.shared(records: f.records)
    let handle = try runtime.submit(f.approval) { _ in
      try f.records.dispatchLocalCareDiscussionTurn(f.approval, now: f.now)
      try f.records.retainLocalCareDiscussionResponse(f.approval, response: f.response("Committed before interruption"), now: f.now)
      try f.records.applySavedLocalCareDiscussionReply(f.approval, now: f.now)
      throw CancellationError()
    }
    await handle.join()
    let committed = try f.turn()
    XCTAssertEqual(committed.execution?.state, .applied)
    XCTAssertEqual(runtime.persistedWorkspace(f.approval)?.status, .paused)
    try await runtime.restore(f.approval, mayApply: { false })
    XCTAssertEqual(try f.turn(), committed)
    XCTAssertEqual(runtime.persistedWorkspace(f.approval)?.status, .completed)
  }

  func testQuarantinedControlReplyIsNotACompletedTask() async throws {
    let f = try HealthDiscussionRecoveryFixture()
    let runtime = GalaxySSIHealthCareTaskRuntime.shared(records: f.records)
    let handle = try runtime.submit(f.approval) { _ in
      try f.records.dispatchLocalCareDiscussionTurn(f.approval, now: f.now)
      try f.records.retainLocalCareDiscussionResponse(f.approval, response: f.response(#"{"actions":[]}"#), now: f.now)
      try f.records.applySavedLocalCareDiscussionReply(f.approval, now: f.now)
    }
    await handle.join()
    XCTAssertEqual(try f.turn().execution?.state, .interrupted)
    XCTAssertEqual(runtime.persistedWorkspace(f.approval)?.status, .blocked)
    XCTAssertNil(try f.turn().answer)
  }

  func testEncryptedWorkspaceRejectsOtherOwnerEvenWithTheSameKey() throws {
    let f = try HealthDiscussionRecoveryFixture()
    let store = GalaxySSIHealthCareTaskStore.make(records: f.records)
    let workspace = try store.upsert(.init(workspaceId: "fixture", sessionId: "session", conversationId: "conversation",
      taskId: "task", goal: "Synthetic secret for encryption fixture"), expectedRevision: 0)
    let url = GalaxySSIHealthCareTaskStore.fileURL(records: f.records)
    let before = try Data(contentsOf: url)
    XCTAssertNil(before.range(of: Data(workspace.goal.utf8)))
    let key = try XCTUnwrap(f.secrets.string(account: "health.discussion.tasks.v1." + f.records.owner))
    try f.secrets.setString(key, account: "health.discussion.tasks.v1.foreign-owner")
    let foreign = GalaxySSIHealthRecords(owner: "foreign-owner", secrets: f.secrets, isolatedFile: f.file)
    let other = GalaxySSIHealthCareTaskStore.make(records: foreign)
    XCTAssertNil(other.find(workspace.workspaceId))
    XCTAssertThrowsError(try other.upsert(workspace, expectedRevision: workspace.revision))
    XCTAssertEqual(try Data(contentsOf: url), before)
  }

  func testMissingEncryptionKeyCannotResetAnExistingWorkspaceFile() throws {
    let f = try HealthDiscussionRecoveryFixture()
    let store = GalaxySSIHealthCareTaskStore.make(records: f.records)
    let workspace = try store.upsert(.init(workspaceId: "fixture", sessionId: "session", conversationId: "conversation",
      taskId: "task"), expectedRevision: 0)
    let url = GalaxySSIHealthCareTaskStore.fileURL(records: f.records)
    let before = try Data(contentsOf: url)
    f.secrets.delete(account: "health.discussion.tasks.v1." + f.records.owner)
    XCTAssertThrowsError(try store.upsert(workspace, expectedRevision: workspace.revision))
    XCTAssertEqual(try Data(contentsOf: url), before)
    XCTAssertNil(f.secrets.string(account: "health.discussion.tasks.v1." + f.records.owner))
  }
}
