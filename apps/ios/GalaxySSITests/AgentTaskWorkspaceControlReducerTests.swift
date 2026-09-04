import XCTest
@testable import GalaxySSI

final class AgentTaskWorkspaceControlReducerTests: XCTestCase {
  func testCancelTransitionsRunningWorkspaceAndRequestsExecutionCancellation() {
    let active = workspace(
      status: .running,
      events: [event(1, AgentTaskEventKinds.running, 1_000, message: "running")]
    )

    let reduction = AgentTaskWorkspaceControlReducer.cancel(
      workspace: active,
      reason: "  User stopped task  ",
      observedAtMillis: 1_500
    )

    XCTAssertTrue(reduction.changed)
    XCTAssertTrue(reduction.shouldCancelExecution)
    XCTAssertEqual(reduction.cancelExecutionReason, "User stopped task")
    XCTAssertEqual(reduction.workspace.status, .cancelled)
    XCTAssertTrue(reduction.workspace.cancellationRequested)
    XCTAssertEqual(reduction.workspace.eventSequence, 2)
    XCTAssertEqual(reduction.workspace.eventJournal.last?.kind, AgentTaskEventKinds.cancelled)
    XCTAssertEqual(reduction.workspace.eventJournal.last?.message, "User stopped task")
    XCTAssertEqual(reduction.workspace.eventJournal.last?.timestampMillis, 1_500)
  }

  func testCancelMarksAlreadyCancelledWorkspaceAsCancellationRequested() {
    let cancelledWithoutFlag = workspace(
      status: .cancelled,
      events: [event(1, AgentTaskEventKinds.cancelled, 1_000, message: "cancelled")],
      cancellationRequested: false
    )

    let reduction = AgentTaskWorkspaceControlReducer.cancel(
      workspace: cancelledWithoutFlag,
      reason: "",
      observedAtMillis: 1_600
    )

    XCTAssertTrue(reduction.changed)
    XCTAssertTrue(reduction.shouldCancelExecution)
    XCTAssertEqual(reduction.cancelExecutionReason, "Task cancellation requested")
    XCTAssertEqual(reduction.workspace.status, .cancelled)
    XCTAssertTrue(reduction.workspace.cancellationRequested)
    XCTAssertEqual(reduction.workspace.eventJournal.last?.message, "Task cancellation requested")
  }

  func testCancelLeavesCompletedWorkspaceUnchanged() {
    let completed = workspace(
      status: .completed,
      events: [event(1, AgentTaskEventKinds.completed, 1_000, message: "done")]
    )

    let reduction = AgentTaskWorkspaceControlReducer.cancel(
      workspace: completed,
      reason: "stop",
      observedAtMillis: 1_600
    )

    XCTAssertFalse(reduction.changed)
    XCTAssertFalse(reduction.shouldCancelExecution)
    XCTAssertEqual(reduction.cancelExecutionReason, "")
    XCTAssertEqual(reduction.workspace, completed)
  }

  func testPermissionRevocationPausesWorkspaceAndCancelsExecution() {
    let active = workspace(
      status: .waitingResponse,
      events: [event(1, AgentTaskEventKinds.waitingResponse, 1_000, message: "waiting")]
    )

    let reduction = AgentTaskWorkspaceControlReducer.pauseForPermissionRevocation(
      workspace: active,
      reason: "  Contacts grant revoked  ",
      observedAtMillis: 1_700
    )

    XCTAssertTrue(reduction.changed)
    XCTAssertTrue(reduction.shouldCancelExecution)
    XCTAssertEqual(reduction.cancelExecutionReason, "Contacts grant revoked")
    XCTAssertEqual(reduction.workspace.status, .paused)
    XCTAssertFalse(reduction.workspace.cancellationRequested)
    XCTAssertEqual(reduction.workspace.eventSequence, 2)
    XCTAssertEqual(reduction.workspace.eventJournal.last?.kind, AgentTaskEventKinds.permissionRevoked)
    XCTAssertEqual(reduction.workspace.eventJournal.last?.message, "Contacts grant revoked")
  }

  func testPermissionRevocationIgnoresTerminalAndCancellationRequestedWorkspaces() {
    let completed = workspace(status: .completed)
    let cancelling = workspace(status: .running, cancellationRequested: true)

    let completedReduction = AgentTaskWorkspaceControlReducer.pauseForPermissionRevocation(
      workspace: completed,
      observedAtMillis: 2_000
    )
    let cancellingReduction = AgentTaskWorkspaceControlReducer.pauseForPermissionRevocation(
      workspace: cancelling,
      observedAtMillis: 2_000
    )

    XCTAssertFalse(completedReduction.changed)
    XCTAssertFalse(completedReduction.shouldCancelExecution)
    XCTAssertEqual(completedReduction.workspace, completed)
    XCTAssertFalse(cancellingReduction.changed)
    XCTAssertFalse(cancellingReduction.shouldCancelExecution)
    XCTAssertEqual(cancellingReduction.workspace, cancelling)
  }

  func testControlReducerPrunesEventJournalAndUsesAndroidWireNames() throws {
    let events = (1...105).map {
      event(Int64($0), AgentTaskEventKinds.progress, Int64($0), message: "event-\($0)")
    }
    let active = workspace(status: .running, events: events)

    let reduction = AgentTaskWorkspaceControlReducer.cancel(
      workspace: active,
      reason: "stop",
      observedAtMillis: 2_000
    )
    let encoded = String(decoding: try JSONEncoder().encode(reduction), as: UTF8.self)

    XCTAssertEqual(reduction.workspace.eventJournal.count, 100)
    XCTAssertEqual(reduction.workspace.eventJournal.first?.sequence, 7)
    XCTAssertTrue(encoded.contains(#""should_cancel_execution":true"#))
    XCTAssertTrue(encoded.contains(#""cancel_execution_reason":"stop""#))
    XCTAssertTrue(encoded.contains(#""cancellation_requested":true"#))
  }

  private func workspace(
    status: AgentWorkspaceStatus,
    events: [AgentWorkspaceEvent] = [],
    cancellationRequested: Bool = false
  ) -> AgentWorkspace {
    AgentWorkspace(
      workspaceId: "workspace",
      sessionId: "session",
      conversationId: "conversation",
      taskId: "task",
      status: status,
      eventSequence: events.map(\.sequence).max() ?? 0,
      eventJournal: events,
      cancellationRequested: cancellationRequested,
      createdAtMillis: 1_000,
      updatedAtMillis: events.map(\.timestampMillis).max() ?? 1_000
    )
  }

  private func event(
    _ sequence: Int64,
    _ kind: String,
    _ timestampMillis: Int64,
    message: String = ""
  ) -> AgentWorkspaceEvent {
    AgentWorkspaceEvent(
      sequence: sequence,
      kind: kind,
      message: message,
      timestampMillis: timestampMillis
    )
  }
}
