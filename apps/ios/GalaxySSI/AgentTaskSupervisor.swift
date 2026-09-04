import Foundation

enum AgentTaskLane: String, Codable, CaseIterable, Identifiable {
  case readReasoning = "READ_REASONING"
  case sideEffect = "SIDE_EFFECT"

  var id: String { rawValue }
}

enum AgentTaskPriority: String, Codable, CaseIterable, Identifiable {
  case foreground = "FOREGROUND"
  case normal = "NORMAL"
  case background = "BACKGROUND"

  var id: String { rawValue }
}

typealias AgentTaskResumeHook = (AgentTaskContext, AgentWorkspace) async throws -> Void
typealias AgentTaskLivenessListener = (AgentTaskLivenessSignal) -> Void

struct AgentTaskSupervisorError: LocalizedError, Equatable {
  var message: String
  var errorDescription: String? { message }
}

final class AgentTaskCancellationSource {
  private let lock = NSRecursiveLock()
  private let requestCancellation: (String) -> Bool
  private var requested = false
  private var interrupted = false
  private var completed = false
  private var executionCanceller: (() -> Void)?

  init(requestCancellation: @escaping (String) -> Bool) {
    self.requestCancellation = requestCancellation
  }

  var isCancellationRequested: Bool {
    synchronized { requested }
  }

  var isActive: Bool {
    synchronized { !completed }
  }

  var isExecutionInterrupted: Bool {
    synchronized { interrupted }
  }

  func cancel(reason: String = AgentTaskWorkspaceControlReducer.defaultCancelReason) -> Bool {
    requestCancellation(Self.reason(reason))
  }

  func throwIfCancellationRequested() throws {
    if isCancellationRequested {
      throw CancellationError()
    }
  }

  fileprivate func setExecutionCanceller(_ canceller: @escaping () -> Void) {
    synchronized {
      executionCanceller = canceller
    }
  }

  fileprivate func cancelExecution(reason _: String) {
    let canceller = synchronized { () -> (() -> Void)? in
      requested = true
      return executionCanceller
    }
    canceller?()
  }

  fileprivate func interruptExecution(reason _: String) {
    let canceller = synchronized { () -> (() -> Void)? in
      interrupted = true
      return executionCanceller
    }
    canceller?()
  }

  fileprivate func complete() {
    synchronized {
      completed = true
      executionCanceller = nil
    }
  }

  private static func reason(_ value: String) -> String {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? AgentTaskWorkspaceControlReducer.defaultCancelReason : clean
  }

  private func synchronized<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}

final class AgentTaskHandle {
  let workspaceId: String
  let taskId: String
  let lane: AgentTaskLane
  let priority: AgentTaskPriority
  let cancellationSource: AgentTaskCancellationSource
  let task: Task<Void, Never>

  fileprivate init(
    workspaceId: String,
    taskId: String,
    lane: AgentTaskLane,
    priority: AgentTaskPriority,
    cancellationSource: AgentTaskCancellationSource,
    task: Task<Void, Never>
  ) {
    self.workspaceId = workspaceId
    self.taskId = taskId
    self.lane = lane
    self.priority = priority
    self.cancellationSource = cancellationSource
    self.task = task
  }

  var isActive: Bool {
    cancellationSource.isActive && !task.isCancelled
  }

  func join() async {
    await task.value
  }

  func cancel(reason: String = AgentTaskWorkspaceControlReducer.defaultCancelReason) -> Bool {
    cancellationSource.cancel(reason: reason)
  }
}

final class AgentTaskContext {
  let workspaceKey: AgentWorkspaceKey
  let lane: AgentTaskLane
  let priority: AgentTaskPriority
  let cancellationSource: AgentTaskCancellationSource
  private let supervisor: AgentTaskSupervisor

  fileprivate init(
    workspaceKey: AgentWorkspaceKey,
    lane: AgentTaskLane,
    priority: AgentTaskPriority,
    cancellationSource: AgentTaskCancellationSource,
    supervisor: AgentTaskSupervisor
  ) {
    self.workspaceKey = workspaceKey
    self.lane = lane
    self.priority = priority
    self.cancellationSource = cancellationSource
    self.supervisor = supervisor
  }

  func workspace() throws -> AgentWorkspace {
    try supervisor.requireWorkspace(workspaceKey.workspaceId)
  }

  func appendEvent(
    kind: String,
    message: String = "",
    payloadJson: String = ""
  ) throws -> AgentWorkspace {
    try supervisor.appendEvent(
      workspaceId: workspaceKey.workspaceId,
      kind: kind,
      message: message,
      payloadJson: payloadJson
    )
  }

  func checkpoint(
    checkpointId: String,
    planSnapshot: String = "",
    stateJson: String = ""
  ) throws -> AgentWorkspace {
    try supervisor.checkpoint(
      workspaceId: workspaceKey.workspaceId,
      checkpointId: checkpointId,
      planSnapshot: planSnapshot,
      stateJson: stateJson
    )
  }

  func heartbeat(
    stage: String = "running",
    message: String = ""
  ) throws -> AgentWorkspace {
    try supervisor.heartbeat(
      workspaceId: workspaceKey.workspaceId,
      stage: stage,
      message: message
    )
  }

  func progress(
    stage: String,
    message: String = ""
  ) throws -> AgentWorkspace {
    try supervisor.progress(
      workspaceId: workspaceKey.workspaceId,
      stage: stage,
      message: message
    )
  }

  func transition(
    status: AgentWorkspaceStatus,
    eventKind: String? = nil,
    message: String = "",
    payloadJson: String = ""
  ) throws -> AgentWorkspace {
    try supervisor.transition(
      workspaceId: workspaceKey.workspaceId,
      status: status,
      eventKind: eventKind ?? "task.status.\(status.rawValue.lowercased())",
      message: message,
      payloadJson: payloadJson
    )
  }

  func recordExecutionSnapshot(_ snapshot: AgentWorkspaceExecutionSnapshot) throws -> AgentWorkspace {
    try supervisor.recordExecutionSnapshot(
      workspaceId: workspaceKey.workspaceId,
      snapshot: snapshot
    )
  }

  func ensureActive() throws {
    try cancellationSource.throwIfCancellationRequested()
    if Task.isCancelled {
      throw CancellationError()
    }
  }

  func waitForConfirmation(message: String = "") throws -> Never {
    try supervisor.deferTask(
      workspaceId: workspaceKey.workspaceId,
      status: .waitingConfirmation,
      eventKind: AgentTaskEventKinds.waitingConfirmation,
      message: message
    )
  }

  func waitForResponse(message: String = "") throws -> Never {
    try supervisor.deferTask(
      workspaceId: workspaceKey.workspaceId,
      status: .waitingResponse,
      eventKind: AgentTaskEventKinds.waitingResponse,
      message: message
    )
  }

  func pause(message: String = "") throws -> Never {
    try supervisor.deferTask(
      workspaceId: workspaceKey.workspaceId,
      status: .paused,
      eventKind: AgentTaskEventKinds.paused,
      message: message
    )
  }

  func blockTask(message: String = "") throws -> Never {
    try supervisor.deferTask(
      workspaceId: workspaceKey.workspaceId,
      status: .blocked,
      eventKind: AgentTaskEventKinds.blocked,
      message: message
    )
  }
}

final class AgentTaskSupervisor {
  private let workspaceStore: AgentWorkspaceStore
  private let readReasoningPermits: AgentTaskAsyncSemaphore
  private let backgroundReadReasoningPermits: AgentTaskAsyncSemaphore
  private let sideEffectPermits = AgentTaskAsyncSemaphore(1)
  private let clock: () -> Int64
  private let livenessPolicy: AgentTaskLivenessPolicy
  private let livenessListener: AgentTaskLivenessListener
  private let memoryObserver: (AgentWorkspace) -> Void
  private let storeMutationLock = NSRecursiveLock()
  private let stateLock = NSRecursiveLock()
  private var activeByWorkspace: [String: TaskControl] = [:]
  private var activeByTask: [String: TaskControl] = [:]
  private var closed = false
  private var watchdogTask: Task<Void, Never>?

  init(
    workspaceStore: AgentWorkspaceStore,
    maxConcurrentReadReasoningTasks: Int = AgentTaskSupervisor.defaultMaxReadReasoningTasks,
    clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
    livenessPolicy: AgentTaskLivenessPolicy = AgentTaskLivenessPolicy(),
    livenessListener: @escaping AgentTaskLivenessListener = { _ in },
    memoryObserver: @escaping (AgentWorkspace) -> Void = { _ in }
  ) {
    precondition(maxConcurrentReadReasoningTasks > 0, "maxConcurrentReadReasoningTasks must be positive")
    self.workspaceStore = workspaceStore
    self.readReasoningPermits = AgentTaskAsyncSemaphore(maxConcurrentReadReasoningTasks)
    self.backgroundReadReasoningPermits = AgentTaskAsyncSemaphore(max(maxConcurrentReadReasoningTasks - 1, 1))
    self.clock = clock
    self.livenessPolicy = livenessPolicy
    self.livenessListener = livenessListener
    self.memoryObserver = memoryObserver
    self.watchdogTask = Task { [weak self] in
      await self?.watchdogLoop()
    }
  }

  deinit {
    close()
  }

  var isActive: Bool {
    stateSynchronized { !closed }
  }

  func activeTaskIds() -> Set<String> {
    stateSynchronized { Set(activeByTask.keys) }
  }

  func activeWorkspaces() -> [AgentWorkspace] {
    let workspaceIds = stateSynchronized { Array(activeByWorkspace.keys) }
    return workspaceIds
      .compactMap(workspaceStore.find)
      .sorted {
        if $0.createdAtMillis != $1.createdAtMillis { return $0.createdAtMillis < $1.createdAtMillis }
        return $0.workspaceId < $1.workspaceId
      }
  }

  func cancellationSource(taskId: String) -> AgentTaskCancellationSource? {
    stateSynchronized {
      activeByTask[Self.clean(taskId)]?.cancellationSource
    }
  }

  func submit(
    workspace: AgentWorkspace,
    lane: AgentTaskLane = .readReasoning,
    priority: AgentTaskPriority = .normal,
    block: @escaping (AgentTaskContext) async throws -> Void
  ) throws -> AgentTaskHandle {
    try startTask(
      workspace: workspace,
      lane: lane,
      priority: priority,
      resumed: false,
      block: block
    )
  }

  func launch(
    workspace: AgentWorkspace,
    lane: AgentTaskLane = .readReasoning,
    priority: AgentTaskPriority = .normal,
    block: @escaping (AgentTaskContext) async throws -> Void
  ) throws -> AgentTaskHandle {
    try submit(workspace: workspace, lane: lane, priority: priority, block: block)
  }

  func recoverableTasks() -> [AgentWorkspace] {
    workspaceStore.recoverable()
  }

  func resume(
    workspaceId: String,
    lane: AgentTaskLane = .readReasoning,
    priority: AgentTaskPriority = .normal,
    hook: @escaping AgentTaskResumeHook
  ) throws -> AgentTaskHandle {
    let recovered = try requireWorkspace(workspaceId)
    guard !recovered.status.isTerminal, !recovered.cancellationRequested else {
      throw AgentTaskSupervisorError(message: "Workspace \(workspaceId) is not recoverable")
    }
    return try startTask(
      workspace: recovered,
      lane: lane,
      priority: priority,
      resumed: true
    ) { context in
      try await hook(context, recovered)
    }
  }

  func resumeRecoverable(
    laneSelector: (AgentWorkspace) -> AgentTaskLane = { _ in .readReasoning },
    prioritySelector: (AgentWorkspace) -> AgentTaskPriority = { _ in .normal },
    hook: @escaping AgentTaskResumeHook
  ) throws -> [AgentTaskHandle] {
    try recoverableTasks()
      .filter { controlForWorkspace($0.workspaceId) == nil }
      .map { workspace in
        try startTask(
          workspace: workspace,
          lane: laneSelector(workspace),
          priority: prioritySelector(workspace),
          resumed: true
        ) { context in
          try await hook(context, workspace)
        }
      }
  }

  func heartbeat(
    workspaceId: String,
    stage: String = "running",
    message: String = ""
  ) throws -> AgentWorkspace {
    try recordActivity(
      workspaceId: workspaceId,
      eventKind: AgentTaskEventKinds.heartbeat,
      stage: stage,
      message: message
    )
  }

  func progress(
    workspaceId: String,
    stage: String,
    message: String = ""
  ) throws -> AgentWorkspace {
    try recordActivity(
      workspaceId: workspaceId,
      eventKind: AgentTaskEventKinds.progress,
      stage: stage,
      message: message
    )
  }

  func sweepLiveness() -> [AgentTaskLivenessSignal] {
    let observedAt = now()
    return workspaceStore.recoverable().compactMap { workspace in
      let volatileActivity = controlForWorkspace(workspace.workspaceId)?.lastActivityAtMillis ?? 0
      return try? sweepWorkspace(
        workspaceId: workspace.workspaceId,
        observedAtMillis: observedAt,
        volatileActivityAtMillis: volatileActivity
      )
    }
  }

  func cancelTask(
    taskId: String,
    reason: String = AgentTaskWorkspaceControlReducer.defaultCancelReason
  ) -> Bool {
    let cleanTaskId = Self.clean(taskId)
    guard !cleanTaskId.isEmpty else { return false }
    if let active = stateSynchronized({ activeByTask[cleanTaskId] }) {
      return cancelWorkspace(workspaceId: active.workspaceId, reason: reason)
    }
    guard let workspace = workspaceStore.list().first(where: { $0.taskId == cleanTaskId }) else {
      return false
    }
    return cancelWorkspace(workspaceId: workspace.workspaceId, reason: reason)
  }

  func cancelWorkspace(
    workspaceId: String,
    reason: String = AgentTaskWorkspaceControlReducer.defaultCancelReason
  ) -> Bool {
    let cleanWorkspaceId = Self.clean(workspaceId)
    guard !cleanWorkspaceId.isEmpty else { return false }
    var changed = false
    var shouldCancelExecution = false
    var cancelReason = AgentTaskWorkspaceControlReducer.defaultCancelReason
    do {
      let found = try withMutationLock { () -> Bool in
        guard workspaceStore.find(cleanWorkspaceId) != nil else { return false }
        _ = try mutateWorkspaceLocked(cleanWorkspaceId) { current in
          let reduction = AgentTaskWorkspaceControlReducer.cancel(
            workspace: current,
            reason: reason,
            observedAtMillis: now()
          )
          changed = reduction.changed
          shouldCancelExecution = reduction.shouldCancelExecution
          if !reduction.cancelExecutionReason.isEmpty {
            cancelReason = reduction.cancelExecutionReason
          }
          return reduction.changed ? reduction.workspace : current
        }
        return true
      }
      guard found else { return false }
      if shouldCancelExecution {
        controlForWorkspace(cleanWorkspaceId)?.cancellationSource.cancelExecution(reason: cancelReason)
      }
      return changed
    } catch {
      return false
    }
  }

  func pauseForPermissionRevocation(
    workspaceId: String,
    reason: String = AgentTaskWorkspaceControlReducer.defaultPermissionRevokedReason
  ) -> Bool {
    let cleanWorkspaceId = Self.clean(workspaceId)
    guard !cleanWorkspaceId.isEmpty else { return false }
    var changed = false
    var shouldCancelExecution = false
    var cancelReason = AgentTaskWorkspaceControlReducer.defaultPermissionRevokedReason
    do {
      let found = try withMutationLock { () -> Bool in
        guard workspaceStore.find(cleanWorkspaceId) != nil else { return false }
        _ = try mutateWorkspaceLocked(cleanWorkspaceId) { current in
          let reduction = AgentTaskWorkspaceControlReducer.pauseForPermissionRevocation(
            workspace: current,
            reason: reason,
            observedAtMillis: now()
          )
          changed = reduction.changed
          shouldCancelExecution = reduction.shouldCancelExecution
          if !reduction.cancelExecutionReason.isEmpty {
            cancelReason = reduction.cancelExecutionReason
          }
          return reduction.changed ? reduction.workspace : current
        }
        return true
      }
      guard found else { return false }
      if shouldCancelExecution {
        controlForWorkspace(cleanWorkspaceId)?.cancellationSource.cancelExecution(reason: cancelReason)
      }
      return changed
    } catch {
      return false
    }
  }

  func appendEvent(
    workspaceId: String,
    kind: String,
    message: String = "",
    payloadJson: String = ""
  ) throws -> AgentWorkspace {
    try withMutationLock {
      try mutateWorkspaceLocked(workspaceId) { current in
        try appendEventCandidate(
          current: current,
          kind: kind,
          message: message,
          payloadJson: payloadJson
        )
      }
    }
  }

  func checkpoint(
    workspaceId: String,
    checkpointId: String,
    planSnapshot: String = "",
    stateJson: String = ""
  ) throws -> AgentWorkspace {
    try withMutationLock {
      let cleanCheckpointId = Self.clean(checkpointId)
      guard !cleanCheckpointId.isEmpty else {
        throw AgentTaskSupervisorError(message: "checkpointId must not be blank")
      }
      let observedAt = now()
      let withEvent = try mutateWorkspaceLocked(workspaceId) { current in
        try appendEventCandidate(
          current: current,
          kind: AgentTaskEventKinds.checkpoint,
          message: cleanCheckpointId,
          payloadJson: "",
          timestampMillis: observedAt
        )
      }
      guard let checkpointed = try workspaceStore.checkpoint(
        workspaceId: withEvent.workspaceId,
        checkpoint: AgentWorkspaceCheckpoint(
          id: cleanCheckpointId,
          eventSequence: withEvent.eventSequence,
          planSnapshot: planSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? withEvent.currentPlanSnapshot
            : planSnapshot,
          stateJson: stateJson,
          createdAtMillis: observedAt
        ),
        expectedRevision: withEvent.revision
      ) else {
        throw AgentTaskSupervisorError(message: "Agent workspace \(workspaceId) does not exist")
      }
      return checkpointed
    }
  }

  func recordExecutionSnapshot(
    workspaceId: String,
    snapshot: AgentWorkspaceExecutionSnapshot
  ) throws -> AgentWorkspace {
    let updated = try withMutationLock {
      try mutateWorkspaceLocked(workspaceId) { current in
        let reduction = AgentWorkspaceExecutionSnapshotReducer.apply(
          snapshot: snapshot,
          to: current,
          observedAtMillis: now()
        )
        return reduction.changed ? reduction.workspace : current
      }
    }
    notifyMemoryObserver(updated)
    return updated
  }

  func transition(
    workspaceId: String,
    status: AgentWorkspaceStatus,
    eventKind: String,
    message: String = "",
    payloadJson: String = ""
  ) throws -> AgentWorkspace {
    let updated = try withMutationLock {
      try mutateWorkspaceLocked(workspaceId) { current in
        try transitionCandidate(
          current: current,
          status: status,
          eventKind: eventKind,
          message: message,
          payloadJson: payloadJson,
          cancellationRequested: current.cancellationRequested || status == .cancelled
        )
      }
    }
    notifyMemoryObserver(updated)
    return updated
  }

  func reconcileLateConnectorResponse(
    workspaceId: String,
    sourceMessageId: Int64
  ) -> AgentWorkspace? {
    do {
      return try withMutationLock {
        guard sourceMessageId > 0 else { return nil }
        let cleanWorkspaceId = Self.clean(workspaceId)
        guard let current = workspaceStore.find(cleanWorkspaceId) else { return nil }
        if current.status != .failed || current.cancellationRequested {
          return current.cancellationRequested ? nil : current
        }
        let sourceSuffix = ":\(sourceMessageId)"
        let handoffMatches = current.handoffIds.contains { $0.hasSuffix(sourceSuffix) } ||
          current.remoteRunId == "\(sourceMessageId)"
        guard handoffMatches else { return nil }
        return try mutateWorkspaceLocked(cleanWorkspaceId) { latest in
          guard latest.status == .failed, !latest.cancellationRequested else {
            return latest
          }
          var updated = try appendEventCandidate(
            current: latest,
            kind: AgentTaskEventKinds.lateResponse,
            message: "Authenticated connector response received after local timeout",
            payloadJson: AgentMcpJSONCodec.stringify(["source_message_id": .int(sourceMessageId)])
          )
          updated.status = .waitingResponse
          updated.errorMessage = ""
          return updated
        }
      }
    } catch {
      return nil
    }
  }

  func close() {
    let controls = stateSynchronized { () -> [TaskControl] in
      guard !closed else { return [] }
      closed = true
      return Array(activeByWorkspace.values)
    }
    watchdogTask?.cancel()
    for control in controls {
      control.cancellationSource.cancelExecution(reason: "Agent task supervisor closed")
    }
    let readSemaphore = readReasoningPermits
    let backgroundSemaphore = backgroundReadReasoningPermits
    let sideEffectSemaphore = sideEffectPermits
    Task {
      await readSemaphore.releaseAllWaiters()
      await backgroundSemaphore.releaseAllWaiters()
      await sideEffectSemaphore.releaseAllWaiters()
    }
  }

  func shutdown() async {
    let tasks = stateSynchronized {
      activeByWorkspace.values.compactMap(\.executionTask)
    }
    close()
    await releaseLaneWaiters()
    for task in tasks {
      await task.value
    }
  }

  fileprivate func requireWorkspace(_ workspaceId: String) throws -> AgentWorkspace {
    let cleanWorkspaceId = Self.clean(workspaceId)
    guard !cleanWorkspaceId.isEmpty,
      let workspace = workspaceStore.find(cleanWorkspaceId) else {
      throw AgentTaskSupervisorError(message: "Agent workspace \(workspaceId) does not exist")
    }
    return workspace
  }

  fileprivate func deferTask(
    workspaceId: String,
    status: AgentWorkspaceStatus,
    eventKind: String,
    message: String
  ) throws -> Never {
    _ = try transition(
      workspaceId: workspaceId,
      status: status,
      eventKind: eventKind,
      message: message
    )
    throw AgentTaskDeferredError(status: status)
  }

  private func startTask(
    workspace: AgentWorkspace,
    lane: AgentTaskLane,
    priority: AgentTaskPriority,
    resumed: Bool,
    block: @escaping (AgentTaskContext) async throws -> Void
  ) throws -> AgentTaskHandle {
    guard isActive else {
      throw AgentTaskSupervisorError(message: "Agent task supervisor is closed")
    }
    var normalized = workspace
    normalized.workspaceId = Self.clean(workspace.workspaceId)
    normalized.sessionId = Self.clean(workspace.sessionId)
    normalized.conversationId = Self.clean(workspace.conversationId)
    normalized.taskId = Self.clean(workspace.taskId)
    guard !normalized.workspaceId.isEmpty else {
      throw AgentTaskSupervisorError(message: "workspaceId must not be blank")
    }
    guard !normalized.sessionId.isEmpty else {
      throw AgentTaskSupervisorError(message: "sessionId must not be blank")
    }
    guard !normalized.conversationId.isEmpty else {
      throw AgentTaskSupervisorError(message: "conversationId must not be blank")
    }
    guard !normalized.taskId.isEmpty else {
      throw AgentTaskSupervisorError(message: "taskId must not be blank")
    }

    let cancellationSource = AgentTaskCancellationSource { [weak self] reason in
      self?.cancelWorkspace(workspaceId: normalized.workspaceId, reason: reason) ?? false
    }
    let control = TaskControl(
      workspaceId: normalized.workspaceId,
      taskId: normalized.taskId,
      lane: lane,
      priority: priority,
      cancellationSource: cancellationSource
    )
    try reserve(control)

    let recoveringFromStall = workspaceStore.find(normalized.workspaceId)
      .map {
        livenessPolicy.hasUnresolvedStall(workspace: $0) ||
          livenessPolicy.hasPendingAssessment(workspace: $0)
      } ?? false
    let queued: AgentWorkspace
    do {
      queued = try queueWorkspace(normalized, resumed: resumed)
    } catch {
      release(control)
      throw error
    }
    notifyMemoryObserver(queued)
    control.lastActivityAtMillis = now()
    if recoveringFromStall {
      notifyLiveness(
        AgentTaskLivenessSignal(
          kind: .recovered,
          workspace: queued,
          reason: "task_resumed",
          observedAtMillis: now()
        )
      )
    }

    let context = AgentTaskContext(
      workspaceKey: queued.key,
      lane: lane,
      priority: priority,
      cancellationSource: cancellationSource,
      supervisor: self
    )
    let execution = Task { [weak self] in
      guard let self else { return }
      defer {
        if let workspace = self.workspaceStore.find(control.workspaceId) {
          self.notifyMemoryObserver(workspace)
        }
        self.release(control)
        cancellationSource.complete()
      }
      await self.runTask(control: control, context: context, block: block)
    }
    control.executionTask = execution
    cancellationSource.setExecutionCanceller {
      execution.cancel()
    }

    return AgentTaskHandle(
      workspaceId: queued.workspaceId,
      taskId: queued.taskId,
      lane: lane,
      priority: priority,
      cancellationSource: cancellationSource,
      task: execution
    )
  }

  private func queueWorkspace(_ workspace: AgentWorkspace, resumed: Bool) throws -> AgentWorkspace {
    try withMutationLock {
      if let existing = workspaceStore.find(workspace.workspaceId) {
        guard existing.key == workspace.key else {
          throw AgentTaskSupervisorError(message: "Agent workspace identity fields cannot change")
        }
        guard !existing.status.isTerminal, !existing.cancellationRequested else {
          throw AgentTaskSupervisorError(message: "Workspace \(workspace.workspaceId) is not recoverable")
        }
        return try mutateWorkspaceLocked(workspace.workspaceId) { current in
          try transitionCandidate(
            current: current,
            status: .queued,
            eventKind: resumed ? AgentTaskEventKinds.resumed : AgentTaskEventKinds.queued
          )
        }
      }
      guard !workspace.status.isTerminal, !workspace.cancellationRequested else {
        throw AgentTaskSupervisorError(message: "A new task workspace must be recoverable")
      }
      var insert = try transitionCandidate(
        current: workspace,
        status: .queued,
        eventKind: resumed ? AgentTaskEventKinds.resumed : AgentTaskEventKinds.queued
      )
      insert.revision = 0
      return try workspaceStore.upsert(insert, expectedRevision: 0)
    }
  }

  private func runTask(
    control: TaskControl,
    context: AgentTaskContext,
    block: @escaping (AgentTaskContext) async throws -> Void
  ) async {
    do {
      try await runInLane(lane: control.lane, priority: control.priority) {
        try context.ensureActive()
        _ = try transition(
          workspaceId: control.workspaceId,
          status: .running,
          eventKind: AgentTaskEventKinds.running
        )
        control.lastActivityAtMillis = now()
        try await block(context)
      }
      finishCompleted(control)
    } catch is AgentTaskDeferredError {
      return
    } catch is CancellationError {
      finishInterrupted(control)
    } catch {
      finishFailed(control, error)
    }
  }

  private func runInLane(
    lane: AgentTaskLane,
    priority: AgentTaskPriority,
    block: () async throws -> Void
  ) async throws {
    switch lane {
    case .readReasoning:
      if priority == .background {
        await backgroundReadReasoningPermits.acquire()
      }
      await readReasoningPermits.acquire()
      do {
        try await block()
        await readReasoningPermits.release()
        if priority == .background {
          await backgroundReadReasoningPermits.release()
        }
      } catch {
        await readReasoningPermits.release()
        if priority == .background {
          await backgroundReadReasoningPermits.release()
        }
        throw error
      }
    case .sideEffect:
      await sideEffectPermits.acquire()
      do {
        try await block()
        await sideEffectPermits.release()
      } catch {
        await sideEffectPermits.release()
        throw error
      }
    }
  }

  private func recordActivity(
    workspaceId: String,
    eventKind: String,
    stage: String,
    message: String
  ) throws -> AgentWorkspace {
    let observedAt = now()
    var pendingSignal: AgentTaskLivenessSignal?
    let updated = try withMutationLock {
      try mutateWorkspaceLocked(workspaceId) { current in
        let reduction = AgentTaskLivenessWorkspaceReducer.recordActivity(
          workspace: current,
          eventKind: eventKind,
          stage: stage,
          message: message,
          policy: livenessPolicy,
          observedAtMillis: observedAt
        )
        pendingSignal = reduction.signal
        return reduction.changed ? reduction.workspace : current
      }
    }
    controlForWorkspace(workspaceId)?.lastActivityAtMillis = observedAt
    if let signal = pendingSignal {
      notifyLiveness(AgentTaskLivenessSignal(
        kind: signal.kind,
        workspace: updated,
        reason: signal.reason,
        observedAtMillis: signal.observedAtMillis
      ))
    }
    return updated
  }

  private func sweepWorkspace(
    workspaceId: String,
    observedAtMillis: Int64,
    volatileActivityAtMillis: Int64
  ) throws -> AgentTaskLivenessSignal? {
    var pendingSignal: AgentTaskLivenessSignal?
    var cancelExecutionReason = ""
    let updated = try withMutationLock {
      try mutateWorkspaceLocked(workspaceId) { current in
        let reduction = AgentTaskLivenessWorkspaceReducer.sweep(
          workspace: current,
          policy: livenessPolicy,
          nowMillis: observedAtMillis,
          volatileActivityAtMillis: volatileActivityAtMillis
        )
        pendingSignal = reduction.signal
        cancelExecutionReason = reduction.cancelExecutionReason
        return reduction.changed ? reduction.workspace : current
      }
    }
    if !cancelExecutionReason.isEmpty {
      controlForWorkspace(workspaceId)?.cancellationSource.interruptExecution(reason: cancelExecutionReason)
    }
    guard let signal = pendingSignal else { return nil }
    let emitted = AgentTaskLivenessSignal(
      kind: signal.kind,
      workspace: updated,
      reason: signal.reason,
      observedAtMillis: signal.observedAtMillis
    )
    notifyLiveness(emitted)
    return emitted
  }

  private func finishCompleted(_ control: TaskControl) {
    try? withMutationLock {
      try mutateWorkspaceLocked(control.workspaceId) { current in
        if current.status.isTerminal {
          return current
        }
        if current.cancellationRequested {
          return try transitionCandidate(
            current: current,
            status: .cancelled,
            eventKind: AgentTaskEventKinds.cancelled,
            message: AgentTaskWorkspaceControlReducer.defaultCancelReason,
            cancellationRequested: true
          )
        }
        if Self.deferredStatuses.contains(current.status) {
          return current
        }
        return try transitionCandidate(
          current: current,
          status: .completed,
          eventKind: AgentTaskEventKinds.completed
        )
      }
    }
  }

  private func finishFailed(_ control: TaskControl, _ error: Error) {
    try? withMutationLock {
      try mutateWorkspaceLocked(control.workspaceId) { current in
        if current.status.isTerminal {
          return current
        }
        if current.cancellationRequested {
          return try transitionCandidate(
            current: current,
            status: .cancelled,
            eventKind: AgentTaskEventKinds.cancelled,
            message: AgentTaskWorkspaceControlReducer.defaultCancelReason,
            cancellationRequested: true
          )
        }
        return try transitionCandidate(
          current: current,
          status: .failed,
          eventKind: AgentTaskEventKinds.failed,
          message: Self.failureMessage(error)
        )
      }
    }
  }

  private func finishInterrupted(_ control: TaskControl) {
    try? withMutationLock {
      try mutateWorkspaceLocked(control.workspaceId) { current in
        if current.status.isTerminal {
          return current
        }
        if current.cancellationRequested || control.cancellationSource.isCancellationRequested {
          return try transitionCandidate(
            current: current,
            status: .cancelled,
            eventKind: AgentTaskEventKinds.cancelled,
            message: AgentTaskWorkspaceControlReducer.defaultCancelReason,
            cancellationRequested: true
          )
        }
        if Self.deferredStatuses.contains(current.status) {
          return current
        }
        return try transitionCandidate(
          current: current,
          status: .paused,
          eventKind: AgentTaskEventKinds.interrupted,
          message: "Task execution was interrupted"
        )
      }
    }
  }

  private func mutateWorkspaceLocked(
    _ workspaceId: String,
    mutation: (AgentWorkspace) throws -> AgentWorkspace
  ) throws -> AgentWorkspace {
    let cleanWorkspaceId = Self.clean(workspaceId)
    guard !cleanWorkspaceId.isEmpty else {
      throw AgentTaskSupervisorError(message: "workspaceId must not be blank")
    }
    var lastConflict: AgentWorkspaceRevisionConflictError?
    for _ in 0..<Self.maxStoreWriteAttempts {
      guard let current = workspaceStore.find(cleanWorkspaceId) else {
        throw AgentTaskSupervisorError(message: "Agent workspace \(workspaceId) does not exist")
      }
      var candidate = try mutation(current)
      if candidate == current {
        return current
      }
      candidate.revision = current.revision
      do {
        return try workspaceStore.upsert(candidate, expectedRevision: current.revision)
      } catch let conflict as AgentWorkspaceRevisionConflictError {
        lastConflict = conflict
      }
    }
    if let lastConflict {
      throw lastConflict
    }
    throw AgentTaskSupervisorError(message: "Agent workspace \(workspaceId) could not be updated")
  }

  private func transitionCandidate(
    current: AgentWorkspace,
    status: AgentWorkspaceStatus,
    eventKind: String,
    message: String = "",
    payloadJson: String = "",
    cancellationRequested: Bool? = nil
  ) throws -> AgentWorkspace {
    guard !current.status.isTerminal || current.status == status else {
      throw AgentTaskSupervisorError(
        message: "Terminal workspace \(current.workspaceId) cannot transition from \(current.status.rawValue) to \(status.rawValue)"
      )
    }
    var updated = try appendEventCandidate(
      current: current,
      kind: eventKind,
      message: message,
      payloadJson: payloadJson
    )
    updated.status = status
    updated.cancellationRequested = cancellationRequested ?? current.cancellationRequested
    return updated
  }

  private func appendEventCandidate(
    current: AgentWorkspace,
    kind: String,
    message: String,
    payloadJson: String,
    timestampMillis: Int64? = nil
  ) throws -> AgentWorkspace {
    let cleanKind = Self.clean(kind)
    guard !cleanKind.isEmpty else {
      throw AgentTaskSupervisorError(message: "event kind must not be blank")
    }
    guard current.eventSequence < Int64.max else {
      throw AgentTaskSupervisorError(message: "Agent workspace event sequence exhausted")
    }
    let timestamp = max(timestampMillis ?? now(), 0)
    let nextSequence = current.eventSequence + 1
    let event = AgentWorkspaceEvent(
      sequence: nextSequence,
      kind: cleanKind,
      message: message,
      payloadJson: payloadJson,
      timestampMillis: timestamp
    )
    var updated = current
    updated.eventSequence = nextSequence
    updated.eventJournal = Array((current.eventJournal + [event]).suffix(AgentWorkspaceBoundsPolicy.maxEvents))
    updated.updatedAtMillis = max(current.updatedAtMillis, timestamp)
    return updated
  }

  private func reserve(_ control: TaskControl) throws {
    try stateSynchronized {
      guard activeByWorkspace[control.workspaceId] == nil else {
        throw AgentTaskSupervisorError(message: "Workspace \(control.workspaceId) already has an active task")
      }
      guard activeByTask[control.taskId] == nil else {
        throw AgentTaskSupervisorError(message: "Task \(control.taskId) is already active")
      }
      if control.priority == .foreground {
        do {
          control.foregroundLease = try AgentForegroundWorkCoordinator.begin(taskId: control.taskId)
        } catch {
          throw error
        }
      }
      activeByWorkspace[control.workspaceId] = control
      activeByTask[control.taskId] = control
    }
  }

  private func release(_ control: TaskControl) {
    stateSynchronized {
      control.foregroundLease?.close()
      control.foregroundLease = nil
      if activeByWorkspace[control.workspaceId] === control {
        activeByWorkspace.removeValue(forKey: control.workspaceId)
      }
      if activeByTask[control.taskId] === control {
        activeByTask.removeValue(forKey: control.taskId)
      }
    }
  }

  private func controlForWorkspace(_ workspaceId: String) -> TaskControl? {
    stateSynchronized {
      activeByWorkspace[Self.clean(workspaceId)]
    }
  }

  private func notifyMemoryObserver(_ workspace: AgentWorkspace) {
    memoryObserver(workspace)
  }

  private func notifyLiveness(_ signal: AgentTaskLivenessSignal) {
    livenessListener(signal)
  }

  private func watchdogLoop() async {
    while isActive {
      let interval = UInt64(max(livenessPolicy.watchdogIntervalMillis, 1)) * 1_000_000
      do {
        try await Task.sleep(nanoseconds: interval)
      } catch {
        break
      }
      if Task.isCancelled {
        break
      }
      _ = sweepLiveness()
    }
  }

  private func releaseLaneWaiters() async {
    await readReasoningPermits.releaseAllWaiters()
    await backgroundReadReasoningPermits.releaseAllWaiters()
    await sideEffectPermits.releaseAllWaiters()
  }

  private func now() -> Int64 {
    max(clock(), 0)
  }

  private func withMutationLock<T>(_ body: () throws -> T) rethrows -> T {
    storeMutationLock.lock()
    defer { storeMutationLock.unlock() }
    return try body()
  }

  private func stateSynchronized<T>(_ body: () throws -> T) rethrows -> T {
    stateLock.lock()
    defer { stateLock.unlock() }
    return try body()
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func failureMessage(_ error: Error) -> String {
    if let localized = error as? LocalizedError,
      let description = localized.errorDescription,
      !clean(description).isEmpty {
      return description
    }
    let description = String(describing: error)
    return clean(description).isEmpty ? "Task failed" : description
  }

  static let defaultMaxReadReasoningTasks = 3
  private static let maxStoreWriteAttempts = 5
  private static let deferredStatuses: Set<AgentWorkspaceStatus> = [
    .waitingConfirmation,
    .waitingResponse,
    .paused,
    .blocked
  ]

  private final class TaskControl {
    let workspaceId: String
    let taskId: String
    let lane: AgentTaskLane
    let priority: AgentTaskPriority
    let cancellationSource: AgentTaskCancellationSource
    var foregroundLease: AgentForegroundWorkCoordinator.Lease?
    var executionTask: Task<Void, Never>?
    var lastActivityAtMillis: Int64 = 0

    init(
      workspaceId: String,
      taskId: String,
      lane: AgentTaskLane,
      priority: AgentTaskPriority,
      cancellationSource: AgentTaskCancellationSource
    ) {
      self.workspaceId = workspaceId
      self.taskId = taskId
      self.lane = lane
      self.priority = priority
      self.cancellationSource = cancellationSource
    }
  }

  private struct AgentTaskDeferredError: Error {
    var status: AgentWorkspaceStatus
  }
}

enum AgentForegroundWorkCoordinator {
  private static let lock = NSRecursiveLock()
  private static var activeTaskIds: Set<String> = []

  static var hasForegroundWork: Bool {
    synchronized { !activeTaskIds.isEmpty }
  }

  static var activeCount: Int {
    synchronized { activeTaskIds.count }
  }

  static func begin(taskId: String) throws -> Lease {
    let cleanTaskId = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTaskId.isEmpty else {
      throw AgentTaskSupervisorError(message: "Foreground task ID must not be blank")
    }
    return try synchronized {
      guard activeTaskIds.insert(cleanTaskId).inserted else {
        throw AgentTaskSupervisorError(message: "Foreground task \(cleanTaskId) is already active")
      }
      return Lease(taskId: cleanTaskId)
    }
  }

  final class Lease {
    private let taskId: String
    private var closed = false

    fileprivate init(taskId: String) {
      self.taskId = taskId
    }

    func close() {
      Self.synchronized {
        guard !closed else { return }
        closed = true
        AgentForegroundWorkCoordinator.activeTaskIds.remove(taskId)
      }
    }

    deinit {
      close()
    }

    private static func synchronized<T>(_ body: () -> T) -> T {
      AgentForegroundWorkCoordinator.synchronized(body)
    }
  }

  private static func synchronized<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}

private actor AgentTaskAsyncSemaphore {
  private var permits: Int
  private var waiters: [CheckedContinuation<Void, Never>] = []

  init(_ permits: Int) {
    self.permits = max(permits, 1)
  }

  func acquire() async {
    if permits > 0 {
      permits -= 1
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func release() {
    if waiters.isEmpty {
      permits += 1
    } else {
      waiters.removeFirst().resume()
    }
  }

  func releaseAllWaiters() {
    let pending = waiters
    waiters.removeAll()
    pending.forEach { $0.resume() }
  }
}
