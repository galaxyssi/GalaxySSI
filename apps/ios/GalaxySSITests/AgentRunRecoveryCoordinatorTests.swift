import XCTest
@testable import GalaxySSI

final class AgentRunRecoveryCoordinatorTests: XCTestCase {
  func testLegacyDeviceCheckpointNeverReachesRecoveryOrInspectionAdapters() async throws {
    let legacy = deviceOperationEvent(conversation: "checkpoint-owner", type: .checkpointSaved)
    XCTAssertEqual(legacy.runId, "device-operation:ce858aedf9fc93591f2a2e2bb5f542c1b4d07c617678df8391c03937ca245a34")
    let events = RecoveryRunControlStore(event: legacy)
    let workspaces = InMemoryAgentWorkspaceStore()
    let recovery = AgentRunRecoveryCoordinator(runStore: events, workspaceStore: workspaces,
      recordedRun: { _ in XCTFail("Observation-only state must not resolve an executable run"); return nil },
      registration: { _, _ in XCTFail("Observation-only state must not resolve a registration"); return nil },
      adapterResolver: { _ in XCTFail("Observation-only state must not resolve an adapter"); return nil })
    let recovered = try await recovery.recover()
    let inspected = try await recovery.inspect()
    XCTAssertTrue(recovered.isEmpty)
    XCTAssertTrue(inspected.isEmpty)
    XCTAssertTrue(events.appended.isEmpty)
    XCTAssertTrue(workspaces.list().isEmpty)
    var foreign = legacy
    foreign.conversationId = "another-conversation"
    XCTAssertFalse(AgentRunRecoveryPolicy.isObservationOnly(foreign))
    XCTAssertFalse(AgentDeviceOperationCheckpoint.isSnapshot(runEvent(type: .checkpointSaved, sequence: 1)))
  }

  func testCheckpointWriteRepairsOnlyPersistedSyntheticFailureAndKeepsReceipts() throws {
    let suite = "device-checkpoint-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let storage = "device-checkpoint-fixture"
    let ledger = UserDefaultsAgentRunEventStore(defaults: defaults, storageKey: storage)
    let legacy = try XCTUnwrap(AgentRunKernelContract.canonical(
      deviceOperationEvent(conversation: "checkpoint-owner", type: .checkpointSaved)))
    var synthetic = legacy
    synthetic.eventId = "legacy-recovery-failure"
    synthetic.idempotencyKey = synthetic.eventId
    synthetic.sequence = 2
    synthetic.type = .runFailed
    synthetic.payload["reason"] = .string("interrupted_run_cannot_be_replayed_safely")
    synthetic.payload["replay_safe"] = .bool(false)
    let key = storage + ".run." + legacy.runId
    defaults.set(try JSONEncoder().encode([legacy, synthetic]), forKey: key)
    XCTAssertEqual(ledger.snapshot(runId: legacy.runId)?.state, .failed)

    var next = legacy
    next.eventId = "next-checkpoint"
    next.idempotencyKey = next.eventId
    next.sequence = 0
    next.payload["updated_at"] = .int(300)
    let repaired = ledger.appendNext(next)
    XCTAssertEqual(repaired.type, .runRecovered)
    XCTAssertEqual(repaired.sequence, 3)
    XCTAssertEqual(repaired.payload["operation_id"], legacy.payload["operation_id"])
    XCTAssertEqual(repaired.payload["status"], .string("completed"))
    XCTAssertEqual(repaired.payload["evidence"], legacy.payload["evidence"])
    XCTAssertEqual(repaired.payload["recovery_mode"], .string("observation_only"))
    XCTAssertNil(repaired.payload["replay_safe"])
    XCTAssertEqual(ledger.appendNext(next), repaired)

    let reopened = UserDefaultsAgentRunEventStore(defaults: defaults, storageKey: storage)
    XCTAssertEqual(reopened.events(runId: legacy.runId), [legacy, synthetic, repaired])
    var stale = next
    stale.eventId = "stale-checkpoint"
    stale.idempotencyKey = stale.eventId
    stale.payload["updated_at"] = .int(100)
    XCTAssertEqual(reopened.appendNext(stale), repaired)

    let foreign = deviceOperationEvent(conversation: "other-checkpoint", type: .checkpointSaved)
    XCTAssertEqual(reopened.appendNext(foreign).sequence, 1)
    for (type, reason) in [(AgentRunControlEventType.runCancelled, "user_cancelled"), (.runFailed, "real_failure")] {
      var terminal = synthetic
      terminal.type = type
      terminal.payload["reason"] = .string(reason)
      defaults.set(try JSONEncoder().encode([legacy, terminal]), forKey: key)
      XCTAssertTrue(reopened.appendNextAll([next]).isEmpty)
      XCTAssertEqual(reopened.appendNext(next), terminal)
      var unsolicited = next
      unsolicited.type = .runRecovered
      XCTAssertEqual(reopened.appendNext(unsolicited), terminal)
      XCTAssertEqual(reopened.latestEvent(runId: foreign.runId)?.payload["operation_id"], foreign.payload["operation_id"])
    }
  }

  private func deviceOperationEvent(conversation: String, type: AgentRunControlEventType) -> AgentRunControlEvent {
    let run = AgentDeviceOperationCheckpoint.runId(conversationId: conversation)
    return AgentRunControlEvent(eventId: run + ":checkpoint", conversationId: conversation, messageId: "",
      taskId: run, runId: run, agentId: "phone-operation", deviceId: "local", type: type, sequence: 1,
      timestampMillis: 200, payload: ["snapshot_kind": .string("device_operation"),
        "operation_id": .string("original-operation"), "kind": .string("agent"), "status": .string("completed"),
        "updated_at": .int(200), "evidence": .string("original receipt")])
  }

  func testTerminalDeliveryFailureStopsRecoveryBeforeResolvingAdapter() async throws {
    let workspaces = InMemoryAgentWorkspaceStore(clock: { 1_000 })
    _ = try workspaces.upsert(deliveryWorkspace())
    var event = runEvent(type: .waitingForDevice, sequence: 8)
    event.clientRouteId = "opaque-route"
    event.goalId = "original-goal"
    event.turnId = "original-turn"
    event.actionId = "original-action"
    let events = RecoveryRunControlStore(event: event)
    let registration = durableRegistration()
    let results = try await AgentRunRecoveryCoordinator(
      runStore: events, workspaceStore: workspaces,
      recordedRun: { _ in self.runningRecordedRun() },
      registration: { _, _ in AgentRunRecoveryRegistration(registration) },
      adapterResolver: { _ in XCTFail("Terminal delivery must not reconnect"); return nil },
      terminalDeliveries: { [self.deliveryFailure()] }
    ).recover()

    XCTAssertEqual(results.single?.outcome, .ignoredTerminal)
    XCTAssertEqual(workspaces.find("turn-1")?.status, .failed)
    XCTAssertEqual(workspaces.find("turn-1")?.errorMessage, "delivery_retry_exhausted")
    let failed = try XCTUnwrap(events.appended.single)
    XCTAssertEqual(failed.type, .runFailed)
    XCTAssertEqual(failed.clientRouteId, event.clientRouteId)
    XCTAssertEqual(failed.goalId, event.goalId)
    XCTAssertEqual(failed.turnId, event.turnId)
    XCTAssertEqual(failed.actionId, event.actionId)
    XCTAssertNotEqual(failed.eventId, event.eventId)
  }

  func testFailureArrivingDuringRemoteQueryDoesNotBecomeWaitingAgain() async throws {
    let workspaces = InMemoryAgentWorkspaceStore(clock: { 1_000 })
    _ = try workspaces.upsert(deliveryWorkspace())
    let events = RecoveryRunControlStore(event: runEvent(type: .toolProgress, sequence: 5))
    let terminals = InMemoryAgentTerminalDeliveryStore()
    let registration = durableRegistration()
    let results = try await AgentRunRecoveryCoordinator(
      runStore: events, workspaceStore: workspaces,
      recordedRun: { _ in self.runningRecordedRun() },
      registration: { _, _ in AgentRunRecoveryRegistration(registration) },
      adapterResolver: { _ in
        terminals.mark(self.deliveryFailure())
        return nil
      },
      terminalDeliveries: { terminals.records() }
    ).recover()

    XCTAssertEqual(results.single?.outcome, .ignoredTerminal)
    XCTAssertEqual(workspaces.find("turn-1")?.status, .failed)
    XCTAssertEqual(events.appended.map(\.type), [.runFailed])
  }

  func testRecoveryCASRejectsCrossInstanceProgressAndTerminalUpdates() throws {
    let suite = "recovery-cas-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = UserDefaultsAgentRunEventStore(defaults: defaults)
    let second = UserDefaultsAgentRunEventStore(defaults: defaults)
    let started = first.appendNext(runEvent(type: .runStarted, sequence: 0))
    _ = first.recoverableRuns()
    var progress = started
    progress.eventId = UUID().uuidString
    progress.idempotencyKey = progress.eventId
    progress.type = .toolProgress
    let advanced = second.appendNext(progress)
    var failure = started
    failure.eventId = UUID().uuidString
    failure.idempotencyKey = failure.eventId
    failure.type = .runFailed
    XCTAssertNil(first.appendRecoveryIfCurrent(failure, expectedSequence: started.sequence))
    XCTAssertEqual(first.latestEvent(runId: started.runId)?.eventId, advanced.eventId)
    XCTAssertNotNil(first.appendRecoveryIfCurrent(failure, expectedSequence: advanced.sequence))
    var resumed = failure
    resumed.eventId = UUID().uuidString
    resumed.idempotencyKey = resumed.eventId
    resumed.type = .runRecovered
    XCTAssertNil(second.appendRecoveryIfCurrent(resumed, expectedSequence: advanced.sequence + 1))
  }

  func testIndexedReadsSeeCrossInstanceCommitsAndPreserveNestedReplayPayloads() throws {
    let suite = "run-index-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let reader = UserDefaultsAgentRunEventStore(defaults: defaults)
    let writer = UserDefaultsAgentRunEventStore(defaults: defaults)
    let started = writer.appendNext(runEvent(type: .runStarted, sequence: 0))
    XCTAssertEqual(reader.latestEvent(runId: started.runId), started)
    var event = started
    event.eventId = "stable-progress"
    event.idempotencyKey = "stable-progress"
    event.actionId = "progress-action"
    event.type = .toolProgress
    event.payload = ["details": .object(["values": .array([.int(42), .double(0.25), .null, .bool(false)])])]
    let committed = writer.appendNext(event)
    XCTAssertTrue(reader.containsIdempotencyKey(runId: started.runId, key: event.idempotencyKey))
    XCTAssertEqual(reader.snapshot(runId: started.runId)?.lastEvent, committed)

    var replay = event
    replay.eventId = "different-transport-id"
    replay.payload = ["details": .object(["values": .array([.double(42.0), .double(0.25), .null, .bool(false)])])]
    XCTAssertEqual(reader.appendNext(replay), committed)
    replay.payload = ["details": .object(["values": .array([.string("42"), .double(0.25), .null, .bool(false)])])]
    XCTAssertFalse(AgentRunKernelContract.isIdempotentReplay(committed, replay))
    XCTAssertEqual(reader.events(runId: started.runId), [started, committed])
    writer.removeRuns([started.runId])
    XCTAssertNil(reader.snapshot(runId: started.runId))
    XCTAssertFalse(reader.containsIdempotencyKey(runId: started.runId, key: event.idempotencyKey))
  }

  func testSnapshotReadDoesNotWaitForLedgerWriter() async throws {
    let suite = "run-read-contention-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(BlockingLedgerDefaults(suiteName: suite))
    let entered = expectation(description: "writer paused before publishing")
    let read = expectation(description: "reader got last committed run")
    let written = expectation(description: "writer completed")
    let release = DispatchSemaphore(value: 0)
    let ledger = UserDefaultsAgentRunEventStore(defaults: defaults)
    let started = ledger.appendNext(runEvent(type: .runStarted, sequence: 0))
    var progress = started
    progress.type = .toolProgress
    progress.eventId = "next-progress"
    progress.idempotencyKey = progress.eventId
    let next = progress
    defaults.beforeSet = { key in
      guard key.hasSuffix(".run." + started.runId) else { return }
      entered.fulfill()
      _ = release.wait(timeout: .now() + 5)
    }
    defer { defaults.removePersistentDomain(forName: suite) }
    DispatchQueue.global().async {
      _ = ledger.appendNext(next)
      written.fulfill()
    }
    await fulfillment(of: [entered], timeout: 2)
    DispatchQueue.global().async {
      XCTAssertEqual(ledger.snapshot(runId: started.runId)?.lastEvent, started)
      read.fulfill()
    }
    await fulfillment(of: [read], timeout: 2)
    release.signal()
    await fulfillment(of: [written], timeout: 2)
    XCTAssertEqual(ledger.latestEvent(runId: started.runId)?.eventId, next.eventId)
  }

  private func deliveryWorkspace() -> AgentWorkspace {
    AgentWorkspace(
      workspaceId: "turn-1", sessionId: "session-1", conversationId: "conversation-1",
      taskId: "turn-1", agentId: "codex", deviceId: "desktop-1", status: .waitingResponse,
      createdAtMillis: 1_000, updatedAtMillis: 1_000
    )
  }

  private func deliveryFailure() -> AgentTerminalDelivery {
    AgentTerminalDelivery(
      sourceMessageId: 71, conversationId: "conversation-1", turnId: "turn-1", taskId: "turn-1",
      reason: "delivery_retry_exhausted", terminalAtMillis: 2_000, isFailure: true
    )
  }

  func testRecoveryWakeCoalescesConcurrentEventsAndRetainsOfflineWake() async throws {
    let firstStarted = expectation(description: "first recovery started")
    let passesFinished = expectation(description: "coalesced recovery passes finished")
    passesFinished.expectedFulfillmentCount = 2
    let counter = RecoveryWakeCounter()
    let coordinator = AgentRecoveryWakeCoordinator { _ in
      let count = counter.increment()
      if count == 1 {
        firstStarted.fulfill()
        try await Task.sleep(nanoseconds: 80_000_000)
      }
      passesFinished.fulfill()
    }

    coordinator.request(isConnected: false)
    XCTAssertTrue(coordinator.hasPendingWake)
    XCTAssertFalse(coordinator.isRunning)
    coordinator.connectionChanged(true)
    await fulfillment(of: [firstStarted], timeout: 1)
    coordinator.request()
    coordinator.request()
    coordinator.request()
    await fulfillment(of: [passesFinished], timeout: 2)

    XCTAssertEqual(counter.value, 2)
    XCTAssertFalse(coordinator.hasPendingWake)
  }

  func testRecoveryWakeRetriesUnresolvedPassAndExternalWakeInterruptsBackoff() async throws {
    let firstStarted = expectation(description: "first recovery started")
    let secondStarted = expectation(description: "retry recovery started")
    let counter = RecoveryWakeCounter()
    let coordinator = AgentRecoveryWakeCoordinator(
      recover: { retry in
        let count = counter.increment()
        if count == 1 {
          firstStarted.fulfill()
          retry()
        } else if count == 2 {
          secondStarted.fulfill()
        }
      },
      initialRetryMillis: 1_000,
      maxRetryMillis: 2_000
    )

    coordinator.request(isConnected: true)
    await fulfillment(of: [firstStarted], timeout: 1)
    coordinator.request()
    await fulfillment(of: [secondStarted], timeout: 0.5)

    XCTAssertEqual(counter.value, 2)
    XCTAssertFalse(coordinator.hasPendingWake)
  }

  func testRecoveryWakeAutomaticallyRetriesAfterBoundedDelay() async throws {
    let retried = expectation(description: "unresolved recovery retried")
    let counter = RecoveryWakeCounter()
    let coordinator = AgentRecoveryWakeCoordinator(
      recover: { retry in
        if counter.increment() == 1 {
          retry()
        } else {
          retried.fulfill()
        }
      },
      initialRetryMillis: 20,
      maxRetryMillis: 40
    )

    coordinator.request(isConnected: true)
    await fulfillment(of: [retried], timeout: 1)

    XCTAssertEqual(counter.value, 2)
    XCTAssertFalse(coordinator.hasPendingWake)
  }

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

private final class BlockingLedgerDefaults: UserDefaults {
  var beforeSet: ((String) -> Void)?

  override func set(_ value: Any?, forKey defaultName: String) {
    beforeSet?(defaultName)
    super.set(value, forKey: defaultName)
  }
}

private final class RecoveryWakeCounter {
  private let lock = NSLock()
  private var count = 0

  func increment() -> Int {
    lock.lock()
    defer { lock.unlock() }
    count += 1
    return count
  }

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
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
