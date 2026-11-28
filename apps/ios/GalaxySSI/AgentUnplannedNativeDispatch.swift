import Foundation

enum AgentUnplannedNativeDispatch {
  // This is an execution envelope for existing actions, not a planner or a consent grant.
  static func plan(task: AgentTaskRecord, action: AgentAction, outgoing: ChatMessage,
    screen: AgentScreenContext) -> AgentPlan? {
    if let plan = task.activePlan { return plan.executionMode == .planOnly ? nil : plan }
    let turn = outgoing.turnId.ifBlank(outgoing.id.uuidString)
    guard task.planContext == nil, task.pendingPlanning == nil,
      !task.blocked, [.planning, .executing, .waitingConfirmation].contains(task.phase),
      !outgoing.conversationId.isBlank, task.taskId == turn,
      task.sessionId == outgoing.conversationId,
      action.parameters["_galaxyssi_task_id"] == task.taskId,
      action.parameters["_galaxyssi_session_id"] == task.sessionId,
      action.parameters["_galaxyssi_conversation_id"] == outgoing.conversationId,
      action.parameters["_galaxyssi_turn_id"] == turn,
      action.parameters["_galaxyssi_contact_id"] == outgoing.contactId else { return nil }
    let remaining = task.pendingActions
    guard !remaining.contains(where: { $0.id == action.id }) else { return nil }
    let actions = [action] + remaining
    let scope = AgentPlanContinuationScope(conversationId: outgoing.conversationId, turnId: turn)
    guard Set(actions.map(\.id)).count == actions.count,
      actions.allSatisfy({ !$0.id.isBlank && [.callNativeTool, .callConnector].contains($0.kind) &&
        [.proposed, .pendingConfirmation].contains($0.status) && scope.owns($0) }) else { return nil }
    return AgentPlan(goal: task.goal, screen: screen, steps: [], actions: actions,
      selectedAgentOrModel: task.targetTitle, plannerProfile: "legacy-native-dispatch")
  }
}
