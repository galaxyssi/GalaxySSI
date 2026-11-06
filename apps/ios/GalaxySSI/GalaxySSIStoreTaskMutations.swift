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
    upsertAgentTask(updated)
    return true
  }

  @discardableResult
  func upsertAgentTask(_ record: AgentTaskRecord) -> AgentTaskRecord {
    let clean = record.taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return record }
    var updated = record
    updated.taskId = clean
    var items = agentTaskRecords.filter { $0.taskId != clean }
    items.append(updated)
    agentTaskRecords = Array(Self.sortedAgentTasks(items).prefix(200))
    _ = UserDefaultsAgentSelfModelStore.shared.observe(task: updated)
    return updated
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
