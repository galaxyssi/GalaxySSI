import XCTest
@testable import GalaxySSI

final class AgentRunRecoveryCoordinatorTests: XCTestCase {
  func testProcessRecreationReconnectsRemoteCursorCheckpointAndToolState() async throws {
    let workspaceStore = InMemoryAgentWorkspaceStore(clock: { 2_000 })
    _ = try workspaceStore.upsert(AgentWorkspace(
      workspaceId: "turn-1",
      sessionId: "session-1",
      conversationId: "conversation-1",
      taskId: "turn-1",
      goal: "Continue a durable Codex task",
      agentId: "codex",
      deviceId: "desktop-1",
      remoteRunId: "remote-1",
      status: .waitingResponse,
      permissionScopes: ["filesystem.project.write"],
      toolCalls: [
        AgentWorkspaceToolCallRecord(
          id: "shell-1",
          toolName: "shell",
          status: .running,
          argumentsJson: #"{"cmd":"gradle test"}"#,
          startedAtMillis: 1_000
        )
      ],
      checkpoints: [
        AgentWorkspaceCheckpoint(
          id: "before-death",
          stateJson: #"{"cursor":7,"permission_wait":true}"#,
          createdAtMillis: 1_500
        )
      ],
      lastRemoteEventSequence: 7
    ))
    let eventStore = RecoveryRunControlStore(
      event: runEvent(type: .waitingForDevice, sequence: 8)
    )
    let registration = durableRegistration()
    let remoteHandle = AgentRunHandle(
      runId: "run-1",
      taskId: "turn-1",
      agentId: "codex",
      remoteRunId: "remote-1"
    )
    let adapter = RecoveryAgentAdapter(
      registration: registration,
      recoverable: [
        AgentRecoverableRun(
          handle: remoteHandle,
          lastEventSequence: 22,
          checkpoint: [
            "cursor": .int(22),
            "permission_wait": .bool(true),
            "active_tool_call_id": .string("shell-1")
          ]
        )
      ]
    )
    let results = try await AgentRunRecoveryCoordinator(
      runStore: eventStore,
      workspaceStore: workspaceStore,
      recordedRun: { _ in runningRecordedRun() },
      registration: { _, _ in AgentRunRecoveryRegistration(registration) },
      adapterResolver: { _ in adapter }
    ).recover()

    let restoredStore = InMemoryAgentWorkspaceStore(
      initialWorkspaces: AgentWorkspaceJsonCodec.decodeList(workspaceStore.serializedSnapshot()),
      clock: { 3_000 }
    )
    let restored = try XCTUnwrap(restoredStore.find("turn-1"))

    XCTAssertEqual(results.single?.outcome, .reconnectedRemote)
    XCTAssertEqual(restored.status, .running)
    XCTAssertEqual(restored.lastRemoteEventSequence, 22)
    XCTAssertEqual(restored.remoteRunId, "remote-1")
    XCTAssertEqual(restored.toolCalls.single?.status, .running)
    XCTAssertTrue(restored.checkpoints.last?.stateJson.contains("active_tool_call_id") == true)
    XCTAssertEqual(eventStore.appended.single?.type, .runRecovered)
  }

  func testUnavailableRemoteIsKeptRecoverableInsteadOfBeingReplayedOrFailed() async throws {
    let workspaceStore = InMemoryAgentWorkspaceStore(clock: { 2_000 })
    _ = try workspaceStore.upsert(AgentWorkspace(
      workspaceId: "turn-1",
      sessionId: "session-1",
      conversationId: "conversation-1",
      taskId: "turn-1",
      goal: "Wait for the trusted desktop",
      agentId: "codex",
      status: .running
    ))
    let eventStore = RecoveryRunControlStore(event: runEvent(type: .toolProgress, sequence: 5))
    let registration = durableRegistration()

    let results = try await AgentRunRecoveryCoordinator(
      runStore: eventStore,
      workspaceStore: workspaceStore,
      recordedRun: { _ in runningRecordedRun() },
      registration: { _, _ in AgentRunRecoveryRegistration(registration) },
      adapterResolver: { _ in nil }
    ).recover()
    let result = results.single

    XCTAssertEqual(result?.outcome, .waitingForRemote)
    XCTAssertEqual(workspaceStore.find("turn-1")?.status, .waitingResponse)
    XCTAssertEqual(eventStore.appended.single?.type, .waitingForDevice)
  }

  func testLocalPermissionWaitRemainsWaitingAcrossRepeatedStartupRecovery() async throws {
    let workspaceStore = InMemoryAgentWorkspaceStore(clock: { 2_000 })
    _ = try workspaceStore.upsert(AgentWorkspace(
      workspaceId: "turn-1",
      sessionId: "session-1",
      conversationId: "conversation-1",
      taskId: "turn-1",
      goal: "Wait for user confirmation",
      status: .waitingConfirmation,
      permissionScopes: ["contacts.write"]
    ))
    let eventStore = RecoveryRunControlStore(event: runEvent(type: .waitingForUser, sequence: 4))
    let localRegistration = AgentRegistration(
      agentId: "codex",
      installationId: "installation-1",
      deviceId: "phone-1",
      providerId: "phone-provider",
      displayName: "Phone Agent",
      location: .phone,
      connectionKind: .inProcess
    )
    let coordinator = AgentRunRecoveryCoordinator(
      runStore: eventStore,
      workspaceStore: workspaceStore,
      recordedRun: { _ in runningRecordedRun() },
      registration: { _, _ in AgentRunRecoveryRegistration(localRegistration) },
      adapterResolver: { _ in
        XCTFail("A local wait must not reconnect or replay an Agent")
        return nil
      }
    )

    let firstResults = try await coordinator.recover()
    let secondResults = try await coordinator.recover()
    let first = firstResults.single
    let second = secondResults.single

    XCTAssertEqual(first?.outcome, .restoredLocalWait)
    XCTAssertEqual(second?.outcome, .restoredLocalWait)
    XCTAssertEqual(eventStore.appended.single?.type, .waitingForUser)
    XCTAssertEqual(workspaceStore.find("turn-1")?.status, .waitingConfirmation)
  }

  private func runningRecordedRun() -> AgentRecordedRun {
    AgentRecordedRun(
      runId: "run-1",
      conversationId: "conversation-1",
      taskThreadId: "turn-1",
      originalRequest: "Continue the task"
    )
  }

  private func durableRegistration() -> AgentRegistration {
    AgentRegistration(
      agentId: "codex",
      installationId: "installation-1",
      deviceId: "desktop-1",
      providerId: "desktop-provider",
      displayName: "Codex",
      status: .busy,
      capabilities: [.code],
      connectionKind: .galaxyssiLink
    )
  }

  private func runEvent(type: AgentRunControlEventType, sequence: Int64) -> AgentRunControlEvent {
    AgentRunControlEvent(
      conversationId: "conversation-1",
      messageId: "message-1",
      taskId: "turn-1",
      runId: "run-1",
      agentId: "codex",
      deviceId: "desktop-1",
      type: type,
      sequence: sequence
    )
  }
}

private final class RecoveryRunControlStore: AgentRunControlStore {
  private let event: AgentRunControlEvent
  var appended: [AgentRunControlEvent] = []

  init(event: AgentRunControlEvent) {
    self.event = event
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

private final class RecoveryAgentAdapter: AgentAdapter {
  let registration: AgentRegistration
  private let recoverable: [AgentRecoverableRun]

  init(registration: AgentRegistration, recoverable: [AgentRecoverableRun]) {
    self.registration = registration
    self.recoverable = recoverable
  }

  func connect() async throws -> AgentProtocolAgreement {
    AgentProtocolAgreement(version: "1.0", features: ["run.recover"])
  }

  func disconnect() async {}

  func status() async throws -> AgentRegistration {
    registration
  }

  func startRun(_ request: AgentRunRequest) async throws -> AgentRunHandle {
    throw AgentControlPlaneAdapterError(message: "Recovery must not replay Run start")
  }

  func sendMessage(runId: String, message: AgentControlMessage) async throws {}

  func cancelRun(runId: String) async throws {}

  func observeEvents(runId: String) -> AsyncStream<AgentRunControlEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }

  func recoverRuns() async throws -> [AgentRecoverableRun] {
    recoverable
  }
}

private extension Array {
  var single: Element? {
    count == 1 ? first : nil
  }
}
