import XCTest
@testable import GalaxySSI

final class AgentTaskLivenessTranscriptPolicyTests: XCTestCase {
  func testPolicyUpsertsStalledWatchdogTranscript() {
    let signal = AgentTaskLivenessSignal(
      kind: .stalled,
      workspace: workspace(status: .running),
      reason: "running_progress_stalled",
      observedAtMillis: 2_000
    )

    let operations = AgentTaskLivenessTranscriptPolicy.operations(
      for: signal,
      existingEntries: [],
      stalledText: "No progress reported"
    )

    XCTAssertEqual(operations.count, 1)
    XCTAssertEqual(operations.first?.kind, .upsert)
    XCTAssertEqual(operations.first?.role, .process)
    XCTAssertEqual(operations.first?.text, "No progress reported")
    XCTAssertEqual(operations.first?.dedupeKey, "task-watchdog:turn")
    XCTAssertEqual(operations.first?.conversationId, "conversation")
    XCTAssertEqual(operations.first?.turnId, "turn")
    XCTAssertEqual(operations.first?.taskId, "turn")
    XCTAssertEqual(operations.first?.timestampMillis, 2_000)
  }

  func testPolicyClearsAssessmentOnRecoveryAndUpsertsAssessmentStatus() {
    let recovered = AgentTaskLivenessSignal(
      kind: .recovered,
      workspace: workspace(status: .running),
      reason: "progress_resumed",
      observedAtMillis: 2_100
    )
    let assessment = AgentTaskLivenessSignal(
      kind: .assessmentRequired,
      workspace: workspace(status: .running),
      reason: "running_progress_assessment_due",
      observedAtMillis: 3_000
    )

    let recoveryOps = AgentTaskLivenessTranscriptPolicy.operations(for: recovered, existingEntries: [])
    let assessmentOps = AgentTaskLivenessTranscriptPolicy.operations(
      for: assessment,
      existingEntries: [],
      timedOutText: "Checking task liveness"
    )

    XCTAssertEqual(recoveryOps.map(\.kind), [.delete, .delete])
    XCTAssertEqual(recoveryOps.first?.dedupeKey, "task-watchdog:turn")
    XCTAssertEqual(recoveryOps.last?.dedupeKey, "task-liveness-assessment:turn")
    XCTAssertEqual(assessmentOps.map(\.kind), [.delete, .upsert])
    XCTAssertEqual(assessmentOps.first?.dedupeKey, "task-watchdog:turn")
    XCTAssertEqual(assessmentOps.last?.role, .process)
    XCTAssertEqual(assessmentOps.last?.text, "Checking task liveness")
    XCTAssertEqual(assessmentOps.last?.dedupeKey, "task-liveness-assessment:turn")
  }

  func testPolicyClearsWatchdogRowsWhenTerminalReplyAlreadyExists() {
    let signal = AgentTaskLivenessSignal(
      kind: .stalled,
      workspace: workspace(status: .running),
      reason: "running_progress_stalled",
      observedAtMillis: 2_000
    )
    let terminal = AgentTranscriptEntry(
      id: "terminal",
      role: .assistant,
      text: "Done",
      timestampMillis: 1_500,
      dedupeKey: "assistant-final:turn",
      conversationId: "conversation",
      turnId: "turn",
      taskId: "turn"
    )

    let operations = AgentTaskLivenessTranscriptPolicy.operations(
      for: signal,
      existingEntries: [terminal]
    )

    XCTAssertEqual(operations.map(\.kind), [.delete, .delete, .delete])
    XCTAssertEqual(
      operations.map(\.dedupeKey),
      ["task-watchdog:turn", "task-watchdog-timeout:turn", "task-liveness-assessment:turn"]
    )
  }

  func testPolicyUsesAndroidWireNames() throws {
    let operation = AgentTaskLivenessTranscriptOperation(
      kind: .append,
      role: .assistant,
      text: "Timed out",
      dedupeKey: "task-watchdog-timeout:turn",
      conversationId: "conversation",
      turnId: "turn",
      taskId: "turn",
      timestampMillis: 3_000
    )
    let encoded = String(decoding: try JSONEncoder().encode(operation), as: UTF8.self)

    XCTAssertTrue(encoded.contains(#""kind":"APPEND""#))
    XCTAssertTrue(encoded.contains(#""dedupe_key":"task-watchdog-timeout:turn""#))
    XCTAssertTrue(encoded.contains(#""conversation_id":"conversation""#))
    XCTAssertTrue(encoded.contains(#""timestamp_millis":3000"#))
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
