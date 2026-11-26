import Foundation
import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthCareAgentTranscriptTests: XCTestCase {
  typealias Projection = GalaxySSIHealthCareAgentTranscriptProjection

  func testOnlyOriginalBoundConversationReceivesPrivateRows() throws {
    let f = try HealthDiscussionRecoveryFixture()
    var thread = try boundThread(f)
    XCTAssertEqual(project(f, thread).map(\.id), [f.approval.id])
    XCTAssertTrue(Projection.rows(thread, owner: f.records.owner, conversation: "foreign",
      workspaces: [:], isExecuting: { _ in false }).isEmpty)
    thread.archivedAt = f.now
    XCTAssertTrue(project(f, thread).isEmpty)
  }

  func testPersistedRunningWorkspaceWithoutLiveHandleCannotKeepClockRunning() throws {
    let f = try HealthDiscussionRecoveryFixture()
    let thread = try boundThread(f)
    var workspace = workspace(f, thread)
    workspace.status = .running
    workspace.updatedAtMillis = Int64(f.now.addingTimeInterval(8).timeIntervalSince1970 * 1_000)
    let row = try XCTUnwrap(project(f, thread, workspace: workspace, now: f.now.addingTimeInterval(90)).first)
    XCTAssertEqual(row.reply, .interruptedRequest)
    XCTAssertFalse(try XCTUnwrap(row.clock).running(at: f.now.addingTimeInterval(90)))
    XCTAssertEqual(row.clock?.seconds(at: f.now.addingTimeInterval(90)), 8)
    XCTAssertEqual(row.clock?.seconds(at: f.now.addingTimeInterval(900)), 8)
  }

  func testLiveClockUsesOriginalDeadlineAndExactWorkspaceIdentity() throws {
    let f = try HealthDiscussionRecoveryFixture()
    let thread = try boundThread(f)
    var workspace = workspace(f, thread)
    workspace.status = .running
    let row = try XCTUnwrap(project(f, thread, workspace: workspace, live: true).first)
    XCTAssertEqual(row.reply, .waiting)
    XCTAssertEqual(row.clock?.seconds(at: f.now.addingTimeInterval(12)), 12)
    XCTAssertTrue(row.clock?.running(at: f.now.addingTimeInterval(12)) == true)
    XCTAssertFalse(row.clock?.running(at: f.now.addingTimeInterval(601)) == true)
    XCTAssertEqual(row.clock?.seconds(at: f.now.addingTimeInterval(900)), 600)
    workspace.conversationId = "other-conversation"
    let foreign = try XCTUnwrap(project(f, thread, workspace: workspace, live: true).first)
    XCTAssertEqual(foreign.reply, .interruptedRequest)
    XCTAssertFalse(foreign.clock?.running(at: f.now) == true)
  }

  func testAppliedAnswerAndOriginalReceiptDurationSurviveReopenProjection() throws {
    let f = try HealthDiscussionRecoveryFixture()
    var thread = try boundThread(f)
    thread.turns[0].answer = "Synthetic retained answer"
    thread.turns[0].execution?.state = .applied
    thread.turns[0].execution?.receivedAt = f.now.addingTimeInterval(16)
    let encoded = try JSONEncoder().encode(thread)
    let reopened = try JSONDecoder().decode(GalaxySSIHealthCareDiscussion.Thread.self, from: encoded)
    let row = try XCTUnwrap(project(f, reopened, live: true).first)
    XCTAssertEqual(row.reply, .answer("Synthetic retained answer"))
    XCTAssertEqual(row.question, f.approval.question)
    XCTAssertEqual(row.clock?.seconds(at: f.now.addingTimeInterval(1_000)), 16)
    XCTAssertFalse(row.clock?.running(at: f.now) == true)
  }

  func testControlReplyNeverBecomesAnAnswerAndTerminalReviewResultsRemainReviewOnly() throws {
    let f = try HealthDiscussionRecoveryFixture()
    var thread = try boundThread(f)
    thread.turns[0].answer = #"{"actions":[{"kind":"CALL_NATIVE_TOOL"}]}"#
    XCTAssertEqual(project(f, thread).first?.reply, .interruptedControl)
    thread.turns[0].answer = nil
    thread.turns[0].proposalID = UUID()
    XCTAssertEqual(project(f, thread).first?.reply, .plan)
    thread.turns[0].proposalID = nil
    thread.turns[0].questionsRetained = true
    XCTAssertEqual(project(f, thread).first?.reply, .questions)
    thread.turns[0].questionsRetained = nil
    thread.turns[0].answerDraftStaged = true
    XCTAssertEqual(project(f, thread).first?.reply, .answerDraft)
  }

  func testForeignExecutionCannotSupplyReplyOrClock() throws {
    let f = try HealthDiscussionRecoveryFixture()
    var thread = try boundThread(f)
    thread.turns[0].execution = try .init(approval: f.approval, agentConversationID: "foreign-agent", startedAt: f.now)
    thread.turns[0].answer = "Do not project a mismatched receipt"
    let row = try XCTUnwrap(project(f, thread, live: true).first)
    XCTAssertEqual(row.reply, .interruptedRequest)
    XCTAssertNil(row.clock)
  }

  func testCancellationStopsDespiteLiveHandleAndDuplicateInterruptionDoesNotMoveStopTime() throws {
    let f = try HealthDiscussionRecoveryFixture()
    try f.records.interruptLocalCareDiscussionExecution(f.approval, now: f.now.addingTimeInterval(20))
    try f.records.interruptLocalCareDiscussionExecution(f.approval, now: f.now.addingTimeInterval(40))
    XCTAssertEqual(try f.turn().execution?.stoppedAt, f.now.addingTimeInterval(20))
    var thread = try boundThread(f)
    thread.turns[0].execution?.state = .dispatched
    thread.turns[0].execution?.stoppedAt = nil
    var workspace = workspace(f, thread)
    workspace.status = .running
    workspace.cancellationRequested = true
    XCTAssertEqual(project(f, thread, workspace: workspace, live: true).first?.reply, .interruptedRequest)
    XCTAssertFalse(project(f, thread, workspace: workspace, live: true).first?.clock?.running(at: f.now) == true)
  }

  func testLegacyTurnWithoutExecutionIsNotFabricatedAsRunning() throws {
    let f = try HealthDiscussionRecoveryFixture()
    var thread = try boundThread(f)
    thread.turns[0].execution = nil
    let row = try XCTUnwrap(project(f, thread, live: true).first)
    XCTAssertEqual(row.reply, .noSavedReply)
    XCTAssertNil(row.clock)
    let before = try JSONEncoder().encode(thread)
    _ = project(f, thread)
    XCTAssertEqual(try JSONDecoder().decode(GalaxySSIHealthCareDiscussion.Thread.self, from: before), thread)
  }

  func testOlderExecutionSchemaDecodesWithoutInventingAStopTime() throws {
    let f = try HealthDiscussionRecoveryFixture()
    let execution = try XCTUnwrap(f.turn().execution)
    var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(execution)) as! [String: Any]
    object.removeValue(forKey: "stoppedAt")
    let decoded = try JSONDecoder().decode(GalaxySSIHealthCareDiscussionRecovery.Execution.self,
      from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNil(decoded.stoppedAt)
    XCTAssertEqual(decoded.approval, f.approval)
    try f.records.interruptLocalCareDiscussionExecution(f.approval, now: f.now.addingTimeInterval(10))
    let reopened = GalaxySSIHealthRecords(owner: f.records.owner, secrets: f.secrets, isolatedFile: f.file)
    XCTAssertEqual(try reopened.load().localCareDiscussions?[f.concern.id.uuidString]?.turns.last?.execution?.stoppedAt,
      f.now.addingTimeInterval(10))
  }

  private func boundThread(_ f: HealthDiscussionRecoveryFixture) throws -> GalaxySSIHealthCareDiscussion.Thread {
    var thread = try XCTUnwrap(f.records.load().localCareDiscussions?[f.concern.id.uuidString])
    thread.agentConversationID = "health-agent"
    thread.turns[0].execution = try .init(approval: f.approval, agentConversationID: "health-agent", startedAt: f.now)
    return thread
  }

  private func workspace(_ f: HealthDiscussionRecoveryFixture, _ thread: GalaxySSIHealthCareDiscussion.Thread) -> AgentWorkspace {
    let id = "private:" + AgentModelLoopRecoveryIdentity.sha256(["owner": f.records.owner,
      "thread": thread.id.uuidString, "turn": f.approval.id.uuidString])
    return .init(workspaceId: id, sessionId: thread.id.uuidString, conversationId: "health-agent", taskId: id,
      updatedAtMillis: Int64(f.now.timeIntervalSince1970 * 1_000))
  }

  private func project(_ f: HealthDiscussionRecoveryFixture, _ thread: GalaxySSIHealthCareDiscussion.Thread,
      workspace: AgentWorkspace? = nil, live: Bool = false, now: Date? = nil) -> [Projection.Row] {
    let snapshot = workspace.map { [$0.workspaceId: $0] } ?? [:]
    return Projection.rows(thread, owner: f.records.owner, conversation: "health-agent", now: now ?? f.now,
      workspaces: snapshot, isExecuting: { _ in live })
  }
}
