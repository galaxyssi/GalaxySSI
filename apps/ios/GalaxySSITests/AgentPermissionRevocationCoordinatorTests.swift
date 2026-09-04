import XCTest
@testable import GalaxySSI

final class AgentPermissionRevocationCoordinatorTests: XCTestCase {
  func testRevocationPausesDependentWorkspaceAndRunAfterRestart() throws {
    let grantStore = InMemoryAgentPermissionGrantStore(nowMillis: { 2_000 })
    let issued = try grantStore.grant(permissionGrant(
      lifetime: .permanent,
      maxUses: 0
    ))
    let workspaceStore = InMemoryAgentWorkspaceStore(clock: { 2_000 })
    _ = try workspaceStore.upsert(AgentWorkspace(
      workspaceId: "workspace-1",
      sessionId: "session-1",
      conversationId: "conversation-1",
      taskId: "task-1",
      goal: "Read location and continue",
      status: .running,
      permissionGrantIds: [issued.grantId],
      permissionScopes: [issued.scope],
      toolCalls: [
        AgentWorkspaceToolCallRecord(
          id: "location-call",
          toolName: "ios.location",
          status: .running,
          startedAtMillis: 1_500
        )
      ]
    ))
    let runStore = PermissionRevocationRunControlStore(taskId: "task-1")
    var pausedHook: [(String, String)] = []

    let report = AgentPermissionRevocationCoordinator(
      grantStore: grantStore,
      workspaceStore: workspaceStore,
      runEventStore: runStore,
      pauseActiveWorkspace: { workspaceId, reason in
        pausedHook.append((workspaceId, reason))
        return true
      }
    ).revokeScope(scope: issued.scope, reason: "user_revoked")

    let restored = try XCTUnwrap(InMemoryAgentWorkspaceStore(
      initialWorkspaces: AgentWorkspaceJsonCodec.decodeList(workspaceStore.serializedSnapshot()),
      clock: { 3_000 }
    ).find("workspace-1"))

    XCTAssertEqual(report.pausedWorkspaceIds, Set(["workspace-1"]))
    XCTAssertEqual(report.pausedRunIds, Set(["run-1"]))
    XCTAssertTrue(report.failedWorkspaceIds.isEmpty)
    XCTAssertEqual(pausedHook.count, 1)
    XCTAssertEqual(pausedHook.first?.0, "workspace-1")
    XCTAssertEqual(pausedHook.first?.1, "user_revoked")
    XCTAssertEqual(restored.status, .paused)
    XCTAssertEqual(restored.errorMessage, "user_revoked")
    XCTAssertEqual(restored.toolCalls.single?.status, .cancelled)
    XCTAssertEqual(restored.toolCalls.single?.errorMessage, "user_revoked")
    XCTAssertEqual(restored.toolCalls.single?.completedAtMillis, 2_000)
    XCTAssertTrue(restored.checkpoints.last?.stateJson.contains("user_revoked") == true)
    XCTAssertEqual(restored.eventJournal.last?.kind, AgentTaskEventKinds.permissionRevoked)
    XCTAssertEqual(restored.eventJournal.last?.timestampMillis, 2_000)
    XCTAssertEqual(runStore.appended.single?.type, .permissionRevoked)
    XCTAssertEqual(runStore.appended.single?.timestampMillis, 2_000)
    XCTAssertEqual(runStore.appended.single?.payload["revocation_reason"]?.stringValue, "user_revoked")
    XCTAssertTrue(runStore.appended.single?.payload["revoked_scopes"]?.stringValue?.contains("location.foreground") == true)
  }

  func testEmptyRevocationDoesNotTouchWorkspaceOrRunState() throws {
    let grantStore = InMemoryAgentPermissionGrantStore(nowMillis: { 2_000 })
    let workspaceStore = InMemoryAgentWorkspaceStore(clock: { 2_000 })
    _ = try workspaceStore.upsert(AgentWorkspace(
      workspaceId: "workspace-1",
      sessionId: "session-1",
      conversationId: "conversation-1",
      taskId: "task-1",
      status: .running
    ))
    let runStore = PermissionRevocationRunControlStore(taskId: "task-1")

    let report = AgentPermissionRevocationCoordinator(
      grantStore: grantStore,
      workspaceStore: workspaceStore,
      runEventStore: runStore
    ).revokeScope(scope: "missing.scope", reason: "missing")

    XCTAssertTrue(report.revocation.revokedGrantIds.isEmpty)
    XCTAssertTrue(report.pausedWorkspaceIds.isEmpty)
    XCTAssertTrue(report.pausedRunIds.isEmpty)
    XCTAssertTrue(report.failedWorkspaceIds.isEmpty)
    XCTAssertTrue(runStore.appended.isEmpty)
    XCTAssertEqual(workspaceStore.find("workspace-1")?.status, .running)
  }

  private func permissionGrant(
    grantId: String = "grant-location",
    lifetime: AgentPermissionGrantLifetime,
    subjectId: String = "ios.location",
    scope: String = "location.foreground",
    action: String = "read",
    resource: String = "",
    target: String = "",
    maxUses: Int? = nil
  ) -> AgentPermissionGrant {
    AgentPermissionGrant(
      grantId: grantId,
      subjectType: .tool,
      subjectId: subjectId,
      scope: scope,
      action: action,
      resource: resource,
      target: target,
      issuer: .user,
      evidence: "approval-dialog:turn-1",
      lifetime: lifetime,
      maxUses: maxUses,
      createdAtMillis: 1_000
    )
  }
}

private final class PermissionRevocationRunControlStore: AgentRunControlStore {
  let event: AgentRunControlEvent
  var appended: [AgentRunControlEvent] = []

  init(taskId: String) {
    self.event = AgentRunControlEvent(
      conversationId: "conversation-1",
      messageId: "message-1",
      taskId: taskId,
      runId: "run-1",
      agentId: "codex",
      deviceId: "desktop-1",
      type: .toolProgress,
      sequence: 5
    )
  }

  func appendNext(_ event: AgentRunControlEvent) -> AgentRunControlEvent {
    var next = event
    next.sequence = self.event.sequence + Int64(appended.count) + 1
    appended.append(next)
    return next
  }

  func recoverableRuns() -> [AgentRunControlSnapshot] {
    let latest = appended.last ?? event
    return [
      AgentRunControlSnapshot(
        runId: latest.runId,
        taskId: latest.taskId,
        state: AgentRunEventStore.reduce(current: .running, event: latest.type),
        agentId: latest.agentId,
        deviceId: latest.deviceId,
        lastSequence: latest.sequence,
        lastEvent: latest
      )
    ]
  }
}

private extension Array {
  var single: Element? {
    count == 1 ? first : nil
  }
}
