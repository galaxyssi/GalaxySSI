import Foundation

struct AgentPlanningRecoveryScope {
  let profile: String
  let task: AgentTaskRecord
  let source: ChatMessage
  let privateMode: Bool
  let sessionRequirement: String

  init?(profile: String, task: AgentTaskRecord, source: ChatMessage, conversation: AgentConversation?) {
    guard !profile.isBlank, task.phase == .planning, !task.blocked,
          source.isMine, !source.isSystem, !source.conversationId.isBlank,
          task.taskId == source.turnId.ifBlank(source.id.uuidString), task.sessionId == source.conversationId,
          let reference = task.pendingPlanning, !reference.inputSha256.isBlank,
          reference.sessionId == task.sessionId, reference.conversationId == task.sessionId,
          reference.turnId == task.taskId,
          let conversation, conversation.id == task.sessionId, conversation.status == .active,
          !conversation.trackingPaused, conversation.mergedIntoConversationId.isBlank else { return nil }
    if reference.isReplanning {
      guard task.activePlan?.planId == reference.basePlanId, task.activePlan?.revision == reference.baseRevision else { return nil }
    } else if task.activePlan != nil { return nil }
    self.profile = profile
    self.task = task
    self.source = source
    privateMode = conversation.privateMode
    sessionRequirement = conversation.sessionRequirement
  }

  func acceptsInput(_ input: AgentInitialPlanningInput) -> Bool {
    input.turnId == task.taskId && input.conversation.conversationId == task.sessionId &&
      input.conversation.privateMode == privateMode && !input.conversation.trackingPaused
  }

  func matches(profile: String, task: AgentTaskRecord?, source: ChatMessage?,
               conversation: AgentConversation?, cancelled: Bool) -> Bool {
    guard !cancelled, profile == self.profile, task == self.task, let source,
          let conversation, conversation.id == self.task.sessionId, conversation.status == .active,
          !conversation.trackingPaused, conversation.mergedIntoConversationId.isBlank,
          conversation.privateMode == privateMode, conversation.sessionRequirement == sessionRequirement else { return false }
    return source.id == self.source.id && source.contactId == self.source.contactId &&
      source.conversationId == self.source.conversationId && source.turnId == self.source.turnId &&
      source.isMine == self.source.isMine && source.isSystem == self.source.isSystem &&
      source.content == self.source.content && source.richOutputJson == self.source.richOutputJson &&
      source.voiceTranscript == self.source.voiceTranscript && source.readOnlyAnalysis == self.source.readOnlyAnalysis &&
      source.sourceConversationId == self.source.sourceConversationId
  }
}
