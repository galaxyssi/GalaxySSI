import XCTest
@testable import GalaxySSI

final class AgentTaskLivenessWorkspaceReducerTests: XCTestCase {
  func testSweepMarksWorkspaceStalledOnceAndEmitsSignal() {
    let workspace = self.workspace(
      status: .running,
      events: [event(1, AgentTaskEventKinds.running, 1_000, message: "running")]
    )

    let first = AgentTaskLivenessWorkspaceReducer.sweep(
      workspace: workspace,
      policy: policy(),
      nowMillis: 1_100
    )
    let duplicate = AgentTaskLivenessWorkspaceReducer.sweep(
      workspace: first.workspace,
      policy: policy(),
      nowMillis: 1_150
    )

    XCTAssertTrue(first.changed)
    XCTAssertEqual(first.signal?.kind, .stalled)
    XCTAssertEqual(first.signal?.reason, "running_progress_stalled")
    XCTAssertEqual(first.workspace.status, .running)
    XCTAssertEqual(first.workspace.eventSequence, 2)
    XCTAssertEqual(first.workspace.eventJournal.last?.kind, AgentTaskEventKinds.stalled)
    XCTAssertEqual(first.workspace.eventJournal.last?.message, "running_progress_stalled")
    XCTAssertEqual(first.workspace.eventJournal.last?.payloadJson, #"{"idle_ms":100,"lifetime_ms":100}"#)
    XCTAssertEqual(first.workspace.updatedAtMillis, 1_100)
    XCTAssertFalse(duplicate.changed)
    XCTAssertNil(duplicate.signal)
  }

  func testRecordActivityAfterStallEmitsRecoveredSignal() {
    let stalled = workspace(
      status: .running,
      events: [
        event(1, AgentTaskEventKinds.running, 1_000, message: "running"),
        event(2, AgentTaskEventKinds.stalled, 1_100, message: "running_progress_stalled")
      ]
    )

    let reduction = AgentTaskLivenessWorkspaceReducer.recordActivity(
      workspace: stalled,
      eventKind: AgentTaskEventKinds.progress,
      stage: "observe",
      message: "saw update",
      policy: policy(),
      observedAtMillis: 1_120
    )

    XCTAssertTrue(reduction.changed)
    XCTAssertEqual(reduction.signal?.kind, .recovered)
    XCTAssertEqual(reduction.signal?.reason, "progress_resumed")
    XCTAssertEqual(reduction.workspace.eventSequence, 3)
    XCTAssertEqual(reduction.workspace.eventJournal.last?.kind, AgentTaskEventKinds.progress)
    XCTAssertEqual(reduction.workspace.eventJournal.last?.message, "saw update")
    XCTAssertEqual(reduction.workspace.eventJournal.last?.payloadJson, #"{"stage":"observe"}"#)
  }

  func testNativeToolWorkspaceProgressBridgeMatchesAndroidSupervisorProgress() {
    let started = AgentNativeToolLifecycleEvent(
      stage: .started,
      toolId: "galaxyssi.workspace.file.read.text",
      invocationId: "invoke-1",
      stepId: "step-1",
      conversationId: "conversation",
      turnId: "workspace",
      timestampMillis: 1_200
    )
    let progress = AgentNativeToolLifecycleEvent(
      stage: .progress,
      toolId: "galaxyssi.workspace.file.read.text",
      invocationId: "invoke-1",
      stepId: "step-1",
      conversationId: "conversation",
      turnId: "workspace",
      progressStage: "reading",
      message: "Reading file",
      percent: 64,
      sequence: 2,
      timestampMillis: 1_250
    )
    let finished = AgentNativeToolLifecycleEvent(
      stage: .finished,
      toolId: "galaxyssi.workspace.file.read.text",
      invocationId: "invoke-1",
      stepId: "step-1",
      conversationId: "conversation",
      turnId: "workspace",
      status: .succeeded,
      timestampMillis: 1_300
    )

    let first = AgentNativeToolWorkspaceProgressBridge.record(event: started, in: workspace(status: .running))
    let second = AgentNativeToolWorkspaceProgressBridge.record(event: progress, in: first.workspace)
    let third = AgentNativeToolWorkspaceProgressBridge.record(event: finished, in: second.workspace)
    let terminal = AgentNativeToolWorkspaceProgressBridge.record(event: progress, in: workspace(status: .completed))

    XCTAssertEqual(AgentNativeToolWorkspaceProgressBridge.workspaceId(for: progress), "workspace")
    XCTAssertTrue(first.changed)
    XCTAssertTrue(second.changed)
    XCTAssertTrue(third.changed)
    XCTAssertFalse(terminal.changed)
    XCTAssertEqual(third.workspace.eventJournal.map(\.kind), [
      AgentTaskEventKinds.progress,
      AgentTaskEventKinds.progress,
      AgentTaskEventKinds.progress
    ])
    XCTAssertEqual(third.workspace.eventJournal.map(\.message), [
      "galaxyssi.workspace.file.read.text",
      "Reading file",
      "galaxyssi.workspace.file.read.text"
    ])
    XCTAssertEqual(third.workspace.eventJournal.map(\.payloadJson), [
      #"{"stage":"tool.started"}"#,
      #"{"stage":"tool.progress"}"#,
      #"{"stage":"tool.finished"}"#
    ])
    XCTAssertEqual(third.workspace.eventJournal.map(\.timestampMillis), [1_200, 1_250, 1_300])
    XCTAssertEqual(third.workspace.eventSequence, 3)
  }

  func testRecordActivityThrottlesDuplicateHeartbeatWithoutUnresolvedStall() {
    let active = workspace(
      status: .running,
      events: [event(1, AgentTaskEventKinds.heartbeat, 1_000, message: "running")]
    )
    let livenessPolicy = AgentTaskLivenessPolicy(
      queuedWarningMillis: 10,
      queuedTimeoutMillis: 20,
      runningWarningMillis: 100,
      runningTimeoutMillis: 200,
      waitingResponseWarningMillis: 300,
      waitingResponseTimeoutMillis: 400,
      watchdogIntervalMillis: 60_000,
      heartbeatWriteThrottleMillis: 50
    )

    let reduction = AgentTaskLivenessWorkspaceReducer.recordActivity(
      workspace: active,
      eventKind: AgentTaskEventKinds.heartbeat,
      stage: "running",
      policy: livenessPolicy,
      observedAtMillis: 1_020
    )

    XCTAssertFalse(reduction.changed)
    XCTAssertEqual(reduction.workspace, active)
    XCTAssertNil(reduction.signal)
  }

  func testSweepRequestsAssessmentAndYieldsExecutionWithoutFailingWorkspace() {
    let workspace = self.workspace(
      status: .running,
      events: [event(1, AgentTaskEventKinds.running, 1_000, message: "running")]
    )

    let reduction = AgentTaskLivenessWorkspaceReducer.sweep(
      workspace: workspace,
      policy: policy(),
      nowMillis: 1_200
    )

    XCTAssertTrue(reduction.changed)
    XCTAssertEqual(reduction.workspace.status, .running)
    XCTAssertEqual(reduction.workspace.eventSequence, 2)
    XCTAssertEqual(reduction.workspace.eventJournal.last?.kind, AgentTaskEventKinds.livenessAssessmentRequested)
    XCTAssertEqual(reduction.workspace.eventJournal.last?.message, "running_progress_assessment_due")
    XCTAssertEqual(
      reduction.workspace.eventJournal.last?.payloadJson,
      #"{"decision_owner":"model","idle_ms":200,"lifetime_ms":200}"#
    )
    XCTAssertEqual(reduction.signal?.kind, .assessmentRequired)
    XCTAssertEqual(reduction.signal?.workspace.status, .running)
    XCTAssertFalse(reduction.cancelExecutionReason.isEmpty)
    XCTAssertTrue(policy().hasPendingAssessment(workspace: reduction.workspace))
  }

  func testReducerIgnoresTerminalAndCancelledWorkspaces() {
    let terminal = AgentTaskLivenessWorkspaceReducer.apply(
      decision: AgentTaskLivenessDecision(state: .assessmentRequired, reason: "timeout", idleMillis: 1, lifetimeMillis: 1),
      to: workspace(status: .completed),
      observedAtMillis: 2_000
    )
    let cancelled = AgentTaskLivenessWorkspaceReducer.recordActivity(
      workspace: workspace(status: .running, cancellationRequested: true),
      eventKind: AgentTaskEventKinds.progress,
      stage: "running",
      observedAtMillis: 2_000
    )

    XCTAssertFalse(terminal.changed)
    XCTAssertEqual(terminal.workspace.status, .completed)
    XCTAssertNil(terminal.signal)
    XCTAssertFalse(cancelled.changed)
    XCTAssertNil(cancelled.signal)
  }

  func testReducerPrunesEventJournalAndUsesAndroidWireNames() throws {
    let manyEvents = (1...105).map {
      event(Int64($0), AgentTaskEventKinds.progress, Int64($0), message: "event-\($0)")
    }
    let reduction = AgentTaskLivenessWorkspaceReducer.apply(
      decision: AgentTaskLivenessDecision(state: .stalled, reason: "manual_stall", idleMillis: 10, lifetimeMillis: 20),
      to: workspace(status: .running, events: manyEvents),
      observedAtMillis: 2_000
    )
    let encoded = String(decoding: try JSONEncoder().encode(reduction), as: UTF8.self)

    XCTAssertEqual(reduction.workspace.eventJournal.count, 100)
    XCTAssertEqual(reduction.workspace.eventJournal.first?.sequence, 7)
    XCTAssertTrue(encoded.contains(#""cancel_execution_reason":""#))
    XCTAssertTrue(encoded.contains(#""observed_at_millis":2000"#))
    XCTAssertTrue(encoded.contains(#""event_journal":["#))
  }

  private func policy() -> AgentTaskLivenessPolicy {
    AgentTaskLivenessPolicy(
      queuedWarningMillis: 10,
      queuedTimeoutMillis: 20,
      runningWarningMillis: 100,
      runningTimeoutMillis: 200,
      waitingResponseWarningMillis: 300,
      waitingResponseTimeoutMillis: 400,
      absoluteTimeoutMillis: 1_000,
      watchdogIntervalMillis: 60_000,
      heartbeatWriteThrottleMillis: 0
    )
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
