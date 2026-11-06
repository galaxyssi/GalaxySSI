import Foundation

extension GalaxySSIStore {
  func commitAcceptedDesktopTask(_ binding: AgentDesktopReplyBinding, message: ChatMessage,
                                 acceptedAt: Int64) -> Bool {
    let taskIds = Set([binding.identity.taskId, binding.identity.turnId])
    let candidates = taskIds.compactMap { agentTask(id: $0) }.filter { $0.sessionId == binding.identity.conversationId }
    guard candidates.count == 1, let task = candidates.first else { return true }
    let verification = "Committed authenticated Desktop result"
    if task.phase == .completed && task.verification == verification && task.result == message.content {
      return save()
    }
    guard let next = Self.desktopTaskCompletion(task, binding: binding, message: message,
      acceptedAt: acceptedAt, verification: verification) else { return true }
    guard replaceAgentTaskForRecovery(expected: task, updated: next) else { return false }
    return save()
  }

  nonisolated static func desktopTaskCompletion(_ task: AgentTaskRecord, binding: AgentDesktopReplyBinding,
                                               message: ChatMessage, acceptedAt: Int64, verification: String)
    -> AgentTaskRecord? {
    guard task.sessionId == binding.identity.conversationId,
          [binding.identity.taskId, binding.identity.turnId].contains(task.taskId),
          task.routeKind == .desktopAgent, [.waitingResponse, .executing, .verifying].contains(task.phase),
          !task.blocked, task.planContext == nil, task.activePlan == nil, task.pendingPlanning == nil,
          task.pendingAction == nil, task.pendingActions.isEmpty,
          !message.isMine, !message.isSystem, message.contactId == binding.displayContactId,
          message.conversationId == task.sessionId, message.turnId == binding.identity.turnId,
          [.delivered, .read].contains(message.deliveryStatus)
    else { return nil }
    var completed = task
    completed.phase = .completed
    completed.result = message.content
    completed.verification = verification
    completed.updatedAtMillis = max(task.updatedAtMillis, acceptedAt)
    return completed
  }

  func replaceAgentTaskForRecovery(expected: AgentTaskRecord, updated: AgentTaskRecord) -> Bool {
    guard updated.taskId == expected.taskId, updated.sessionId == expected.sessionId,
          agentTask(id: expected.taskId) == expected else { return false }
    return upsertAgentTask(updated) == updated
  }

  func persistLocalWorkspaceCancellation(for task: AgentTaskRecord, at timestamp: Int64) -> Bool {
    for _ in 0..<3 {
      guard let current = agentWorkspaceStore.find(task.taskId),
            Self.isLocalWorkspace(current, for: task) else { return true }
      let cancellation = AgentTaskWorkspaceControlReducer.cancel(workspace: current, observedAtMillis: timestamp)
      guard cancellation.changed else { return cancellation.shouldCancelExecution }
      do {
        _ = try agentWorkspaceStore.upsert(cancellation.workspace, expectedRevision: current.revision)
        return true
      } catch is AgentWorkspaceRevisionConflictError {
        continue
      } catch {
        return false
      }
    }
    return false
  }

  func interruptedLocalWorkspaceCancellations() -> [AgentTaskRecord] {
    // The workspace is committed first; a crash can leave the task record at its old phase.
    let candidates = agentTaskRecords.filter { AgentTaskCenterPolicy.canRequestCancellation($0.phase) }
    guard !candidates.isEmpty else { return [] }
    let cancelled = Dictionary(uniqueKeysWithValues: agentWorkspaceStore.list().lazy
      .filter { $0.status == .cancelled && $0.cancellationRequested }.map { ($0.workspaceId, $0) })
    return candidates.filter { task in
      cancelled[task.taskId].map { Self.isLocalWorkspace($0, for: task) } ?? false
    }
  }

  private static func isLocalWorkspace(_ workspace: AgentWorkspace, for task: AgentTaskRecord) -> Bool {
    !task.sessionId.isBlank && workspace.workspaceId == task.taskId && workspace.taskId == task.taskId &&
      workspace.sessionId == task.sessionId && workspace.conversationId == task.sessionId &&
      workspace.parentRunId.isBlank && workspace.agentId.isBlank && workspace.deviceId.isBlank &&
      workspace.remoteRunId.isBlank && workspace.deliveryMode == AgentDeliveryMode.respond.rawValue
  }

  @discardableResult
  func upsertAgentTask(_ record: AgentTaskRecord, recoveredWorkspaceObservations: [AgentActionResult] = [],
                       explicitRollback: Bool = false) -> AgentTaskRecord {
    let clean = record.taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return record }
    var updated = record
    updated.taskId = clean
    let previous = agentTaskRecords.first { $0.taskId == clean && $0.sessionId == updated.sessionId }
    if let previous, previous.phase == .cancelled, updated.phase != .cancelled, !explicitRollback {
      return previous
    }
    var items = agentTaskRecords.filter { $0.taskId != clean }
    items.append(updated)
    agentTaskRecords = Array(Self.sortedAgentTasks(items).prefix(200))
    if previous != updated || !recoveredWorkspaceObservations.isEmpty {
      projectLocalToolWorkspace(updated, previous: previous, recovered: recoveredWorkspaceObservations)
    }
    _ = UserDefaultsAgentSelfModelStore.shared.observe(task: updated)
    return updated
  }

  private func projectLocalToolWorkspace(_ task: AgentTaskRecord, previous: AgentTaskRecord?, recovered: [AgentActionResult]) {
    guard task.routeKind == .localSystem,
          task.executionLocationKind == .phone || task.executionLocationKind == .unknown,
          !task.sessionId.isBlank,
          let session = agentSession(id: task.sessionId), !session.privateMode, !session.trackingPaused,
          session.mergedIntoConversationId.isBlank else { return }
    let calls = AgentWorkspaceToolCallProjection.records(task: task, recovered: recovered)
    let status: AgentWorkspaceStatus
    switch task.phase {
    case .observing, .planning: status = .queued
    case .executing, .verifying: status = .running
    case .waitingConfirmation: status = .waitingConfirmation
    case .waitingResponse: status = .waitingResponse
    case .paused: status = .paused
    case .blocked: status = .blocked
    case .cancelled: status = .cancelled
    case .completed:
      if !task.pendingActions.isEmpty { status = .running }
      else { status = calls.contains(where: { $0.status == .running }) ? .waitingResponse : .completed }
    case .failed: status = .failed
    }
    for _ in 0..<3 {
      let existing = agentWorkspaceStore.find(task.taskId)
      guard existing != nil || !calls.isEmpty else { return }
      var base = existing ?? AgentWorkspace(workspaceId: task.taskId, sessionId: task.sessionId,
        conversationId: task.sessionId, taskId: task.taskId, goal: task.goal, createdAtMillis: task.createdAtMillis)
      let last = base.eventJournal.last
      let sourceTimestamp = last?.kind == AgentTaskEventKinds.localToolProjection
        ? last?.timestampMillis ?? 0 : base.updatedAtMillis
      guard Self.isLocalWorkspace(base, for: task),
            sourceTimestamp <= task.updatedAtMillis, !base.cancellationRequested || status == .cancelled
      else { return }
      // An explicit local retry may reopen a failed workspace, but never one that was cancelled.
      if base.status == .failed && status != .failed && status != .cancelled && previous?.phase == .failed {
        base.status = status
      }
      let snapshot = AgentWorkspaceExecutionSnapshot(status: status, resultJson: base.resultJson, toolCalls: calls)
      var next = AgentWorkspaceExecutionSnapshotReducer.apply(snapshot: snapshot, to: base,
        observedAtMillis: task.updatedAtMillis).workspace
      if let existing, next.status == existing.status && next.toolCalls == existing.toolCalls &&
        next.cancellationRequested == existing.cancellationRequested { return }
      if next.eventJournal.last?.kind == AgentTaskEventKinds.snapshot {
        next.eventJournal[next.eventJournal.count - 1].kind = AgentTaskEventKinds.localToolProjection
      }
      do {
        _ = try agentWorkspaceStore.upsert(next, expectedRevision: existing?.revision ?? 0)
        return
      } catch is AgentWorkspaceRevisionConflictError {
        continue
      } catch {
        return
      }
    }
  }

  @discardableResult
  func deleteAgentTask(id taskId: String) -> Bool {
    let clean = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return false }
    let before = agentTaskRecords.count
    agentTaskRecords.removeAll { $0.taskId == clean }
    var deletedWorkspace = false
    for workspace in agentWorkspaceStore.list() where workspace.taskId == clean {
      if (try? agentWorkspaceStore.delete(workspace.workspaceId, expectedRevision: nil)) == true {
        deletedWorkspace = true
      }
    }
    if before == agentTaskRecords.count && !deletedWorkspace {
      return false
    }
    save()
    return true
  }

  @discardableResult
  func deleteAgentTasks(ids taskIds: Set<String>) -> Int {
    let cleanIds = Set(taskIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    guard !cleanIds.isEmpty else { return 0 }
    let before = agentTaskRecords.count
    agentTaskRecords.removeAll { cleanIds.contains($0.taskId) }
    var deleted = before - agentTaskRecords.count
    for workspace in agentWorkspaceStore.list() where cleanIds.contains(workspace.taskId) {
      if (try? agentWorkspaceStore.delete(workspace.workspaceId, expectedRevision: nil)) == true {
        deleted += 1
      }
    }
    if deleted > 0 {
      save()
    }
    return deleted
  }

  @discardableResult
  func rebindAgentTasks(sourceSessionId: String, targetSessionId: String) -> Int {
    let source = sourceSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    let target = targetSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !source.isEmpty, !target.isEmpty, source != target else { return 0 }
    var changed = 0
    agentTaskRecords = agentTaskRecords.map { record in
      guard record.sessionId == source else { return record }
      changed += 1
      var updated = record
      updated.sessionId = target
      return updated
    }
    return changed
  }
}
