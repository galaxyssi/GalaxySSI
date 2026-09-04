import XCTest
@testable import GalaxySSI

final class AgentWorkspaceRuntimeMetadataTests: XCTestCase {
  func testAgentWorkspaceDecodesAndroidRuntimeMetadataFields() throws {
    let workspace = try JSONDecoder().decode(
      AgentWorkspace.self,
      from: Data(
        #"""
        {
          "workspace_id": "workspace",
          "session_id": "session",
          "conversation_id": "conversation",
          "task_id": "task",
          "goal": "Run task",
          "parent_run_id": "parent-run",
          "agent_id": "codex",
          "device_id": "desktop",
          "remote_run_id": "remote-71",
          "delivery_mode": "RESPOND",
          "status": "WAITING_RESPONSE",
          "current_plan_snapshot": "{\"actions\":[]}",
          "result_json": "{\"ok\":true}",
          "error_message": "waiting",
          "permission_grant_ids": [" grant-a ", ""],
          "permission_scopes": ["contacts.read"],
          "handoff_ids": ["handoff:71"],
          "last_remote_event_sequence": 8,
          "event_sequence": 2,
          "event_journal": [
            {
              "sequence": 2,
              "kind": "task.progress",
              "message": "still running",
              "payload_json": "{\"stage\":\"observe\"}",
              "timestamp": 1234
            }
          ],
          "tool_calls": [
            {
              "id": "call-1",
              "tool_name": "workspace.read_text",
              "status": "SUCCEEDED",
              "arguments_json": "{\"path\":\"README.md\"}",
              "result_json": "{\"text\":\"ok\"}",
              "error_message": "",
              "started_at": 1200,
              "completed_at": 1250
            }
          ],
          "checkpoints": [
            {
              "id": "checkpoint-1",
              "event_sequence": 2,
              "plan_snapshot": "{\"actions\":[]}",
              "state_json": "{\"phase\":\"observe\"}",
              "created_at": 1300
            }
          ],
          "artifacts": [
            {
              "id": "artifact-1",
              "uri": "app://artifact/1",
              "name": "result.zip",
              "mime_type": "application/zip",
              "metadata_json": "{\"sha256\":\"abc\"}",
              "created_at": 1400
            }
          ],
          "cancellation_requested": false,
          "created_at": 1000,
          "updated_at": 1234,
          "revision": 5
        }
        """#.utf8
      )
    )

    XCTAssertEqual(workspace.parentRunId, "parent-run")
    XCTAssertEqual(workspace.agentId, "codex")
    XCTAssertEqual(workspace.deviceId, "desktop")
    XCTAssertEqual(workspace.remoteRunId, "remote-71")
    XCTAssertEqual(workspace.deliveryMode, "RESPOND")
    XCTAssertEqual(workspace.currentPlanSnapshot, #"{"actions":[]}"#)
    XCTAssertEqual(workspace.resultJson, #"{"ok":true}"#)
    XCTAssertEqual(workspace.errorMessage, "waiting")
    XCTAssertEqual(workspace.permissionGrantIds, ["grant-a"])
    XCTAssertEqual(workspace.permissionScopes, ["contacts.read"])
    XCTAssertEqual(workspace.handoffIds, ["handoff:71"])
    XCTAssertEqual(workspace.lastRemoteEventSequence, 8)
    XCTAssertEqual(workspace.eventJournal.first?.timestampMillis, 1234)
    XCTAssertEqual(workspace.toolCalls.first?.toolName, "workspace.read_text")
    XCTAssertEqual(workspace.toolCalls.first?.status, .succeeded)
    XCTAssertEqual(workspace.toolCalls.first?.argumentsJson, #"{"path":"README.md"}"#)
    XCTAssertEqual(workspace.checkpoints.first?.createdAtMillis, 1300)
    XCTAssertEqual(workspace.artifacts.first?.mimeType, "application/zip")
    XCTAssertEqual(workspace.createdAtMillis, 1000)
    XCTAssertEqual(workspace.updatedAtMillis, 1234)
  }

  func testAgentWorkspaceKeepsLegacyMinimalPayloadDefaults() throws {
    let workspace = try JSONDecoder().decode(
      AgentWorkspace.self,
      from: Data(
        #"""
        {
          "workspace_id": "workspace",
          "session_id": "session",
          "conversation_id": "conversation",
          "task_id": "task",
          "status": "RUNNING",
          "created_at_millis": 1000,
          "updated_at_millis": 1100
        }
        """#.utf8
      )
    )

    XCTAssertEqual(workspace.deliveryMode, "RESPOND")
    XCTAssertEqual(workspace.resultJson, "{}")
    XCTAssertTrue(workspace.permissionGrantIds.isEmpty)
    XCTAssertTrue(workspace.toolCalls.isEmpty)
    XCTAssertTrue(workspace.checkpoints.isEmpty)
    XCTAssertEqual(workspace.createdAtMillis, 1000)
    XCTAssertEqual(workspace.updatedAtMillis, 1100)
  }

  func testAgentWorkspaceRuntimeMetadataUsesAndroidWireNames() throws {
    let workspace = AgentWorkspace(
      workspaceId: "workspace",
      sessionId: "session",
      conversationId: "conversation",
      taskId: "task",
      parentRunId: "parent",
      agentId: "codex",
      deviceId: "desktop",
      remoteRunId: "remote",
      deliveryMode: "OBSERVE",
      status: .running,
      currentPlanSnapshot: "{}",
      resultJson: "{}",
      errorMessage: "none",
      permissionGrantIds: ["grant-a"],
      permissionScopes: ["contacts.read"],
      handoffIds: ["handoff:1"],
      lastRemoteEventSequence: 9,
      eventSequence: 1,
      eventJournal: [
        AgentWorkspaceEvent(
          sequence: 1,
          kind: AgentTaskEventKinds.running,
          timestampMillis: 1_000
        )
      ],
      toolCalls: [
        AgentWorkspaceToolCallRecord(
          id: "call",
          toolName: "workspace.stat",
          status: .running,
          argumentsJson: "{}",
          startedAtMillis: 1_100
        )
      ],
      checkpoints: [
        AgentWorkspaceCheckpoint(id: "checkpoint", eventSequence: 1, createdAtMillis: 1_200)
      ],
      artifacts: [
        AgentWorkspaceArtifactReference(id: "artifact", uri: "app://artifact", createdAtMillis: 1_300)
      ],
      createdAtMillis: 900,
      updatedAtMillis: 1_300
    )
    let encoded = String(decoding: try JSONEncoder().encode(workspace), as: UTF8.self)

    XCTAssertTrue(encoded.contains(#""parent_run_id":"parent""#))
    XCTAssertTrue(encoded.contains(#""agent_id":"codex""#))
    XCTAssertTrue(encoded.contains(#""remote_run_id":"remote""#))
    XCTAssertTrue(encoded.contains(#""delivery_mode":"OBSERVE""#))
    XCTAssertTrue(encoded.contains(#""current_plan_snapshot":"{}""#))
    XCTAssertTrue(encoded.contains(#""result_json":"{}""#))
    XCTAssertTrue(encoded.contains(#""error_message":"none""#))
    XCTAssertTrue(encoded.contains(#""permission_grant_ids":["grant-a"]"#))
    XCTAssertTrue(encoded.contains(#""last_remote_event_sequence":9"#))
    XCTAssertTrue(encoded.contains(#""tool_name":"workspace.stat""#))
    XCTAssertTrue(encoded.contains(#""started_at":1100"#))
    XCTAssertTrue(encoded.contains(#""created_at":1200"#))
  }

  func testAgentWorkspaceExecutionSnapshotUsesAndroidWireNames() throws {
    let snapshot = AgentWorkspaceExecutionSnapshot(
      status: .waitingResponse,
      planSnapshot: "{}",
      resultJson: "{\"waiting\":true}",
      errorMessage: "waiting",
      toolCalls: [AgentWorkspaceToolCallRecord(id: "call", toolName: "tool", status: .pending)],
      artifacts: [AgentWorkspaceArtifactReference(id: "artifact", uri: "app://artifact")],
      permissionGrantIds: ["grant-a"],
      permissionScopes: ["contacts.read"],
      handoffIds: ["handoff:1"],
      agentId: "codex",
      deviceId: "desktop",
      remoteRunId: "remote",
      lastRemoteEventSequence: 3
    )
    let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)

    XCTAssertTrue(encoded.contains(#""status":"WAITING_RESPONSE""#))
    XCTAssertTrue(encoded.contains(#""plan_snapshot":"{}""#))
    XCTAssertTrue(encoded.contains(#""result_json":"{\"waiting\":true}""#))
    XCTAssertTrue(encoded.contains(#""tool_calls":["#))
    XCTAssertTrue(encoded.contains(#""permission_scopes":["contacts.read"]"#))
    XCTAssertTrue(encoded.contains(#""handoff_ids":["handoff:1"]"#))
    XCTAssertTrue(encoded.contains(#""last_remote_event_sequence":3"#))
  }
}
