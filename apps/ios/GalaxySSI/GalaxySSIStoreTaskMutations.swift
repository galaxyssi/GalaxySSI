import Foundation

extension GalaxySSIStore {
  func replaceAgentTaskForRecovery(expected: AgentTaskRecord, updated: AgentTaskRecord) -> Bool {
    guard updated.taskId == expected.taskId, updated.sessionId == expected.sessionId,
          agentTask(id: expected.taskId) == expected else { return false }
    upsertAgentTask(updated)
    return true
  }

  @discardableResult
  func upsertAgentTask(_ record: AgentTaskRecord, recoveredWorkspaceObservations: [AgentActionResult] = []) -> AgentTaskRecord {
    let clean = record.taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return record }
    var updated = record
    updated.taskId = clean
    let previous = agentTaskRecords.first { $0.taskId == clean && $0.sessionId == updated.sessionId }
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
      guard base.taskId == task.taskId, base.sessionId == task.sessionId,
            base.conversationId == task.sessionId, base.parentRunId.isBlank,
            base.agentId.isBlank, base.deviceId.isBlank, base.remoteRunId.isBlank,
            base.deliveryMode == AgentDeliveryMode.respond.rawValue,
            sourceTimestamp <= task.updatedAtMillis, !base.cancellationRequested || status == .cancelled
      else { return }
      // An explicit local retry may reopen a failed workspace, but never one that was cancelled.
      if base.status == .failed && status != .failed && status != .cancelled && previous?.phase == .failed {
        base.status = status
      }
      let snapshot = AgentWorkspaceExecutionSnapshot(status: status, resultJson: base.resultJson, toolCalls: calls)
      var next = AgentWorkspaceExecutionSnapshotReducer.apply(snapshot: snapshot, to: base,
        observedAtMillis: task.updatedAtMillis).workspace
      if let existing, next.status == existing.status && next.toolCalls == existing.toolCalls { return }
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
