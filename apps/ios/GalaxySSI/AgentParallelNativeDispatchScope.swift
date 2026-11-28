import Foundation

struct AgentParallelNativeDispatchScope {
  let profile: String
  let task: AgentTaskRecord
  let source: ChatMessage

  init?(profile: String, task: AgentTaskRecord, source: ChatMessage, actions: [AgentAction],
        processId: String = AgentOwnedOperationContext.processId) {
    let turn = source.turnId.ifBlank(source.id.uuidString)
    let owner = AgentPlanContinuationScope(conversationId: source.conversationId, turnId: turn)
    guard !profile.isBlank, source.isMine, !source.isSystem, !source.conversationId.isBlank,
          task.taskId == turn, task.sessionId == source.conversationId,
          task.phase == .executing, !task.blocked, task.localOperationProcessId == processId,
          let plan = task.activePlan, plan.executionMode != .planOnly,
          actions.count > 1, Set(actions.map(\.id)).count == actions.count,
          actions.allSatisfy({ action in
            guard action.kind == .callNativeTool, owner.owns(action) else { return false }
            var running = action
            running.status = .running
            return plan.actions.contains(running)
          }) else { return nil }
    self.profile = profile
    self.task = task
    self.source = source
  }

  func matches(profile: String, task: AgentTaskRecord?, source: ChatMessage?, cancelled: Bool) -> Bool {
    guard !cancelled, profile == self.profile, task == self.task, let source else { return false }
    return source.id == self.source.id && source.contactId == self.source.contactId &&
      source.conversationId == self.source.conversationId && source.turnId == self.source.turnId &&
      source.isMine == self.source.isMine && source.isSystem == self.source.isSystem &&
      source.content == self.source.content && source.richOutputJson == self.source.richOutputJson &&
      source.voiceTranscript == self.source.voiceTranscript && source.readOnlyAnalysis == self.source.readOnlyAnalysis &&
      source.sourceConversationId == self.source.sourceConversationId
  }
}
