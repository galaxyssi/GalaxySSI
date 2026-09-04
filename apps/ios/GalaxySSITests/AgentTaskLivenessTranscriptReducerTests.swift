import XCTest
@testable import GalaxySSI

final class AgentTaskLivenessTranscriptReducerTests: XCTestCase {
  func testReducerAppliesWatchdogStallUpsertAndReplacement() {
    let first = AgentTaskLivenessTranscriptOperation(
      kind: .upsert,
      role: .process,
      text: "No progress reported",
      dedupeKey: "task-watchdog:turn",
      conversationId: "conversation",
      turnId: "turn",
      taskId: "turn",
      timestampMillis: 2_000
    )
    let second = AgentTaskLivenessTranscriptOperation(
      kind: .upsert,
      role: .process,
      text: "Still no progress",
      dedupeKey: "task-watchdog:turn",
      conversationId: "conversation",
      turnId: "turn",
      taskId: "turn",
      timestampMillis: 3_000
    )
    var ids = ["watchdog-1", "watchdog-2"].makeIterator()

    let inserted = AgentTaskLivenessTranscriptReducer.apply([first], to: []) {
      ids.next() ?? UUID().uuidString
    }
    let replaced = AgentTaskLivenessTranscriptReducer.apply([second], to: inserted) {
      ids.next() ?? UUID().uuidString
    }

    XCTAssertEqual(inserted.count, 1)
    XCTAssertEqual(inserted.first?.id, "watchdog-1")
    XCTAssertEqual(inserted.first?.text, "No progress reported")
    XCTAssertEqual(replaced.count, 1)
    XCTAssertEqual(replaced.first?.id, "watchdog-2")
    XCTAssertEqual(replaced.first?.text, "Still no progress")
    XCTAssertEqual(replaced.first?.dedupeKey, "task-watchdog:turn")
  }

  func testReducerSkipsDuplicateAppendAndDeletesByConversationDedupe() {
    let existing = entry(
      id: "timeout-1",
      role: .assistant,
      text: "Timed out",
      dedupeKey: "task-watchdog-timeout:turn"
    )
    let duplicateAppend = AgentTaskLivenessTranscriptOperation(
      kind: .append,
      role: .assistant,
      text: "Timed out again",
      dedupeKey: "task-watchdog-timeout:turn",
      conversationId: "conversation",
      turnId: "turn",
      taskId: "turn",
      timestampMillis: 4_000
    )
    let delete = AgentTaskLivenessTranscriptOperation(
      kind: .delete,
      dedupeKey: "task-watchdog-timeout:turn",
      conversationId: "conversation",
      turnId: "turn",
      taskId: "turn"
    )

    let unchanged = AgentTaskLivenessTranscriptReducer.apply([duplicateAppend], to: [existing]) {
      "timeout-2"
    }
    let removed = AgentTaskLivenessTranscriptReducer.apply([delete], to: unchanged)

    XCTAssertEqual(unchanged, [existing])
    XCTAssertTrue(removed.isEmpty)
  }

  func testReducerAppliesPolicyTimeoutOperationsEndToEnd() {
    let warning = entry(
      id: "warning",
      role: .process,
      text: "No progress",
      dedupeKey: "task-watchdog:turn"
    )
    let workspace = AgentWorkspace(
      workspaceId: "workspace",
      sessionId: "session",
      conversationId: "conversation",
      taskId: "turn",
      status: .failed,
      eventSequence: 0,
      eventJournal: [],
      createdAtMillis: 1_000,
      updatedAtMillis: 1_000
    )
    let signal = AgentTaskLivenessSignal(
      kind: .timedOut,
      workspace: workspace,
      reason: "running_progress_timeout",
      observedAtMillis: 5_000
    )
    let operations = AgentTaskLivenessTranscriptPolicy.operations(
      for: signal,
      existingEntries: [warning],
      timedOutText: "Task watchdog timed out"
    )

    let reduced = AgentTaskLivenessTranscriptReducer.apply(operations, to: [warning]) {
      "timeout"
    }

    XCTAssertEqual(reduced.count, 1)
    XCTAssertEqual(reduced.first?.id, "timeout")
    XCTAssertEqual(reduced.first?.role, .assistant)
    XCTAssertEqual(reduced.first?.text, "Task watchdog timed out")
    XCTAssertEqual(reduced.first?.dedupeKey, "task-watchdog-timeout:turn")
    XCTAssertEqual(reduced.first?.timestampMillis, 5_000)
  }

  private func entry(
    id: String,
    role: AgentTranscriptRole,
    text: String,
    dedupeKey: String
  ) -> AgentTranscriptEntry {
    AgentTranscriptEntry(
      id: id,
      role: role,
      text: text,
      timestampMillis: 1_000,
      dedupeKey: dedupeKey,
      conversationId: "conversation",
      turnId: "turn",
      taskId: "turn"
    )
  }
}
