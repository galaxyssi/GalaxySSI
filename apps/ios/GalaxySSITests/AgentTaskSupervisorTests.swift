import XCTest
@testable import GalaxySSI

final class AgentTaskSupervisorTests: XCTestCase {
  func testMemoryObserverReceivesQueuedAndTerminalTaskIdentity() async throws {
    let clock = TestClock(start: 1_000)
    let store = InMemoryAgentWorkspaceStore(clock: clock.tick)
    let observer = AgentTaskSupervisorObserver()
    let supervisor = AgentTaskSupervisor(
      workspaceStore: store,
      clock: clock.tick,
      memoryObserver: { observer.record($0) }
    )

    let handle = try supervisor.submit(workspace("memory")) { context in
      _ = try context.recordExecutionSnapshot(AgentWorkspaceExecutionSnapshot(agentId: "model:deepseek"))
    }
    await handle.join()
    await supervisor.shutdown()

    let observed = observer.snapshot()
    XCTAssertTrue(observed.contains {
      $0.taskId == "task-memory" && $0.status == .queued
    })
    XCTAssertTrue(observed.contains {
      $0.taskId == "task-memory" &&
        $0.agentId == "model:deepseek" &&
        $0.status == .completed
    })
    XCTAssertTrue(supervisor.activeWorkspaces().isEmpty)
  }

  func testReadReasoningLaneBoundsConcurrentWork() async throws {
    let store = InMemoryAgentWorkspaceStore()
    let supervisor = AgentTaskSupervisor(workspaceStore: store, maxConcurrentReadReasoningTasks: 2)
    let probe = AgentTaskSupervisorProbe()

    let handles = try (1...4).map { index in
      try supervisor.submit(workspace("\(index)")) { _ in
        await probe.begin("task-\(index)")
        await probe.waitForRelease()
        await probe.finish("task-\(index)")
      }
    }

    await probe.waitForStarted(count: 2)
    let maximumRunning = await probe.maximumRunning()
    let initiallyStarted = await probe.startedCount()
    XCTAssertEqual(maximumRunning, 2)
    XCTAssertEqual(initiallyStarted, 2)

    await probe.releaseAll()
    for handle in handles {
      await handle.join()
    }
    await supervisor.shutdown()

    let finallyStarted = await probe.startedCount()
    XCTAssertEqual(finallyStarted, 4)
    XCTAssertTrue(store.list().allSatisfy { $0.status == .completed })
  }

  func testForegroundChatStartsWhileBackgroundWorkUsesReservedCapacity() async throws {
    let store = InMemoryAgentWorkspaceStore()
    let supervisor = AgentTaskSupervisor(workspaceStore: store, maxConcurrentReadReasoningTasks: 2)
    let probe = AgentTaskSupervisorProbe()

    let firstBackground = try supervisor.submit(
      workspace("background-one"),
      lane: .readReasoning,
      priority: .background
    ) { _ in
      await probe.begin("background-one")
      await probe.waitForRelease()
      await probe.finish("background-one")
    }
    await probe.waitForStarted(id: "background-one")

    let secondBackground = try supervisor.submit(
      workspace("background-two"),
      lane: .readReasoning,
      priority: .background
    ) { _ in
      await probe.begin("background-two")
      await probe.waitForRelease()
      await probe.finish("background-two")
    }
    let foreground = try supervisor.submit(
      workspace("foreground"),
      lane: .readReasoning,
      priority: .foreground
    ) { _ in
      await probe.begin("foreground")
      await probe.waitForRelease()
      await probe.finish("foreground")
    }

    await probe.waitForStarted(id: "foreground")
    let secondBackgroundStartedEarly = await probe.hasStarted("background-two")
    XCTAssertFalse(secondBackgroundStartedEarly)
    XCTAssertEqual(AgentForegroundWorkCoordinator.activeCount, 1)

    await probe.releaseAll()
    await firstBackground.join()
    await secondBackground.join()
    await foreground.join()
    await supervisor.shutdown()

    let secondBackgroundEventuallyStarted = await probe.hasStarted("background-two")
    XCTAssertTrue(secondBackgroundEventuallyStarted)
    XCTAssertEqual(AgentForegroundWorkCoordinator.activeCount, 0)
  }

  func testSideEffectLaneRunsOneTaskAtATime() async throws {
    let store = InMemoryAgentWorkspaceStore()
    let supervisor = AgentTaskSupervisor(workspaceStore: store)
    let probe = AgentTaskSupervisorProbe()

    let first = try supervisor.submit(workspace("first"), lane: .sideEffect) { _ in
      await probe.begin("first")
      await probe.waitForRelease()
      await probe.finish("first")
    }
    await probe.waitForStarted(id: "first")

    let second = try supervisor.submit(workspace("second"), lane: .sideEffect) { _ in
      await probe.begin("second")
      await probe.finish("second")
    }
    try await Task.sleep(nanoseconds: 80_000_000)
    let secondStartedEarly = await probe.hasStarted("second")
    XCTAssertFalse(secondStartedEarly)

    await probe.releaseAll()
    await first.join()
    await second.join()
    await supervisor.shutdown()

    let secondEventuallyStarted = await probe.hasStarted("second")
    XCTAssertTrue(secondEventuallyStarted)
    XCTAssertEqual(store.find("workspace-first")?.status, .completed)
    XCTAssertEqual(store.find("workspace-second")?.status, .completed)
  }

  func testFailedTaskDoesNotCancelSibling() async throws {
    let store = InMemoryAgentWorkspaceStore()
    let supervisor = AgentTaskSupervisor(workspaceStore: store)
    let probe = AgentTaskSupervisorProbe()

    let failed = try supervisor.submit(workspace("failed")) { _ in
      throw AgentTaskSupervisorError(message: "reasoning failed")
    }
    let sibling = try supervisor.submit(workspace("sibling")) { _ in
      await probe.begin("sibling")
      await probe.finish("sibling")
    }

    await failed.join()
    await sibling.join()

    let siblingStarted = await probe.hasStarted("sibling")
    XCTAssertTrue(siblingStarted)
    XCTAssertEqual(store.find("workspace-failed")?.status, .failed)
    XCTAssertEqual(store.find("workspace-sibling")?.status, .completed)
    XCTAssertTrue(supervisor.isActive)
    await supervisor.shutdown()
  }

  func testCancellationSourcePersistsCancellationEventAndCheckpoint() async throws {
    let clock = TestClock(start: 1_000)
    let store = InMemoryAgentWorkspaceStore(clock: clock.tick)
    let supervisor = AgentTaskSupervisor(workspaceStore: store, clock: clock.tick)
    let probe = AgentTaskSupervisorProbe()

    let handle = try supervisor.submit(workspace("cancel")) { context in
      _ = try context.checkpoint(
        checkpointId: "before-side-effect",
        planSnapshot: "1. Read\n2. Confirm\n3. Execute",
        stateJson: #"{"step":2}"#
      )
      await probe.begin("cancel")
      while true {
        try context.ensureActive()
        try await Task.sleep(nanoseconds: 10_000_000)
      }
    }

    await probe.waitForStarted(id: "cancel")
    XCTAssertTrue(handle.cancel(reason: "user stopped task"))
    await handle.join()
    await supervisor.shutdown()

    let cancelled = try XCTUnwrap(store.find("workspace-cancel"))
    XCTAssertEqual(cancelled.status, .cancelled)
    XCTAssertTrue(cancelled.cancellationRequested)
    XCTAssertEqual(cancelled.checkpoints.single?.id, "before-side-effect")
    XCTAssertEqual(cancelled.checkpoints.single?.stateJson, #"{"step":2}"#)
    XCTAssertTrue(cancelled.eventJournal.contains { $0.kind == AgentTaskEventKinds.checkpoint })
    XCTAssertTrue(cancelled.eventJournal.contains {
      $0.kind == AgentTaskEventKinds.cancelled && $0.message == "user stopped task"
    })
    XCTAssertTrue(handle.cancellationSource.isCancellationRequested)
    XCTAssertTrue(supervisor.recoverableTasks().isEmpty)
  }

  func testRecoverableTasksResumeThroughHookFromDurableState() async throws {
    let store = InMemoryAgentWorkspaceStore()
    _ = try store.upsert(workspace("paused", status: .paused))
    _ = try store.upsert(workspace("running", status: .running))
    _ = try store.upsert(workspace("complete", status: .completed))
    let supervisor = AgentTaskSupervisor(workspaceStore: store)
    let resumed = AgentTaskSupervisorObserver()

    XCTAssertEqual(
      Set(supervisor.recoverableTasks().map(\.workspaceId)),
      Set(["workspace-paused", "workspace-running"])
    )

    let handles = try supervisor.resumeRecoverable { context, recovered in
      resumed.record(recovered)
      _ = try context.checkpoint(
        checkpointId: "resumed-\(recovered.taskId)",
        stateJson: #"{"resumed":true}"#
      )
    }
    for handle in handles {
      await handle.join()
    }
    await supervisor.shutdown()

    XCTAssertEqual(Set(resumed.snapshot().map(\.workspaceId)), Set(["workspace-paused", "workspace-running"]))
    for workspaceId in ["workspace-paused", "workspace-running"] {
      let workspace = try XCTUnwrap(store.find(workspaceId))
      XCTAssertEqual(workspace.status, .completed)
      XCTAssertTrue(workspace.eventJournal.contains { $0.kind == AgentTaskEventKinds.resumed })
      XCTAssertTrue(workspace.checkpoints.single?.stateJson.contains("resumed") == true)
    }
    XCTAssertEqual(store.find("workspace-complete")?.status, .completed)
  }

  func testWatchdogWarnsThenRequestsAssessmentExactlyOnce() throws {
    let clock = TestClock(start: 1_000)
    let store = InMemoryAgentWorkspaceStore(clock: clock.current)
    _ = try store.upsert(workspace("stalled", status: .running, createdAtMillis: 1_000))
    let signals = AgentTaskSupervisorSignals()
    let supervisor = AgentTaskSupervisor(
      workspaceStore: store,
      clock: clock.current,
      livenessPolicy: livenessPolicy(),
      livenessListener: { signals.record($0) }
    )

    clock.set(1_011)
    XCTAssertEqual(supervisor.sweepLiveness().map(\.kind), [.stalled])
    XCTAssertEqual(store.find("workspace-stalled")?.status, .running)

    clock.set(1_021)
    XCTAssertEqual(supervisor.sweepLiveness().map(\.kind), [.assessmentRequired])
    let assessing = try XCTUnwrap(store.find("workspace-stalled"))
    XCTAssertEqual(assessing.status, .running)
    XCTAssertTrue(assessing.eventJournal.contains { $0.kind == AgentTaskEventKinds.livenessAssessmentRequested })
    XCTAssertTrue(supervisor.sweepLiveness().isEmpty)
    XCTAssertEqual(signals.snapshot().map(\.kind), [.stalled, .assessmentRequired])
    supervisor.close()
  }

  func testLivenessAssessmentYieldsExecutionWithoutUserCancellation() async throws {
    let clock = TestClock(start: 1_000)
    let store = InMemoryAgentWorkspaceStore(clock: clock.current)
    let supervisor = AgentTaskSupervisor(
      workspaceStore: store,
      clock: clock.current,
      livenessPolicy: livenessPolicy()
    )
    let handle = try supervisor.submit(workspace("assessment", createdAtMillis: 1_000)) { _ in
      try await Task.sleep(nanoseconds: UInt64.max)
    }
    await Task.yield()

    clock.set(1_021)
    XCTAssertEqual(supervisor.sweepLiveness().map(\.kind), [.assessmentRequired])
    await handle.join()

    let yielded = try XCTUnwrap(store.find("workspace-assessment"))
    XCTAssertEqual(yielded.status, .paused)
    XCTAssertFalse(yielded.cancellationRequested)
    XCTAssertFalse(handle.cancellationSource.isCancellationRequested)
    XCTAssertTrue(handle.cancellationSource.isExecutionInterrupted)
    XCTAssertTrue(livenessPolicy().hasPendingAssessment(workspace: yielded))
    await supervisor.shutdown()
  }

  func testProgressAfterWarningPublishesRecoveredSignal() throws {
    let clock = TestClock(start: 1_000)
    let store = InMemoryAgentWorkspaceStore(clock: clock.current)
    _ = try store.upsert(workspace("recovered", status: .running, createdAtMillis: 1_000))
    let signals = AgentTaskSupervisorSignals()
    let supervisor = AgentTaskSupervisor(
      workspaceStore: store,
      clock: clock.current,
      livenessPolicy: livenessPolicy(),
      livenessListener: { signals.record($0) }
    )

    clock.set(1_011)
    _ = supervisor.sweepLiveness()
    clock.set(1_012)
    _ = try supervisor.progress(
      workspaceId: "workspace-recovered",
      stage: "tool.running",
      message: "Running tool"
    )

    XCTAssertEqual(signals.snapshot().map(\.kind), [.stalled, .recovered])
    let recovered = try XCTUnwrap(store.find("workspace-recovered"))
    XCTAssertFalse(livenessPolicy().hasUnresolvedStall(workspace: recovered))
    supervisor.close()
  }

  func testAuthenticatedLateConnectorResponseReopensOnlyItsFailedHandoff() throws {
    let store = InMemoryAgentWorkspaceStore()
    var failed = workspace("late", status: .failed)
    failed.handoffIds = ["codex:731"]
    failed.errorMessage = "Codex timed out"
    _ = try store.upsert(failed)
    let supervisor = AgentTaskSupervisor(workspaceStore: store)

    XCTAssertNil(supervisor.reconcileLateConnectorResponse(workspaceId: "workspace-late", sourceMessageId: 999))
    let recovered = try XCTUnwrap(supervisor.reconcileLateConnectorResponse(
      workspaceId: "workspace-late",
      sourceMessageId: 731
    ))

    XCTAssertEqual(recovered.status, .waitingResponse)
    XCTAssertEqual(recovered.errorMessage, "")
    XCTAssertEqual(recovered.eventJournal.last?.kind, AgentTaskEventKinds.lateResponse)
    supervisor.close()
  }

  private func workspace(
    _ suffix: String,
    status: AgentWorkspaceStatus = .created,
    createdAtMillis: Int64 = 0
  ) -> AgentWorkspace {
    AgentWorkspace(
      workspaceId: "workspace-\(suffix)",
      sessionId: "session-\(suffix)",
      conversationId: "conversation-\(suffix)",
      taskId: "task-\(suffix)",
      status: status,
      createdAtMillis: createdAtMillis
    )
  }

  private func livenessPolicy() -> AgentTaskLivenessPolicy {
    AgentTaskLivenessPolicy(
      queuedWarningMillis: 10,
      queuedTimeoutMillis: 20,
      runningWarningMillis: 10,
      runningTimeoutMillis: 20,
      waitingResponseWarningMillis: 10,
      waitingResponseTimeoutMillis: 20,
      absoluteTimeoutMillis: 1_000,
      watchdogIntervalMillis: 60_000,
      heartbeatWriteThrottleMillis: 0
    )
  }
}

private actor AgentTaskSupervisorProbe {
  private var running = 0
  private var maximum = 0
  private var startedIds: [String] = []
  private var releaseOpen = false
  private var startedWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private var idWaiters: [(String, CheckedContinuation<Void, Never>)] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func begin(_ id: String) {
    running += 1
    maximum = max(maximum, running)
    startedIds.append(id)
    resumeStartedWaiters()
  }

  func finish(_: String) {
    running = max(running - 1, 0)
  }

  func waitForStarted(count: Int) async {
    if startedIds.count >= count { return }
    await withCheckedContinuation { continuation in
      startedWaiters.append((count, continuation))
    }
  }

  func waitForStarted(id: String) async {
    if startedIds.contains(id) { return }
    await withCheckedContinuation { continuation in
      idWaiters.append((id, continuation))
    }
  }

  func waitForRelease() async {
    if releaseOpen { return }
    await withCheckedContinuation { continuation in
      releaseWaiters.append(continuation)
    }
  }

  func releaseAll() {
    releaseOpen = true
    let waiters = releaseWaiters
    releaseWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }

  func hasStarted(_ id: String) -> Bool {
    startedIds.contains(id)
  }

  func startedCount() -> Int {
    startedIds.count
  }

  func maximumRunning() -> Int {
    maximum
  }

  private func resumeStartedWaiters() {
    var remainingCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    for waiter in startedWaiters {
      if startedIds.count >= waiter.0 {
        waiter.1.resume()
      } else {
        remainingCountWaiters.append(waiter)
      }
    }
    startedWaiters = remainingCountWaiters

    var remainingIdWaiters: [(String, CheckedContinuation<Void, Never>)] = []
    for waiter in idWaiters {
      if startedIds.contains(waiter.0) {
        waiter.1.resume()
      } else {
        remainingIdWaiters.append(waiter)
      }
    }
    idWaiters = remainingIdWaiters
  }
}

private final class AgentTaskSupervisorObserver {
  private let lock = NSRecursiveLock()
  private var workspaces: [AgentWorkspace] = []

  func record(_ workspace: AgentWorkspace) {
    lock.lock()
    workspaces.append(workspace)
    lock.unlock()
  }

  func snapshot() -> [AgentWorkspace] {
    lock.lock()
    defer { lock.unlock() }
    return workspaces
  }
}

private final class AgentTaskSupervisorSignals {
  private let lock = NSRecursiveLock()
  private var signals: [AgentTaskLivenessSignal] = []

  func record(_ signal: AgentTaskLivenessSignal) {
    lock.lock()
    signals.append(signal)
    lock.unlock()
  }

  func snapshot() -> [AgentTaskLivenessSignal] {
    lock.lock()
    defer { lock.unlock() }
    return signals
  }
}

private final class TestClock {
  private let lock = NSRecursiveLock()
  private var value: Int64

  init(start: Int64) {
    self.value = start
  }

  func tick() -> Int64 {
    lock.lock()
    defer { lock.unlock() }
    value += 1
    return value
  }

  func current() -> Int64 {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func set(_ next: Int64) {
    lock.lock()
    value = next
    lock.unlock()
  }
}

private extension Array {
  var single: Element? {
    count == 1 ? first : nil
  }
}
