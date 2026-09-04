import XCTest
@testable import GalaxySSI

final class AgentWorkspaceCheckpointReducerTests: XCTestCase {
  func testCheckpointAppendsEventAndStoresSnapshot() {
    let current = workspace(
      currentPlanSnapshot: #"{"old":true}"#,
      events: [event(1, AgentTaskEventKinds.running, 1_000, message: "running")]
    )

    let reduction = AgentWorkspaceCheckpointReducer.checkpoint(
      workspace: current,
      checkpointId: " checkpoint-a ",
      planSnapshot: #"{"new":true}"#,
      stateJson: #"{"phase":"act"}"#,
      observedAtMillis: 2_000
    )

    XCTAssertTrue(reduction.changed)
    XCTAssertEqual(reduction.checkpoint?.id, "checkpoint-a")
    XCTAssertEqual(reduction.checkpoint?.eventSequence, 2)
    XCTAssertEqual(reduction.checkpoint?.planSnapshot, #"{"new":true}"#)
    XCTAssertEqual(reduction.checkpoint?.stateJson, #"{"phase":"act"}"#)
    XCTAssertEqual(reduction.checkpoint?.createdAtMillis, 2_000)
    XCTAssertEqual(reduction.workspace.currentPlanSnapshot, #"{"new":true}"#)
    XCTAssertEqual(reduction.workspace.eventSequence, 2)
    XCTAssertEqual(reduction.workspace.eventJournal.last?.kind, AgentTaskEventKinds.checkpoint)
    XCTAssertEqual(reduction.workspace.eventJournal.last?.message, "checkpoint-a")
    XCTAssertEqual(reduction.workspace.updatedAtMillis, 2_000)
  }

  func testCheckpointFallsBackToCurrentPlanSnapshot() {
    let current = workspace(currentPlanSnapshot: #"{"current":true}"#)

    let reduction = AgentWorkspaceCheckpointReducer.checkpoint(
      workspace: current,
      checkpointId: "checkpoint-a",
      planSnapshot: " ",
      stateJson: "{}",
      observedAtMillis: 2_000
    )

    XCTAssertEqual(reduction.checkpoint?.planSnapshot, #"{"current":true}"#)
    XCTAssertEqual(reduction.workspace.currentPlanSnapshot, #"{"current":true}"#)
  }

  func testCheckpointRejectsBlankId() {
    let current = workspace(currentPlanSnapshot: "{}")

    let reduction = AgentWorkspaceCheckpointReducer.checkpoint(
      workspace: current,
      checkpointId: " ",
      observedAtMillis: 2_000
    )

    XCTAssertFalse(reduction.changed)
    XCTAssertNil(reduction.checkpoint)
    XCTAssertEqual(reduction.workspace, current)
  }

  func testCheckpointReplacesSameIdAndPrunesToAndroidLimit() throws {
    let checkpoints = (1...10).map {
      AgentWorkspaceCheckpoint(
        id: "checkpoint-\($0)",
        eventSequence: Int64($0),
        planSnapshot: "{}",
        stateJson: "{}",
        createdAtMillis: Int64($0)
      )
    }
    let current = workspace(
      currentPlanSnapshot: "{}",
      checkpoints: checkpoints,
      events: (1...105).map { event(Int64($0), AgentTaskEventKinds.progress, Int64($0)) }
    )

    let replaced = AgentWorkspaceCheckpointReducer.checkpoint(
      workspace: current,
      checkpointId: "checkpoint-5",
      planSnapshot: #"{"replacement":true}"#,
      observedAtMillis: 2_000
    )
    let appended = AgentWorkspaceCheckpointReducer.checkpoint(
      workspace: replaced.workspace,
      checkpointId: "checkpoint-11",
      planSnapshot: #"{"new":true}"#,
      observedAtMillis: 2_100
    )
    let encoded = String(decoding: try JSONEncoder().encode(appended), as: UTF8.self)

    XCTAssertEqual(replaced.workspace.checkpoints.filter { $0.id == "checkpoint-5" }.count, 1)
    XCTAssertEqual(replaced.workspace.checkpoints.last?.id, "checkpoint-5")
    XCTAssertEqual(replaced.workspace.checkpoints.last?.planSnapshot, #"{"replacement":true}"#)
    XCTAssertEqual(appended.workspace.checkpoints.count, 10)
    XCTAssertEqual(appended.workspace.checkpoints.first?.id, "checkpoint-2")
    XCTAssertEqual(appended.workspace.checkpoints.last?.id, "checkpoint-11")
    XCTAssertEqual(appended.workspace.eventJournal.count, 100)
    XCTAssertEqual(appended.workspace.eventJournal.first?.sequence, 8)
    XCTAssertTrue(encoded.contains(#""checkpoint":{"#))
    XCTAssertTrue(encoded.contains(#""task.checkpoint""#))
    XCTAssertTrue(encoded.contains(#""event_sequence":107"#))
  }

  private func workspace(
    currentPlanSnapshot: String = "",
    checkpoints: [AgentWorkspaceCheckpoint] = [],
    events: [AgentWorkspaceEvent] = []
  ) -> AgentWorkspace {
    AgentWorkspace(
      workspaceId: "workspace",
      sessionId: "session",
      conversationId: "conversation",
      taskId: "task",
      status: .running,
      currentPlanSnapshot: currentPlanSnapshot,
      eventSequence: events.map(\.sequence).max() ?? checkpoints.map(\.eventSequence).max() ?? 0,
      eventJournal: events,
      checkpoints: checkpoints,
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
