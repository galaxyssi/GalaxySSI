import XCTest
@testable import GalaxySSI

final class AgentTaskLivenessSignalActionPolicyTests: XCTestCase {
  func testStalledWaitingResponseRemoteAgentPlansReconciliation() {
    let signal = AgentTaskLivenessSignal(
      kind: .stalled,
      workspace: workspace(status: .waitingResponse),
      reason: "waiting_response_progress_stalled",
      observedAtMillis: 2_000
    )

    let plan = AgentTaskLivenessSignalActionPolicy.plan(
      for: signal,
      existingEntries: [],
      agentId: "codex",
      stalledText: "No progress reported"
    )

    XCTAssertEqual(plan.transcriptOperations.count, 1)
    XCTAssertEqual(plan.transcriptOperations.first?.kind, .upsert)
    XCTAssertEqual(plan.transcriptOperations.first?.dedupeKey, "task-watchdog:turn")
    XCTAssertEqual(plan.transcriptOperations.first?.text, "No progress reported")
    XCTAssertTrue(plan.consumePendingConnectorResponses)
    XCTAssertTrue(plan.requestRecoverableRunReconciliation)
    XCTAssertEqual(plan.reconciliationReason, "stall")
    XCTAssertTrue(plan.forceTimeoutRunIds.isEmpty)
  }

  func testStalledMobileAgentConsumesPendingResponsesWithoutRemoteReconciliation() {
    let signal = AgentTaskLivenessSignal(
      kind: .stalled,
      workspace: workspace(status: .waitingResponse),
      reason: "waiting_response_progress_stalled",
      observedAtMillis: 2_000
    )

    let plan = AgentTaskLivenessSignalActionPolicy.plan(
      for: signal,
      existingEntries: [],
      agentId: "galaxyssi-mobile"
    )

    XCTAssertTrue(plan.consumePendingConnectorResponses)
    XCTAssertFalse(plan.requestRecoverableRunReconciliation)
    XCTAssertEqual(plan.reconciliationReason, "")
  }

  func testRecoveredOnlyClearsWatchdogTranscript() {
    let signal = AgentTaskLivenessSignal(
      kind: .recovered,
      workspace: workspace(status: .running),
      reason: "progress_resumed",
      observedAtMillis: 2_500
    )

    let plan = AgentTaskLivenessSignalActionPolicy.plan(
      for: signal,
      existingEntries: []
    )

    XCTAssertEqual(plan.transcriptOperations.map(\.kind), [.delete, .delete])
    XCTAssertFalse(plan.consumePendingConnectorResponses)
    XCTAssertFalse(plan.requestRecoverableRunReconciliation)
    XCTAssertTrue(plan.cancelConnectorTimeoutSourceMessageIds.isEmpty)
    XCTAssertTrue(plan.forceTimeoutRunIds.isEmpty)
  }

  func testAssessmentPreservesActiveRunsAndRequestsRecovery() {
    let signal = AgentTaskLivenessSignal(
      kind: .assessmentRequired,
      workspace: workspace(status: .running),
      reason: "running_progress_assessment_due",
      observedAtMillis: 3_000
    )
    let activeRuns = [
      AgentTaskLivenessActiveRun(runId: "run-a", workspaceId: "workspace", sourceMessageId: 71, agentId: "codex"),
      AgentTaskLivenessActiveRun(runId: "run-a", workspaceId: "workspace", sourceMessageId: 71, agentId: "codex"),
      AgentTaskLivenessActiveRun(runId: "run-b", workspaceId: "other", sourceMessageId: 72, agentId: "codex"),
      AgentTaskLivenessActiveRun(runId: "run-c", workspaceId: "workspace", sourceMessageId: 73, agentId: "hermes")
    ]

    let plan = AgentTaskLivenessSignalActionPolicy.plan(
      for: signal,
      existingEntries: [],
      activeRuns: activeRuns,
      timedOutText: "Checking task liveness"
    )

    XCTAssertEqual(plan.transcriptOperations.map(\.kind), [.delete, .upsert])
    XCTAssertEqual(plan.transcriptOperations.last?.role, .process)
    XCTAssertEqual(plan.transcriptOperations.last?.dedupeKey, "task-liveness-assessment:turn")
    XCTAssertTrue(plan.cancelConnectorTimeoutSourceMessageIds.isEmpty)
    XCTAssertTrue(plan.removeActiveRunIds.isEmpty)
    XCTAssertTrue(plan.forceTimeoutRunIds.isEmpty)
    XCTAssertTrue(plan.timeoutMessage.isEmpty)
    XCTAssertTrue(plan.requestRecoverableRunReconciliation)
    XCTAssertEqual(plan.reconciliationReason, "liveness_assessment")
  }

  func testTerminalReplySuppressesRuntimeActionsAndOnlyClearsTranscriptRows() {
    let signal = AgentTaskLivenessSignal(
      kind: .assessmentRequired,
      workspace: workspace(status: .running),
      reason: "running_progress_assessment_due",
      observedAtMillis: 3_000
    )
    let terminal = AgentTranscriptEntry(
      id: "terminal",
      role: .assistant,
      text: "Done",
      timestampMillis: 2_500,
      dedupeKey: "assistant-final:turn",
      conversationId: "conversation",
      turnId: "turn",
      taskId: "turn"
    )

    let plan = AgentTaskLivenessSignalActionPolicy.plan(
      for: signal,
      existingEntries: [terminal],
      activeRuns: [
        AgentTaskLivenessActiveRun(runId: "run-a", workspaceId: "workspace", sourceMessageId: 71, agentId: "codex")
      ],
      agentId: "codex"
    )

    XCTAssertEqual(plan.transcriptOperations.map(\.kind), [.delete, .delete, .delete])
    XCTAssertFalse(plan.consumePendingConnectorResponses)
    XCTAssertFalse(plan.requestRecoverableRunReconciliation)
    XCTAssertTrue(plan.cancelConnectorTimeoutSourceMessageIds.isEmpty)
    XCTAssertTrue(plan.removeActiveRunIds.isEmpty)
    XCTAssertTrue(plan.forceTimeoutRunIds.isEmpty)
  }

  func testActionPlanUsesAndroidWireNames() throws {
    let plan = AgentTaskLivenessSignalActionPlan(
      transcriptOperations: [
        AgentTaskLivenessTranscriptOperation(
          kind: .delete,
          dedupeKey: "task-watchdog:turn",
          conversationId: "conversation",
          turnId: "turn",
          taskId: "turn"
        )
      ],
      consumePendingConnectorResponses: true,
      requestRecoverableRunReconciliation: true,
      reconciliationReason: "stall",
      cancelConnectorTimeoutSourceMessageIds: [71],
      removeActiveRunIds: ["run-a"],
      forceTimeoutRunIds: ["run-a"],
      timeoutMessage: "Task watchdog timed out"
    )
    let activeRun = AgentTaskLivenessActiveRun(
      runId: "run-a",
      workspaceId: "workspace",
      sourceMessageId: 71,
      agentId: "codex"
    )
    let encodedPlan = String(decoding: try JSONEncoder().encode(plan), as: UTF8.self)
    let encodedRun = String(decoding: try JSONEncoder().encode(activeRun), as: UTF8.self)

    XCTAssertTrue(encodedPlan.contains(#""transcript_operations":["#))
    XCTAssertTrue(encodedPlan.contains(#""consume_pending_connector_responses":true"#))
    XCTAssertTrue(encodedPlan.contains(#""request_recoverable_run_reconciliation":true"#))
    XCTAssertTrue(encodedPlan.contains(#""cancel_connector_timeout_source_message_ids":[71]"#))
    XCTAssertTrue(encodedPlan.contains(#""force_timeout_run_ids":["run-a"]"#))
    XCTAssertTrue(encodedRun.contains(#""source_message_id":71"#))
    XCTAssertTrue(encodedRun.contains(#""agent_id":"codex""#))
  }

  private func workspace(status: AgentWorkspaceStatus) -> AgentWorkspace {
    AgentWorkspace(
      workspaceId: "workspace",
      sessionId: "session",
      conversationId: "conversation",
      taskId: "turn",
      status: status,
      eventSequence: 0,
      eventJournal: [],
      createdAtMillis: 1_000,
      updatedAtMillis: 1_000
    )
  }
}
