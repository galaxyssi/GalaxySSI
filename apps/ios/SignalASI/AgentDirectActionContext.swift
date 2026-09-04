import Foundation

extension AgentAction {
  func withDirectConversationContext(
    request: AgentModelPlanningPromptRequest,
    executionMode: AgentTaskExecutionMode = .autoComplete
  ) -> AgentAction {
    let conversation = request.conversationContext.applyingGlobalContextDispatchPolicy(
      query: request.planRequest.goal,
      hasAttachments: request.hasAttachments
    )
    let turnId = conversation.turns.last?.turnId
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(id)
      ?? id
    var copy = self
    copy.parameters.merge([
      "_signalasi_conversation_id": conversation.conversationId,
      "_signalasi_conversation_context": conversation.asTransportBlock(
        maximumTokens: 10_000,
        includeGlobalContext: true
      ),
      "_signalasi_conversation_has_attachments": request.hasAttachments.description,
      "_signalasi_turn_id": turnId,
      "_signalasi_long_term_write_allowed": (!conversation.privateMode).description,
      "_signalasi_task_execution_mode": executionMode.rawValue,
      "_signalasi_task_id": turnId,
      "original_goal": String(request.planRequest.goal.prefix(500))
    ]) { _, new in new }
    return copy
  }
}

extension AgentPlan {
  func withDirectConversationContext(
    request: AgentModelPlanningPromptRequest,
    executionMode: AgentTaskExecutionMode = .autoComplete
  ) -> AgentPlan {
    var copy = self
    copy.actions = actions.map {
      $0.withDirectConversationContext(request: request, executionMode: executionMode)
    }
    return copy
  }
}
