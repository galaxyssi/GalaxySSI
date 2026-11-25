import Foundation

@MainActor
final class GalaxySSIHealthCareTaskRuntime {
  private final class WeakRuntime {
    weak var value: GalaxySSIHealthCareTaskRuntime?
    init(_ value: GalaxySSIHealthCareTaskRuntime) { self.value = value }
  }
  private static var runtimes: [String: WeakRuntime] = [:]
  private let records: GalaxySSIHealthRecords
  private let store: FileAgentWorkspaceStore
  private let supervisor: AgentTaskSupervisor
  private var handles: [String: AgentTaskHandle] = [:]

  static func shared(records: GalaxySSIHealthRecords) -> GalaxySSIHealthCareTaskRuntime {
    let key = records.owner + "\n" + GalaxySSIHealthCareTaskStore.fileURL(records: records).standardizedFileURL.path
    if let runtime = runtimes[key]?.value { return runtime }
    runtimes = runtimes.filter { $0.value.value != nil }
    let runtime = GalaxySSIHealthCareTaskRuntime(records: records)
    runtimes[key] = WeakRuntime(runtime)
    return runtime
  }

  private init(records: GalaxySSIHealthRecords) {
    self.records = records
    let store = GalaxySSIHealthCareTaskStore.make(records: records)
    self.store = store
    // Deliberately no global memory observer or transcript-progress projection.
    supervisor = AgentTaskSupervisor(workspaceStore: store, maxConcurrentReadReasoningTasks: 1)
  }

  deinit { supervisor.close() }

  func submit(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      operation: @escaping @MainActor (AgentTaskContext) async throws -> Void) throws -> AgentTaskHandle {
    let execution = try execution(approval)
    guard execution.state == .prepared else { throw GalaxySSIHealthRecords.Failure.stale }
    try records.validateLocalCareDiscussionTurn(approval)
    let workspace = workspace(approval, execution: execution)
    guard store.find(workspace.workspaceId) == nil else { throw GalaxySSIHealthRecords.Failure.stale }
    return track(try supervisor.submit(workspace: workspace, priority: .foreground) { [self] context in
      try await run(approval, context: context, operation: operation)
    })
  }

  func restore(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      mayApply: @escaping @MainActor () -> Bool,
      resumeRound: (@MainActor () async throws -> Void)? = nil) async throws {
    let id = identity(approval)
    // A second view must not create a second executor while the first one unwinds.
    if let active = handles[id] { await active.join() }
    try Task.checkCancellation()
    let execution = try execution(approval)
    let expected = workspace(approval, execution: execution)
    let persisted = store.find(id)
    if let persisted {
      guard persisted.key == expected.key else { throw GalaxySSIHealthRecords.Failure.stale }
      if persisted.cancellationRequested || persisted.status == .cancelled {
        try records.interruptLocalCareDiscussionExecution(approval)
        return
      }
      if persisted.status.isTerminal {
        guard persisted.status == .completed, execution.state == .applied else {
          throw GalaxySSIHealthRecords.Failure.stale
        }
        return
      }
      if execution.state == .interrupted && persisted.status == .blocked { return }
    }
    let operation: @MainActor (AgentTaskContext) async throws -> Void = { [self] _ in
      let current = try self.execution(approval)
      if current.state == .applied { return }
      if (current.state == .prepared || current.state == .dispatched),
         current.rounds?.canResume == true, mayApply(), let resumeRound {
        do { try await resumeRound() }
        catch is CancellationError { throw CancellationError() }
        catch {
          try? records.interruptLocalCareDiscussionExecution(approval)
          throw error
        }
        return
      }
      guard current.state == .received, mayApply() else {
        try records.interruptLocalCareDiscussionExecution(approval)
        return
      }
      do { try records.applySavedLocalCareDiscussionReply(approval) }
      catch {
        try? records.interruptLocalCareDiscussionExecution(approval)
        throw error
      }
    }
    let handle: AgentTaskHandle
    if persisted != nil {
      handle = try supervisor.resume(workspaceId: id, priority: .foreground) { [self] context, _ in
        try await run(approval, context: context, operation: operation)
      }
    } else {
      // Migrate final receipts saved before the supervised workspace existed; no dispatch.
      handle = try supervisor.submit(workspace: expected, priority: .foreground) { [self] context in
        try await run(approval, context: context, operation: operation)
      }
    }
    await track(handle).join()
    let final = try self.execution(approval)
    guard final.state == .applied || final.state == .interrupted else { throw GalaxySSIHealthRecords.Failure.unavailable }
  }

  func persistedWorkspace(_ approval: GalaxySSIHealthCareDiscussion.Approval) -> AgentWorkspace? {
    store.find(identity(approval))
  }

  func cancel(_ approval: GalaxySSIHealthCareDiscussion.Approval) -> Bool {
    let id = identity(approval)
    do {
      var cancelled = workspace(approval, execution: try execution(approval))
      if let persisted = store.find(id) {
        guard persisted.key == cancelled.key else { return false }
        return supervisor.cancelWorkspace(workspaceId: id, reason: "private_discussion_user_cancelled")
      }
      cancelled.status = .cancelled
      cancelled.cancellationRequested = true
      _ = try store.upsert(cancelled, expectedRevision: 0)
      return true
    } catch { return false }
  }

  private func run(_ approval: GalaxySSIHealthCareDiscussion.Approval, context: AgentTaskContext,
      operation: @escaping @MainActor (AgentTaskContext) async throws -> Void) async throws {
    try context.ensureActive()
    let heartbeat = Task {
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: 5_000_000_000)
          try Task.checkCancellation()
          _ = try context.heartbeat(stage: "private-discussion")
        } catch { return }
      }
    }
    defer { heartbeat.cancel() }
    do { try await operation(context) }
    catch is CancellationError { throw CancellationError() }
    catch {
      try context.ensureActive()
      try context.blockTask(message: "private_discussion_requires_review")
    }
    try context.ensureActive()
    guard try execution(approval).state == .applied else {
      try context.blockTask(message: "private_discussion_interrupted")
    }
  }

  private func track(_ handle: AgentTaskHandle) -> AgentTaskHandle {
    handles[handle.taskId] = handle
    Task { @MainActor [weak self] in
      await handle.join()
      if self?.handles[handle.taskId] === handle { self?.handles[handle.taskId] = nil }
    }
    return handle
  }

  private func execution(_ approval: GalaxySSIHealthCareDiscussion.Approval) throws -> GalaxySSIHealthCareDiscussionRecovery.Execution {
    let archive = try records.load()
    guard records.owner == approval.owner, let thread = archive.localCareDiscussions?[approval.concernID.uuidString],
          thread.id == approval.threadID, let turn = thread.turns.last, turn.id == approval.id,
          let execution = turn.execution, execution.approval == approval,
          execution.agentConversationID == thread.agentConversationID else { throw GalaxySSIHealthRecords.Failure.stale }
    return execution
  }

  private func identity(_ approval: GalaxySSIHealthCareDiscussion.Approval) -> String {
    "private:" + AgentModelLoopRecoveryIdentity.sha256(["owner": approval.owner,
      "thread": approval.threadID.uuidString, "turn": approval.id.uuidString])
  }

  private func workspace(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      execution: GalaxySSIHealthCareDiscussionRecovery.Execution) -> AgentWorkspace {
    let id = identity(approval)
    return AgentWorkspace(workspaceId: id, sessionId: approval.threadID.uuidString,
      conversationId: execution.agentConversationID ?? approval.threadID.uuidString, taskId: id,
      createdAtMillis: Int64(execution.startedAt.timeIntervalSince1970 * 1_000))
  }
}
