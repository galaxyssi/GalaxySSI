import XCTest

@testable import GalaxySSI

final class AgentTaskRuntimeTests: XCTestCase {
  override func tearDown() {
    AgentTaskRuntime.resetForTesting()
    AgentMemoryPssRuntime.configureForTesting(monitor: nil)
    super.tearDown()
  }

  func testSupervisorIsProcessLifetimeAndForwardsLivenessSignals() throws {
    let clock = TestRuntimeClock(start: 1_000)
    let store = InMemoryAgentWorkspaceStore(clock: clock.current)
    _ = try store.upsert(workspace("runtime", status: .running, createdAtMillis: 1_000))
    let signals = RuntimeLivenessSignals()
    let subscription = AgentTaskRuntime.addLivenessListener { signals.record($0) }

    let first = AgentTaskRuntime.supervisor(options: options(
      store: store,
      clock: clock.current,
      livenessPolicy: livenessPolicy()
    ))
    let second = AgentTaskRuntime.supervisor(options: options(
      store: InMemoryAgentWorkspaceStore(),
      clock: clock.current
    ))

    XCTAssertTrue(first === second)

    clock.set(1_011)
    XCTAssertEqual(first.sweepLiveness().map(\.kind), [.stalled])
    XCTAssertEqual(signals.snapshot().map(\.kind), [.stalled])

    XCTAssertTrue(AgentTaskRuntime.removeLivenessListener(subscription))
    clock.set(1_021)
    XCTAssertEqual(first.sweepLiveness().map(\.kind), [.assessmentRequired])
    XCTAssertEqual(signals.snapshot().map(\.kind), [.stalled])
  }

  func testRecoverableUsesSharedRuntimeSupervisorStore() throws {
    let store = InMemoryAgentWorkspaceStore(clock: { 2_000 })
    _ = try store.upsert(workspace("paused", status: .paused))
    _ = try store.upsert(workspace("completed", status: .completed))

    let recovered = AgentTaskRuntime.recoverable(options: options(store: store))

    XCTAssertEqual(recovered.map(\.workspaceId), ["workspace-paused"])
  }

  func testPhaseWorkspaceStatusMappingMatchesAndroidRuntime() {
    let cases: [(AgentPhase, AgentWorkspaceStatus)] = [
      (.observing, .running),
      (.planning, .running),
      (.executing, .running),
      (.verifying, .running),
      (.waitingConfirmation, .waitingConfirmation),
      (.waitingResponse, .waitingResponse),
      (.paused, .paused),
      (.blocked, .blocked),
      (.completed, .completed),
      (.failed, .failed),
      (.cancelled, .cancelled)
    ]

    for (phase, status) in cases {
      XCTAssertEqual(phase.toWorkspaceStatus(), status)
    }
  }

  private func options(
    store: AgentWorkspaceStore,
    clock: @escaping () -> Int64 = { 2_000 },
    livenessPolicy: AgentTaskLivenessPolicy = AgentTaskLivenessPolicy()
  ) -> AgentTaskRuntimeOptions {
    AgentTaskRuntimeOptions(
      workspaceStore: store,
      maxConcurrentReadReasoningTasks: 2,
      clock: clock,
      livenessPolicy: livenessPolicy,
      startMemoryTelemetry: false,
      memoryObserver: { _ in }
    )
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

private final class RuntimeLivenessSignals {
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

private final class TestRuntimeClock {
  private let lock = NSRecursiveLock()
  private var value: Int64

  init(start: Int64) {
    self.value = start
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
