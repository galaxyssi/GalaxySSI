import XCTest
@testable import GalaxySSI

final class AgentWorkspaceBoundsPolicyTests: XCTestCase {
  func testNormalizeWorkspaceBoundsRuntimeMetadata() {
    let workspace = self.workspace(
      goal: String(repeating: "g", count: AgentWorkspaceBoundsPolicy.maxGoalCharacters + 10),
      parentRunId: String(repeating: "p", count: AgentWorkspaceBoundsPolicy.maxIdentifierCharacters + 10),
      deliveryMode: " ",
      currentPlanSnapshot: String(repeating: "p", count: AgentWorkspaceBoundsPolicy.maxPlanCharacters + 10),
      resultJson: "",
      errorMessage: String(repeating: "e", count: AgentWorkspaceBoundsPolicy.maxErrorMessageCharacters + 10),
      permissionGrantIds: [" grant-a ", "grant-a", String(repeating: "b", count: 200)],
      permissionScopes: ["scope-a", "scope-a", " "],
      handoffIds: ["handoff:1", "handoff:1", "handoff:2"],
      eventSequence: 1,
      events: [
        AgentWorkspaceEvent(sequence: 0, kind: "task.bad", timestampMillis: 1),
        AgentWorkspaceEvent(sequence: 1, kind: "task.running", timestampMillis: 1),
        AgentWorkspaceEvent(
          sequence: 2,
          kind: "task.progress",
          message: "newer",
          timestampMillis: 3
        ),
        AgentWorkspaceEvent(
          sequence: 3,
          kind: " \(String(repeating: "k", count: 90)) ",
          message: String(repeating: "m", count: 1_100),
          payloadJson: String(repeating: "p", count: 5_000),
          timestampMillis: 4
        )
      ],
      toolCalls: [
        toolCall("call-a", startedAtMillis: 10, completedAtMillis: 20),
        toolCall("call-a", startedAtMillis: 30, completedAtMillis: 40),
        toolCall("call-b", toolName: " ", startedAtMillis: 10, completedAtMillis: 20),
        toolCall(
          "call-c",
          toolName: String(repeating: "t", count: 200),
          argumentsJson: String(repeating: "a", count: 5_000),
          resultJson: String(repeating: "r", count: 9_000),
          errorMessage: String(repeating: "x", count: 2_000),
          startedAtMillis: 50,
          completedAtMillis: 60
        )
      ],
      checkpoints: [
        AgentWorkspaceCheckpoint(id: "checkpoint-a", eventSequence: 1, planSnapshot: "{}", createdAtMillis: 10),
        AgentWorkspaceCheckpoint(id: "checkpoint-a", eventSequence: 2, planSnapshot: #"{"new":true}"#, createdAtMillis: 20),
        AgentWorkspaceCheckpoint(id: "checkpoint-future", eventSequence: 99, createdAtMillis: 30)
      ],
      artifacts: [
        artifact("artifact-a", uri: " app://a ", createdAtMillis: 1),
        artifact("artifact-a", uri: "app://new", createdAtMillis: 2),
        artifact("artifact-empty", uri: " ", createdAtMillis: 3),
        artifact(
          "artifact-b",
          uri: "app://b",
          name: String(repeating: "n", count: 700),
          mimeType: " \(String(repeating: "m", count: 180)) ",
          metadataJson: String(repeating: "z", count: 3_000),
          createdAtMillis: 4
        )
      ]
    )

    let normalized = AgentWorkspaceBoundsPolicy.normalizeOrNil(workspace)

    XCTAssertNotNil(normalized)
    XCTAssertEqual(normalized?.goal.count, AgentWorkspaceBoundsPolicy.maxGoalCharacters)
    XCTAssertEqual(normalized?.parentRunId.count, AgentWorkspaceBoundsPolicy.maxIdentifierCharacters)
    XCTAssertEqual(normalized?.deliveryMode, "RESPOND")
    XCTAssertEqual(normalized?.currentPlanSnapshot.count, AgentWorkspaceBoundsPolicy.maxPlanCharacters)
    XCTAssertEqual(normalized?.resultJson, "{}")
    XCTAssertEqual(normalized?.errorMessage.count, AgentWorkspaceBoundsPolicy.maxErrorMessageCharacters)
    XCTAssertEqual(normalized?.permissionGrantIds.count, 2)
    XCTAssertEqual(normalized?.permissionGrantIds.first, "grant-a")
    XCTAssertEqual(normalized?.permissionGrantIds.last?.count, AgentWorkspaceBoundsPolicy.maxIdentifierCharacters)
    XCTAssertEqual(normalized?.permissionScopes, ["scope-a"])
    XCTAssertEqual(normalized?.handoffIds, ["handoff:1", "handoff:2"])
    XCTAssertEqual(normalized?.eventSequence, 3)
    XCTAssertEqual(normalized?.eventJournal.map(\.sequence), [1, 2, 3])
    XCTAssertEqual(normalized?.eventJournal[1].kind, "task.progress")
    XCTAssertEqual(normalized?.eventJournal.last?.kind.count, AgentWorkspaceBoundsPolicy.maxEventKindCharacters)
    XCTAssertEqual(normalized?.eventJournal.last?.message.count, AgentWorkspaceBoundsPolicy.maxEventMessageCharacters)
    XCTAssertEqual(normalized?.eventJournal.last?.payloadJson.count, AgentWorkspaceBoundsPolicy.maxEventPayloadCharacters)
    XCTAssertEqual(normalized?.toolCalls.map(\.id), ["call-a", "call-c"])
    XCTAssertEqual(normalized?.toolCalls.first?.startedAtMillis, 30)
    XCTAssertEqual(normalized?.toolCalls.last?.toolName.count, AgentWorkspaceBoundsPolicy.maxToolNameCharacters)
    XCTAssertEqual(normalized?.toolCalls.last?.argumentsJson.count, AgentWorkspaceBoundsPolicy.maxToolArgumentsCharacters)
    XCTAssertEqual(normalized?.toolCalls.last?.resultJson.count, AgentWorkspaceBoundsPolicy.maxToolResultCharacters)
    XCTAssertEqual(normalized?.toolCalls.last?.errorMessage.count, AgentWorkspaceBoundsPolicy.maxToolErrorCharacters)
    XCTAssertEqual(normalized?.checkpoints.map(\.id), ["checkpoint-a"])
    XCTAssertEqual(normalized?.checkpoints.first?.planSnapshot, #"{"new":true}"#)
    XCTAssertEqual(normalized?.artifacts.map(\.id), ["artifact-a", "artifact-b"])
    XCTAssertEqual(normalized?.artifacts.first?.uri, "app://new")
    XCTAssertEqual(normalized?.artifacts.last?.name.count, AgentWorkspaceBoundsPolicy.maxArtifactNameCharacters)
    XCTAssertEqual(normalized?.artifacts.last?.mimeType.count, AgentWorkspaceBoundsPolicy.maxMimeTypeCharacters)
    XCTAssertEqual(normalized?.artifacts.last?.metadataJson.count, AgentWorkspaceBoundsPolicy.maxArtifactMetadataCharacters)
  }

  func testNormalizeRejectsInvalidWorkspaceAndInvalidChildRecords() {
    let blankId = workspace(workspaceId: " ")
    let longId = workspace(workspaceId: String(repeating: "w", count: 200))
    let negativeCounters = workspace(eventSequence: -1)
    let invalidChildren = workspace(
      events: [
        AgentWorkspaceEvent(sequence: 1, kind: " ", timestampMillis: 1),
        AgentWorkspaceEvent(sequence: 2, kind: "task.progress", timestampMillis: -1)
      ],
      toolCalls: [
        toolCall("call-bad", startedAtMillis: 30, completedAtMillis: 20)
      ],
      artifacts: [
        artifact("artifact-bad", uri: "")
      ]
    )

    XCTAssertNil(AgentWorkspaceBoundsPolicy.normalizeOrNil(blankId))
    XCTAssertNil(AgentWorkspaceBoundsPolicy.normalizeOrNil(longId))
    XCTAssertNil(AgentWorkspaceBoundsPolicy.normalizeOrNil(negativeCounters))
    XCTAssertEqual(AgentWorkspaceBoundsPolicy.normalizeOrNil(invalidChildren)?.eventJournal ?? [], [])
    XCTAssertEqual(AgentWorkspaceBoundsPolicy.normalizeOrNil(invalidChildren)?.toolCalls ?? [], [])
    XCTAssertEqual(AgentWorkspaceBoundsPolicy.normalizeOrNil(invalidChildren)?.artifacts ?? [], [])
  }

  func testBoundWorkspacesKeepsBestRevisionAndLatest64() {
    let duplicateOld = workspace(workspaceId: "workspace-duplicate", revision: 1, updatedAtMillis: 10)
    let duplicateNew = workspace(workspaceId: "workspace-duplicate", revision: 2, updatedAtMillis: 1_000)
    let many = (1...70).map {
      workspace(
        workspaceId: "workspace-\($0)",
        revision: Int64($0),
        updatedAtMillis: Int64($0)
      )
    }

    let bounded = AgentWorkspaceBoundsPolicy.boundWorkspaces([duplicateOld, duplicateNew] + many)

    XCTAssertEqual(bounded.count, AgentWorkspaceBoundsPolicy.maxWorkspaces)
    XCTAssertFalse(bounded.contains { $0.workspaceId == "workspace-1" })
    XCTAssertFalse(bounded.contains { $0.workspaceId == "workspace-7" })
    XCTAssertEqual(bounded.first?.workspaceId, "workspace-8")
    XCTAssertEqual(bounded.first { $0.workspaceId == "workspace-duplicate" }?.revision, 2)
  }

  func testNormalizePrunesRuntimeLedgersToAndroidLimits() {
    let workspace = self.workspace(
      permissionGrantIds: (1...140).map { "grant-\($0)" },
      handoffIds: (1...140).map { "handoff:\($0)" },
      events: (1...110).map {
        AgentWorkspaceEvent(sequence: Int64($0), kind: AgentTaskEventKinds.progress, timestampMillis: Int64($0))
      },
      toolCalls: (1...60).map { toolCall("call-\($0)", startedAtMillis: Int64($0), completedAtMillis: Int64($0 + 1)) },
      checkpoints: (1...15).map {
        AgentWorkspaceCheckpoint(id: "checkpoint-\($0)", eventSequence: Int64($0), createdAtMillis: Int64($0))
      },
      artifacts: (1...60).map { artifact("artifact-\($0)", uri: "app://\($0)", createdAtMillis: Int64($0)) }
    )

    let normalized = AgentWorkspaceBoundsPolicy.normalizeOrNil(workspace)

    XCTAssertEqual(normalized?.eventJournal.count, AgentWorkspaceBoundsPolicy.maxEvents)
    XCTAssertEqual(normalized?.eventJournal.first?.sequence, 11)
    XCTAssertEqual(normalized?.toolCalls.count, AgentWorkspaceBoundsPolicy.maxToolCalls)
    XCTAssertEqual(normalized?.toolCalls.first?.id, "call-11")
    XCTAssertEqual(normalized?.checkpoints.count, AgentWorkspaceBoundsPolicy.maxCheckpoints)
    XCTAssertEqual(normalized?.checkpoints.first?.id, "checkpoint-6")
    XCTAssertEqual(normalized?.artifacts.count, AgentWorkspaceBoundsPolicy.maxArtifacts)
    XCTAssertEqual(normalized?.artifacts.first?.id, "artifact-11")
    XCTAssertEqual(normalized?.permissionGrantIds.count, AgentWorkspaceBoundsPolicy.maxPermissionBindings)
    XCTAssertEqual(normalized?.permissionGrantIds.last, "grant-128")
    XCTAssertEqual(normalized?.handoffIds.count, AgentWorkspaceBoundsPolicy.maxHandoffIds)
    XCTAssertEqual(normalized?.handoffIds.last, "handoff:128")
  }

  private func workspace(
    workspaceId: String = "workspace",
    goal: String = "",
    parentRunId: String = "",
    deliveryMode: String = "RESPOND",
    currentPlanSnapshot: String = "",
    resultJson: String = "{}",
    errorMessage: String = "",
    permissionGrantIds: [String] = [],
    permissionScopes: [String] = [],
    handoffIds: [String] = [],
    eventSequence: Int64 = 0,
    events: [AgentWorkspaceEvent] = [],
    toolCalls: [AgentWorkspaceToolCallRecord] = [],
    checkpoints: [AgentWorkspaceCheckpoint] = [],
    artifacts: [AgentWorkspaceArtifactReference] = [],
    revision: Int64 = 0,
    updatedAtMillis: Int64 = 1_000
  ) -> AgentWorkspace {
    AgentWorkspace(
      workspaceId: workspaceId,
      sessionId: "session",
      conversationId: "conversation",
      taskId: "task",
      goal: goal,
      parentRunId: parentRunId,
      deliveryMode: deliveryMode,
      status: .running,
      currentPlanSnapshot: currentPlanSnapshot,
      resultJson: resultJson,
      errorMessage: errorMessage,
      permissionGrantIds: permissionGrantIds,
      permissionScopes: permissionScopes,
      handoffIds: handoffIds,
      eventSequence: eventSequence == 0 ? events.map(\.sequence).max() ?? 0 : eventSequence,
      eventJournal: events,
      toolCalls: toolCalls,
      checkpoints: checkpoints,
      artifacts: artifacts,
      createdAtMillis: 1_000,
      updatedAtMillis: updatedAtMillis,
      revision: revision
    )
  }

  private func toolCall(
    _ id: String,
    toolName: String? = nil,
    argumentsJson: String = "",
    resultJson: String = "",
    errorMessage: String = "",
    startedAtMillis: Int64,
    completedAtMillis: Int64
  ) -> AgentWorkspaceToolCallRecord {
    AgentWorkspaceToolCallRecord(
      id: id,
      toolName: toolName ?? "tool.\(id)",
      status: .succeeded,
      argumentsJson: argumentsJson,
      resultJson: resultJson,
      errorMessage: errorMessage,
      startedAtMillis: startedAtMillis,
      completedAtMillis: completedAtMillis
    )
  }

  private func artifact(
    _ id: String,
    uri: String,
    name: String = "",
    mimeType: String = "",
    metadataJson: String = "",
    createdAtMillis: Int64
  ) -> AgentWorkspaceArtifactReference {
    AgentWorkspaceArtifactReference(
      id: id,
      uri: uri,
      name: name,
      mimeType: mimeType,
      metadataJson: metadataJson,
      createdAtMillis: createdAtMillis
    )
  }
}
