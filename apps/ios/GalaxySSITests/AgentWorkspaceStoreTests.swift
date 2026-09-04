import XCTest
@testable import GalaxySSI

final class AgentWorkspaceStoreTests: XCTestCase {
  func testMutationsAdvanceRevisionAndRejectStaleWriters() throws {
    var now: Int64 = 1_000
    let store = InMemoryAgentWorkspaceStore(clock: { now })
    let created = try store.upsert(workspace(status: .running))

    XCTAssertEqual(created.revision, 1)
    XCTAssertEqual(created.createdAtMillis, now)
    XCTAssertEqual(created.updatedAtMillis, now)

    now = 1_100
    let withEvent = try XCTUnwrap(store.appendEvent(
      workspaceId: created.workspaceId,
      kind: "tool_started",
      payloadJson: #"{"tool":"shell"}"#,
      expectedRevision: created.revision
    ))
    XCTAssertEqual(withEvent.revision, 2)
    XCTAssertEqual(withEvent.eventSequence, 1)
    XCTAssertEqual(withEvent.eventJournal.single?.sequence, 1)

    XCTAssertThrowsError(try store.appendEvent(
      workspaceId: created.workspaceId,
      kind: "stale",
      expectedRevision: created.revision
    )) { error in
      XCTAssertTrue(error is AgentWorkspaceRevisionConflictError)
    }

    now = 1_200
    let checkpointed = try XCTUnwrap(store.checkpoint(
      workspaceId: created.workspaceId,
      checkpointId: "checkpoint-1",
      planSnapshot: "1. Inspect\n2. Execute",
      stateJson: #"{"cursor":2}"#,
      expectedRevision: withEvent.revision
    ))
    XCTAssertEqual(checkpointed.revision, 3)
    XCTAssertEqual(checkpointed.eventSequence, 1)
    XCTAssertEqual(checkpointed.checkpoints.single?.eventSequence, 1)
    XCTAssertEqual(checkpointed.currentPlanSnapshot, "1. Inspect\n2. Execute")
    XCTAssertEqual(store.recoverable(), [checkpointed])

    now = 1_300
    let cancelled = try XCTUnwrap(store.requestCancel(
      created.workspaceId,
      expectedRevision: checkpointed.revision
    ))
    XCTAssertTrue(cancelled.cancellationRequested)
    XCTAssertEqual(cancelled.revision, 4)
    XCTAssertTrue(store.recoverable().isEmpty)
  }

  func testEventJournalIsBoundedWhileSequenceRemainsMonotonic() throws {
    let store = InMemoryAgentWorkspaceStore(clock: { 10 })
    var current = try store.upsert(workspace())
    let appendedCount = AgentWorkspaceBoundsPolicy.maxEvents + 7

    for index in 0..<appendedCount {
      current = try XCTUnwrap(store.appendEvent(
        workspaceId: current.workspaceId,
        kind: "progress",
        message: "event-\(index)",
        expectedRevision: current.revision,
        timestampMillis: 20 + Int64(index)
      ))
    }

    XCTAssertEqual(current.eventSequence, Int64(appendedCount))
    XCTAssertEqual(current.eventJournal.count, AgentWorkspaceBoundsPolicy.maxEvents)
    XCTAssertEqual(current.eventJournal.first?.sequence, 8)
    XCTAssertEqual(current.eventJournal.last?.sequence, Int64(appendedCount))
  }

  func testDeterministicCodecRoundTripsEveryWorkspaceRecordType() throws {
    let source = workspace(
      status: .waitingConfirmation,
      goal: "Build and verify the project",
      parentRunId: "parent-run",
      agentId: "codex",
      deviceId: "desktop-1",
      remoteRunId: "remote-run-1",
      deliveryMode: AgentDeliveryMode.respond.rawValue,
      currentPlanSnapshot: "Plan \"A\"\nthen B",
      resultJson: #"{"status":"waiting"}"#,
      errorMessage: "approval required",
      permissionGrantIds: ["grant-1"],
      permissionScopes: ["filesystem.write"],
      handoffIds: ["handoff-1"],
      lastRemoteEventSequence: 14,
      eventSequence: 1,
      eventJournal: [
        AgentWorkspaceEvent(sequence: 1, kind: "tool_result", message: "done", payloadJson: #"{"ok":true}"#, timestampMillis: 200)
      ],
      toolCalls: [
        AgentWorkspaceToolCallRecord(
          id: "call-1",
          toolName: "shell",
          status: .succeeded,
          argumentsJson: #"{"cmd":"pwd"}"#,
          resultJson: #"{"exit":0}"#,
          startedAtMillis: 150,
          completedAtMillis: 180
        )
      ],
      checkpoints: [
        AgentWorkspaceCheckpoint(id: "cp-1", eventSequence: 1, planSnapshot: "Plan A", stateJson: #"{"step":1}"#, createdAtMillis: 210)
      ],
      artifacts: [
        AgentWorkspaceArtifactReference(
          id: "artifact-1",
          uri: "content://galaxyssi/result.txt",
          name: "result.txt",
          mimeType: "text/plain",
          metadataJson: #"{"bytes":12}"#,
          createdAtMillis: 220
        )
      ],
      createdAtMillis: 100,
      updatedAtMillis: 220,
      revision: 9
    )

    let encoded = try AgentWorkspaceJsonCodec.encode(source)
    let decoded = try XCTUnwrap(AgentWorkspaceJsonCodec.decode(encoded))

    XCTAssertEqual(source, decoded)
    XCTAssertEqual(encoded, try AgentWorkspaceJsonCodec.encode(decoded))
    XCTAssertTrue(encoded.hasPrefix(#"{"version":2,"workspace_id":"#))
    XCTAssertTrue(encoded.contains(#""timestamp":200"#))
    XCTAssertFalse(encoded.contains("timestamp_millis"))
    XCTAssertNil(AgentWorkspaceJsonCodec.decode("{not-json}"))
  }

  func testProcessRecreationRestoresCompleteRunExecutionContext() throws {
    let first = InMemoryAgentWorkspaceStore(clock: { 1_000 })
    let created = try first.upsert(workspace(
      workspaceId: "run-1",
      status: .waitingResponse,
      goal: "Inspect, modify, and verify the project",
      parentRunId: "run-parent",
      agentId: "codex",
      deviceId: "desktop-a",
      remoteRunId: "remote-42",
      currentPlanSnapshot: #"[{"step":1}]"#,
      resultJson: #"{"partial":true}"#,
      errorMessage: "remote response pending",
      permissionGrantIds: ["grant-files"],
      permissionScopes: ["filesystem.project.write"],
      handoffIds: ["handoff-codex"],
      lastRemoteEventSequence: 27,
      eventSequence: 1,
      eventJournal: [AgentWorkspaceEvent(sequence: 1, kind: "remote.progress", message: "working", payloadJson: "{}", timestampMillis: 900)],
      toolCalls: [
        AgentWorkspaceToolCallRecord(
          id: "tool-1",
          toolName: "shell",
          status: .running,
          argumentsJson: #"{"cmd":"gradle test"}"#,
          startedAtMillis: 800
        )
      ],
      checkpoints: [
        AgentWorkspaceCheckpoint(
          id: "checkpoint-27",
          eventSequence: 1,
          planSnapshot: #"[{"step":1}]"#,
          stateJson: #"{"cursor":27,"permission_wait":true}"#,
          createdAtMillis: 950
        )
      ],
      artifacts: [
        AgentWorkspaceArtifactReference(
          id: "artifact-1",
          uri: "content://galaxyssi/patch.diff",
          name: "patch.diff",
          createdAtMillis: 920
        )
      ]
    ))

    let recreated = InMemoryAgentWorkspaceStore(serialized: first.serializedSnapshot(), clock: { 2_000 })
    let restored = try XCTUnwrap(recreated.find(created.workspaceId))

    XCTAssertEqual(created, restored)
    XCTAssertEqual(restored.goal, "Inspect, modify, and verify the project")
    XCTAssertEqual(restored.permissionGrantIds, ["grant-files"])
    XCTAssertEqual(restored.lastRemoteEventSequence, 27)
    XCTAssertEqual(restored.toolCalls.single?.status, .running)
    XCTAssertEqual(restored.checkpoints.single?.id, "checkpoint-27")
    XCTAssertEqual(restored.handoffIds.single, "handoff-codex")
  }

  func testListFindDeleteClearAndRecoverableUseWorkspaceIdentity() throws {
    var now: Int64 = 100
    let store = InMemoryAgentWorkspaceStore(clock: { now })
    let active = try store.upsert(workspace(workspaceId: "active", status: .paused))
    now = 200
    let complete = try store.upsert(workspace(workspaceId: "complete", status: .completed))

    XCTAssertEqual(store.list(), [complete, active])
    XCTAssertEqual(store.find(active.key), Optional(active))
    XCTAssertNil(store.find(AgentWorkspaceKey(
      workspaceId: active.workspaceId,
      sessionId: active.sessionId,
      conversationId: active.conversationId,
      taskId: "different"
    )))
    XCTAssertEqual(store.recoverable(), [active])
    XCTAssertTrue(try store.delete(complete.workspaceId))
    XCTAssertFalse(try store.delete(complete.workspaceId))
    XCTAssertNotNil(store.find(active.workspaceId))

    store.clear()
    XCTAssertTrue(store.list().isEmpty)
    XCTAssertEqual(store.serializedSnapshot(), AgentWorkspaceJsonCodec.emptyDocument())
  }

  private func workspace(
    workspaceId: String = "workspace-1",
    status: AgentWorkspaceStatus = .created,
    goal: String = "",
    parentRunId: String = "",
    agentId: String = "",
    deviceId: String = "",
    remoteRunId: String = "",
    deliveryMode: String = AgentDeliveryMode.respond.rawValue,
    currentPlanSnapshot: String = "",
    resultJson: String = "{}",
    errorMessage: String = "",
    permissionGrantIds: [String] = [],
    permissionScopes: [String] = [],
    handoffIds: [String] = [],
    lastRemoteEventSequence: Int64 = 0,
    eventSequence: Int64 = 0,
    eventJournal: [AgentWorkspaceEvent] = [],
    toolCalls: [AgentWorkspaceToolCallRecord] = [],
    checkpoints: [AgentWorkspaceCheckpoint] = [],
    artifacts: [AgentWorkspaceArtifactReference] = [],
    createdAtMillis: Int64 = 0,
    updatedAtMillis: Int64 = 0,
    revision: Int64 = 0
  ) -> AgentWorkspace {
    AgentWorkspace(
      workspaceId: workspaceId,
      sessionId: "session-1",
      conversationId: "conversation-1",
      taskId: "task-1",
      goal: goal,
      parentRunId: parentRunId,
      agentId: agentId,
      deviceId: deviceId,
      remoteRunId: remoteRunId,
      deliveryMode: deliveryMode,
      status: status,
      currentPlanSnapshot: currentPlanSnapshot,
      resultJson: resultJson,
      errorMessage: errorMessage,
      permissionGrantIds: permissionGrantIds,
      permissionScopes: permissionScopes,
      handoffIds: handoffIds,
      lastRemoteEventSequence: lastRemoteEventSequence,
      eventSequence: eventSequence,
      eventJournal: eventJournal,
      toolCalls: toolCalls,
      checkpoints: checkpoints,
      artifacts: artifacts,
      createdAtMillis: createdAtMillis,
      updatedAtMillis: updatedAtMillis,
      revision: revision
    )
  }
}

private extension Array {
  var single: Element? {
    count == 1 ? first : nil
  }
}
