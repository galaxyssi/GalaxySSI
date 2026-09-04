import XCTest
@testable import GalaxySSI

final class AgentWorkspaceExecutionSnapshotReducerTests: XCTestCase {
  func testSnapshotAppendsEventAndMergesRuntimeMetadata() {
    let current = workspace(
      status: .running,
      currentPlanSnapshot: #"{"old":true}"#,
      resultJson: #"{"old":true}"#,
      errorMessage: "still running",
      permissionGrantIds: ["grant-a"],
      permissionScopes: ["contacts.read"],
      handoffIds: ["handoff:71"],
      agentId: "codex",
      deviceId: "desktop",
      remoteRunId: "71",
      lastRemoteEventSequence: 2,
      toolCalls: [
        toolCall("call-a", .running),
        toolCall("call-b", .succeeded)
      ],
      artifacts: [artifact("artifact-a")],
      events: [event(1, AgentTaskEventKinds.running, 1_000, message: "running")]
    )
    let snapshot = AgentWorkspaceExecutionSnapshot(
      status: .waitingResponse,
      planSnapshot: #"{"new":true}"#,
      resultJson: #"{"waiting":true}"#,
      errorMessage: "waiting",
      toolCalls: [
        toolCall("call-a", .succeeded),
        toolCall("call-c", .pending)
      ],
      artifacts: [
        artifact("artifact-a"),
        artifact("artifact-b")
      ],
      permissionGrantIds: ["grant-a", "grant-b"],
      permissionScopes: [" contacts.read ", "calendar.write"],
      handoffIds: ["handoff:71", "handoff:72"],
      agentId: "hermes",
      deviceId: "desktop-2",
      remoteRunId: "72",
      lastRemoteEventSequence: 5
    )

    let reduction = AgentWorkspaceExecutionSnapshotReducer.apply(
      snapshot: snapshot,
      to: current,
      observedAtMillis: 2_000
    )

    XCTAssertTrue(reduction.changed)
    XCTAssertTrue(reduction.statusChanged)
    XCTAssertEqual(reduction.workspace.status, .waitingResponse)
    XCTAssertEqual(reduction.workspace.eventSequence, 2)
    XCTAssertEqual(reduction.workspace.eventJournal.last?.kind, AgentTaskEventKinds.snapshot)
    XCTAssertEqual(reduction.workspace.eventJournal.last?.message, "waiting_response")
    XCTAssertEqual(reduction.workspace.currentPlanSnapshot, #"{"new":true}"#)
    XCTAssertEqual(reduction.workspace.resultJson, #"{"waiting":true}"#)
    XCTAssertEqual(reduction.workspace.errorMessage, "waiting")
    XCTAssertEqual(reduction.workspace.toolCalls.map(\.id), ["call-a", "call-b", "call-c"])
    XCTAssertEqual(reduction.workspace.toolCalls.first?.status, .running)
    XCTAssertEqual(reduction.workspace.artifacts.map(\.id), ["artifact-a", "artifact-b"])
    XCTAssertEqual(reduction.workspace.permissionGrantIds, ["grant-a", "grant-b"])
    XCTAssertEqual(reduction.workspace.permissionScopes, ["contacts.read", "calendar.write"])
    XCTAssertEqual(reduction.workspace.handoffIds, ["handoff:71", "handoff:72"])
    XCTAssertEqual(reduction.workspace.agentId, "hermes")
    XCTAssertEqual(reduction.workspace.deviceId, "desktop-2")
    XCTAssertEqual(reduction.workspace.remoteRunId, "72")
    XCTAssertEqual(reduction.workspace.lastRemoteEventSequence, 5)
  }

  func testSnapshotPreservesCurrentValuesWhenIncomingOptionalFieldsAreBlank() {
    let current = workspace(
      status: .running,
      currentPlanSnapshot: #"{"old":true}"#,
      resultJson: #"{"ok":true}"#,
      errorMessage: "old error",
      agentId: "codex",
      deviceId: "desktop",
      remoteRunId: "71",
      lastRemoteEventSequence: 7
    )
    let snapshot = AgentWorkspaceExecutionSnapshot(
      status: nil,
      planSnapshot: "",
      resultJson: "",
      errorMessage: "",
      agentId: "",
      deviceId: "",
      remoteRunId: "",
      lastRemoteEventSequence: 3
    )

    let reduction = AgentWorkspaceExecutionSnapshotReducer.apply(
      snapshot: snapshot,
      to: current,
      observedAtMillis: 2_000
    )

    XCTAssertTrue(reduction.changed)
    XCTAssertFalse(reduction.statusChanged)
    XCTAssertEqual(reduction.workspace.status, .running)
    XCTAssertEqual(reduction.workspace.currentPlanSnapshot, #"{"old":true}"#)
    XCTAssertEqual(reduction.workspace.resultJson, "{}")
    XCTAssertEqual(reduction.workspace.errorMessage, "old error")
    XCTAssertEqual(reduction.workspace.agentId, "codex")
    XCTAssertEqual(reduction.workspace.deviceId, "desktop")
    XCTAssertEqual(reduction.workspace.remoteRunId, "71")
    XCTAssertEqual(reduction.workspace.lastRemoteEventSequence, 7)
    XCTAssertEqual(reduction.workspace.eventJournal.last?.message, "running")
  }

  func testSnapshotIgnoresIncompatibleTerminalStatusChange() {
    let completed = workspace(status: .completed)
    let snapshot = AgentWorkspaceExecutionSnapshot(status: .running)

    let reduction = AgentWorkspaceExecutionSnapshotReducer.apply(
      snapshot: snapshot,
      to: completed,
      observedAtMillis: 2_000
    )

    XCTAssertFalse(reduction.changed)
    XCTAssertFalse(reduction.statusChanged)
    XCTAssertEqual(reduction.workspace, completed)
  }

  func testSnapshotPrunesMergedCollectionsAndUsesAndroidWireNames() throws {
    let currentCalls = (1...55).map { toolCall("call-\($0)", .succeeded) }
    let currentArtifacts = (1...55).map { artifact("artifact-\($0)") }
    let current = workspace(
      status: .running,
      permissionGrantIds: (1...130).map { "grant-\($0)" },
      permissionScopes: (1...130).map { "scope-\($0)" },
      handoffIds: (1...130).map { "handoff:\($0)" },
      toolCalls: currentCalls,
      artifacts: currentArtifacts,
      events: (1...105).map { event(Int64($0), AgentTaskEventKinds.progress, Int64($0)) }
    )
    let snapshot = AgentWorkspaceExecutionSnapshot(
      status: .running,
      toolCalls: [toolCall("call-56", .pending)],
      artifacts: [artifact("artifact-56")],
      permissionGrantIds: ["grant-131"],
      permissionScopes: ["scope-131"],
      handoffIds: ["handoff:131"]
    )

    let reduction = AgentWorkspaceExecutionSnapshotReducer.apply(
      snapshot: snapshot,
      to: current,
      observedAtMillis: 2_000
    )
    let encoded = String(decoding: try JSONEncoder().encode(reduction), as: UTF8.self)

    XCTAssertEqual(reduction.workspace.eventJournal.count, 100)
    XCTAssertEqual(reduction.workspace.eventJournal.first?.sequence, 7)
    XCTAssertEqual(reduction.workspace.toolCalls.count, 50)
    XCTAssertEqual(reduction.workspace.toolCalls.first?.id, "call-7")
    XCTAssertEqual(reduction.workspace.artifacts.count, 50)
    XCTAssertEqual(reduction.workspace.artifacts.first?.id, "artifact-7")
    XCTAssertEqual(reduction.workspace.permissionGrantIds.count, 128)
    XCTAssertEqual(reduction.workspace.permissionGrantIds.first, "grant-4")
    XCTAssertEqual(reduction.workspace.handoffIds.last, "handoff:131")
    XCTAssertTrue(encoded.contains(#""status_changed":false"#))
    XCTAssertTrue(encoded.contains(#""task.execution_snapshot""#))
    XCTAssertTrue(encoded.contains(#""tool_calls":["#))
  }

  private func workspace(
    status: AgentWorkspaceStatus,
    currentPlanSnapshot: String = "",
    resultJson: String = "{}",
    errorMessage: String = "",
    permissionGrantIds: [String] = [],
    permissionScopes: [String] = [],
    handoffIds: [String] = [],
    agentId: String = "",
    deviceId: String = "",
    remoteRunId: String = "",
    lastRemoteEventSequence: Int64 = 0,
    toolCalls: [AgentWorkspaceToolCallRecord] = [],
    artifacts: [AgentWorkspaceArtifactReference] = [],
    events: [AgentWorkspaceEvent] = []
  ) -> AgentWorkspace {
    AgentWorkspace(
      workspaceId: "workspace",
      sessionId: "session",
      conversationId: "conversation",
      taskId: "task",
      agentId: agentId,
      deviceId: deviceId,
      remoteRunId: remoteRunId,
      status: status,
      currentPlanSnapshot: currentPlanSnapshot,
      resultJson: resultJson,
      errorMessage: errorMessage,
      permissionGrantIds: permissionGrantIds,
      permissionScopes: permissionScopes,
      handoffIds: handoffIds,
      lastRemoteEventSequence: lastRemoteEventSequence,
      eventSequence: events.map(\.sequence).max() ?? 0,
      eventJournal: events,
      toolCalls: toolCalls,
      artifacts: artifacts,
      createdAtMillis: 1_000,
      updatedAtMillis: events.map(\.timestampMillis).max() ?? 1_000
    )
  }

  private func toolCall(
    _ id: String,
    _ status: AgentToolCallStatus
  ) -> AgentWorkspaceToolCallRecord {
    AgentWorkspaceToolCallRecord(
      id: id,
      toolName: "tool.\(id)",
      status: status,
      startedAtMillis: 1_000
    )
  }

  private func artifact(_ id: String) -> AgentWorkspaceArtifactReference {
    AgentWorkspaceArtifactReference(
      id: id,
      uri: "app://\(id)",
      createdAtMillis: 1_000
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
