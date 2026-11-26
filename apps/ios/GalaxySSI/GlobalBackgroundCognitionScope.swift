import Foundation

struct GlobalBackgroundCognitionScope {
  let conversations: GlobalRealtimePlanningScope

  init(enabled: Bool, conversations: @autoclosure () -> [AgentConversation]) {
    self.conversations = GlobalRealtimePlanningScope(enabled: enabled, conversations: conversations())
  }

  func allowsSource(_ task: GlobalCognitionTask) -> Bool {
    guard conversations.canRead, task.sourceEvent.sensitivity != .sessionPrivate,
          !GlobalAgentEvidenceLifecyclePolicy.isInvalidatedState(task.lastError) else { return false }
    var ids = Set((task.sourceEvent.metadata["source_conversation_ids"] ?? "")
      .split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    let primary = task.sourceEvent.conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    let goalId = task.longHorizonGoalId
    if !goalId.isEmpty {
      guard task.sourceEvent.metadata["long_horizon_goal_id"] == goalId,
            task.sourceEvent.metadata["source_conversation_ids"] != nil else { return false }
    }
    let syntheticGoal = !goalId.isEmpty && primary == "global-goal:\(goalId)" &&
      task.sourceEvent.metadata["origin"] == "global_long_horizon_scheduler"
    if !primary.isEmpty && !syntheticGoal { ids.insert(primary) }
    return ids.isSubset(of: conversations.allowedConversationIds)
  }

  func allowsRunning(_ task: GlobalCognitionTask) -> Bool {
    guard allowsSource(task), !task.id.isEmpty, !task.resourceId.isEmpty,
          task.status == .running, task.sourceMessageId > 0,
          task.resourceTransport != nil, let contextIds = task.contextConversationIds else { return false }
    return contextIds.isSubset(of: conversations.allowedConversationIds)
  }

  func accepts(_ task: GlobalCognitionTask, request: GalaxySSIGlobalCognitionDispatchRequest) -> Bool {
    allowsRunning(task) && task.id == request.taskId && task.sourceMessageId == request.sourceMessageId &&
      task.resourceId == request.resourceId && task.resourceTransport == request.transport &&
      request.conversationId == "global-cognition:\(task.id)" && request.turnId == task.id &&
      request.contactId == (request.transport == .onDeviceModel ? "" : task.resourceId)
  }

  func accepts(_ task: GlobalCognitionTask, response: AgentConnectorResponse) -> Bool {
    allowsRunning(task) && task.sourceMessageId == response.sourceMessageId &&
      !task.resourceId.isEmpty && task.resourceId == response.contactId &&
      (response.conversationId.isEmpty || response.conversationId == "global-cognition:\(task.id)") &&
      (response.turnId.isEmpty || response.turnId == task.id) &&
      (response.taskId.isEmpty || response.taskId == task.id)
  }
}
