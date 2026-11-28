import Foundation

struct AgentPlanningRecoveryScope {
  enum Use { case startupRecovery, userReplan }
  let profile: String
  let task: AgentTaskRecord
  let source: ChatMessage
  let privateMode: Bool
  let trackingPaused: Bool
  let sessionRequirement: String

  init?(profile: String, task: AgentTaskRecord, source: ChatMessage, conversation: AgentConversation?,
        use: Use = .startupRecovery) {
    guard !profile.isBlank,
          source.isMine, !source.isSystem, !source.conversationId.isBlank,
          task.taskId == source.turnId.ifBlank(source.id.uuidString), task.sessionId == source.conversationId,
          let conversation, conversation.id == task.sessionId, conversation.status == .active,
          conversation.mergedIntoConversationId.isBlank else { return nil }
    switch use {
    case .startupRecovery:
      guard task.phase == .planning, !task.blocked, !conversation.trackingPaused else { return nil }
    case .userReplan:
      guard [.failed, .blocked, .planning].contains(task.phase) else { return nil }
    }
    if task.phase == .planning {
      guard let reference = task.pendingPlanning, !reference.inputSha256.isBlank,
            reference.sessionId == task.sessionId, reference.conversationId == task.sessionId,
            reference.turnId == task.taskId else { return nil }
      if reference.isReplanning {
        guard task.activePlan?.planId == reference.basePlanId, task.activePlan?.revision == reference.baseRevision else { return nil }
      } else if task.activePlan != nil { return nil }
    }
    self.profile = profile
    self.task = task
    self.source = source
    privateMode = conversation.privateMode
    trackingPaused = conversation.trackingPaused
    sessionRequirement = conversation.sessionRequirement
  }

  func acceptsInput(_ input: AgentInitialPlanningInput) -> Bool {
    input.turnId == task.taskId && input.conversation.conversationId == task.sessionId &&
      input.conversation.privateMode == privateMode && input.conversation.trackingPaused == trackingPaused
  }

  func matches(profile: String, task: AgentTaskRecord?, source: ChatMessage?,
               conversation: AgentConversation?, cancelled: Bool) -> Bool {
    guard !cancelled, profile == self.profile, task == self.task, let source,
          let conversation, conversation.id == self.task.sessionId, conversation.status == .active,
          conversation.trackingPaused == trackingPaused, conversation.mergedIntoConversationId.isBlank,
          conversation.privateMode == privateMode, conversation.sessionRequirement == sessionRequirement else { return false }
    return source.id == self.source.id && source.contactId == self.source.contactId &&
      source.conversationId == self.source.conversationId && source.turnId == self.source.turnId &&
      source.isMine == self.source.isMine && source.isSystem == self.source.isSystem &&
      source.content == self.source.content && source.richOutputJson == self.source.richOutputJson &&
      source.voiceTranscript == self.source.voiceTranscript && source.readOnlyAnalysis == self.source.readOnlyAnalysis &&
      source.sourceConversationId == self.source.sourceConversationId
  }
}
