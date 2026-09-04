import Foundation

struct AgentTaskRuntimeOptions {
  var workspaceStore: AgentWorkspaceStore
  var maxConcurrentReadReasoningTasks: Int
  var clock: () -> Int64
  var livenessPolicy: AgentTaskLivenessPolicy
  var startMemoryTelemetry: Bool
  var memoryDefaults: UserDefaults
  var memoryObserver: (AgentWorkspace) -> Void

  init(
    workspaceStore: AgentWorkspaceStore = FileAgentWorkspaceStore(),
    maxConcurrentReadReasoningTasks: Int = AgentDeviceProfileDetector.detect().maxReadReasoningTasks,
    clock: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    },
    livenessPolicy: AgentTaskLivenessPolicy = AgentTaskLivenessPolicy(),
    startMemoryTelemetry: Bool = true,
    memoryDefaults: UserDefaults = .standard,
    memoryObserver: @escaping (AgentWorkspace) -> Void = {
      AgentMemoryPssRuntime.requestCapture(workspace: $0)
    }
  ) {
    self.workspaceStore = workspaceStore
    self.maxConcurrentReadReasoningTasks = max(1, maxConcurrentReadReasoningTasks)
    self.clock = clock
    self.livenessPolicy = livenessPolicy
    self.startMemoryTelemetry = startMemoryTelemetry
    self.memoryDefaults = memoryDefaults
    self.memoryObserver = memoryObserver
  }
}

struct AgentTaskLivenessSubscription: Hashable {
  fileprivate let id: UUID
}

enum AgentTaskRuntime {
  private static let lock = NSRecursiveLock()
  private static var supervisorInstance: AgentTaskSupervisor?
  private static var livenessListeners: [AgentTaskLivenessSubscription: AgentTaskLivenessListener] = [:]

  static func supervisor(options: AgentTaskRuntimeOptions = AgentTaskRuntimeOptions()) -> AgentTaskSupervisor {
    locked {
      if let existing = supervisorInstance {
        return existing
      }
      let created = AgentTaskSupervisor(
        workspaceStore: options.workspaceStore,
        maxConcurrentReadReasoningTasks: options.maxConcurrentReadReasoningTasks,
        clock: options.clock,
        livenessPolicy: options.livenessPolicy,
        livenessListener: publishLivenessSignal,
        memoryObserver: options.memoryObserver
      )
      if options.startMemoryTelemetry {
        AgentMemoryPssRuntime.start(
          defaults: options.memoryDefaults,
          activeWorkspaces: created.activeWorkspaces
        )
      }
      supervisorInstance = created
      return created
    }
  }

  static func recoverable(options: AgentTaskRuntimeOptions = AgentTaskRuntimeOptions()) -> [AgentWorkspace] {
    supervisor(options: options).recoverableTasks()
  }

  static func resumeLongRunningTasks(
    options: AgentTaskRuntimeOptions = AgentTaskRuntimeOptions(),
    session: (AgentWorkspace) -> AgentSessionSnapshot?,
    hook: @escaping (AgentTaskContext, AgentWorkspace, AgentLongTaskRecoveryDecision) async throws -> Void
  ) throws -> [AgentTaskHandle] {
    let supervisor = supervisor(options: options)
    let activeIds = Set(supervisor.activeWorkspaces().map(\.workspaceId))
    return try supervisor.recoverableTasks().compactMap { workspace in
      guard let decision = AgentLongTaskRecoveryPolicy.decide(
        workspace: workspace,
        session: session(workspace),
        activeWorkspaceIds: activeIds
      ),
      let claim = AgentLongTaskRecoveryClaims.tryAcquire(workspaceId: workspace.workspaceId) else {
        return nil
      }
      do {
        return try supervisor.resume(
          workspaceId: workspace.workspaceId,
          lane: .readReasoning,
          priority: .background
        ) { context, recovered in
          defer { claim.close() }
          try await hook(context, recovered, decision)
        }
      } catch {
        claim.close()
        throw error
      }
    }
  }

  @discardableResult
  static func addLivenessListener(_ listener: @escaping AgentTaskLivenessListener) -> AgentTaskLivenessSubscription {
    locked {
      let subscription = AgentTaskLivenessSubscription(id: UUID())
      livenessListeners[subscription] = listener
      return subscription
    }
  }

  @discardableResult
  static func removeLivenessListener(_ subscription: AgentTaskLivenessSubscription) -> Bool {
    locked {
      livenessListeners.removeValue(forKey: subscription) != nil
    }
  }

  static func resetForTesting() {
    let existing = locked { () -> AgentTaskSupervisor? in
      let current = supervisorInstance
      supervisorInstance = nil
      livenessListeners.removeAll()
      return current
    }
    existing?.close()
  }

  private static func publishLivenessSignal(_ signal: AgentTaskLivenessSignal) {
    let listeners = locked {
      Array(livenessListeners.values)
    }
    listeners.forEach { $0(signal) }
  }

  private static func locked<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}

extension AgentPhase {
  func toWorkspaceStatus() -> AgentWorkspaceStatus {
    switch self {
    case .observing, .planning, .executing, .verifying:
      return .running
    case .waitingConfirmation:
      return .waitingConfirmation
    case .waitingResponse:
      return .waitingResponse
    case .paused:
      return .paused
    case .blocked:
      return .blocked
    case .completed:
      return .completed
    case .failed:
      return .failed
    case .cancelled:
      return .cancelled
    }
  }
}
