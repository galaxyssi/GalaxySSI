import XCTest
@testable import GalaxySSI

final class AgentConnectorLateResponseReducerTests: XCTestCase {
  func testReconcilesFailedWorkspaceWithMatchingHandoff() {
    let failed = workspace(
      status: .failed,
      errorMessage: "running_progress_timeout",
      handoffIds: ["connector:71"],
      events: [event(1, AgentTaskEventKinds.timedOut, 1_000, message: "timeout")]
    )

    let reduction = AgentConnectorLateResponseReducer.reconcile(
      workspace: failed,
      sourceMessageId: 71,
      observedAtMillis: 2_000
    )

    XCTAssertTrue(reduction.changed)
    XCTAssertTrue(reduction.accepted)
    XCTAssertEqual(reduction.sourceMessageId, 71)
    XCTAssertEqual(reduction.workspace?.status, .waitingResponse)
    XCTAssertEqual(reduction.workspace?.errorMessage, "")
    XCTAssertEqual(reduction.workspace?.eventSequence, 2)
    XCTAssertEqual(reduction.workspace?.eventJournal.last?.kind, AgentTaskEventKinds.lateResponse)
    XCTAssertEqual(reduction.workspace?.eventJournal.last?.message, AgentConnectorLateResponseReducer.defaultMessage)
    XCTAssertEqual(reduction.workspace?.eventJournal.last?.payloadJson, #"{"source_message_id":71}"#)
    XCTAssertEqual(reduction.workspace?.updatedAtMillis, 2_000)
  }

  func testReconcilesFailedWorkspaceWithMatchingRemoteRunId() {
    let failed = workspace(
      status: .failed,
      errorMessage: "timeout",
      remoteRunId: "71"
    )

    let reduction = AgentConnectorLateResponseReducer.reconcile(
      workspace: failed,
      sourceMessageId: 71,
      observedAtMillis: 2_000
    )

    XCTAssertTrue(reduction.accepted)
    XCTAssertEqual(reduction.workspace?.status, .waitingResponse)
    XCTAssertEqual(reduction.workspace?.eventJournal.last?.kind, AgentTaskEventKinds.lateResponse)
  }

  func testRejectsInvalidSourceAndMismatchedHandoff() {
    let failed = workspace(
      status: .failed,
      errorMessage: "timeout",
      handoffIds: ["connector:72"],
      remoteRunId: "73"
    )

    let invalid = AgentConnectorLateResponseReducer.reconcile(
      workspace: failed,
      sourceMessageId: 0,
      observedAtMillis: 2_000
    )
    let mismatch = AgentConnectorLateResponseReducer.reconcile(
      workspace: failed,
      sourceMessageId: 71,
      observedAtMillis: 2_000
    )

    XCTAssertFalse(invalid.accepted)
    XCTAssertNil(invalid.workspace)
    XCTAssertFalse(mismatch.accepted)
    XCTAssertNil(mismatch.workspace)
  }

  func testLeavesNonFailedWorkspaceAndCancelledWorkspaceUnchanged() {
    let waiting = workspace(status: .waitingResponse, handoffIds: ["connector:71"])
    let cancelled = workspace(
      status: .failed,
      handoffIds: ["connector:71"],
      cancellationRequested: true
    )

    let waitingReduction = AgentConnectorLateResponseReducer.reconcile(
      workspace: waiting,
      sourceMessageId: 71,
      observedAtMillis: 2_000
    )
    let cancelledReduction = AgentConnectorLateResponseReducer.reconcile(
      workspace: cancelled,
      sourceMessageId: 71,
      observedAtMillis: 2_000
    )

    XCTAssertFalse(waitingReduction.changed)
    XCTAssertFalse(waitingReduction.accepted)
    XCTAssertEqual(waitingReduction.workspace, Optional(waiting))
    XCTAssertFalse(cancelledReduction.changed)
    XCTAssertFalse(cancelledReduction.accepted)
    XCTAssertNil(cancelledReduction.workspace)
  }

  func testLateResponsePrunesEventJournalAndUsesAndroidWireNames() throws {
    let events = (1...105).map {
      event(Int64($0), AgentTaskEventKinds.progress, Int64($0), message: "event-\($0)")
    }
    let failed = workspace(
      status: .failed,
      handoffIds: ["handoff:71"],
      events: events
    )

    let reduction = AgentConnectorLateResponseReducer.reconcile(
      workspace: failed,
      sourceMessageId: 71,
      observedAtMillis: 2_000
    )
    let encoded = String(decoding: try JSONEncoder().encode(reduction), as: UTF8.self)

    XCTAssertEqual(reduction.workspace?.eventJournal.count, 100)
    XCTAssertEqual(reduction.workspace?.eventJournal.first?.sequence, 7)
    XCTAssertTrue(encoded.contains(#""accepted":true"#))
    XCTAssertTrue(encoded.contains(#""source_message_id":71"#))
    XCTAssertTrue(encoded.contains(#""task.late_response""#))
  }

  private func workspace(
    status: AgentWorkspaceStatus,
    errorMessage: String = "",
    handoffIds: [String] = [],
    remoteRunId: String = "",
    events: [AgentWorkspaceEvent] = [],
    cancellationRequested: Bool = false
  ) -> AgentWorkspace {
    AgentWorkspace(
      workspaceId: "workspace",
      sessionId: "session",
      conversationId: "conversation",
      taskId: "task",
      remoteRunId: remoteRunId,
      status: status,
      errorMessage: errorMessage,
      handoffIds: handoffIds,
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
