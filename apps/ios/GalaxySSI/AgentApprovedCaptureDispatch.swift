import Foundation

enum AgentApprovedCaptureDispatch {
  struct Prepared {
    let task: AgentTaskRecord
    let node: AgentSequentialPlanNodeDispatch.Prepared
  }

  static func prepare(wait: AgentCapturePermissionContinuation, task: AgentTaskRecord,
    outgoing: ChatMessage, executionAction: AgentAction, screen: AgentScreenContext, nowMillis: Int64) -> Prepared? {
    guard nowMillis > 0, wait.acceptsCallback(in: task, outgoing: outgoing),
      let original = wait.action(in: task, outgoing: outgoing), task.activePlan?.executionMode != .planOnly,
      executionAction.id == original.id, executionAction.kind == original.kind,
      executionAction.target == original.target, AgentCapturePermissionContinuation.kind(for: executionAction) == wait.kind,
      executionAction.parameters["input_json"] == original.parameters["input_json"],
      executionAction.parameters["_galaxyssi_capture_permission_preflight"] == "true",
      executionAction.parameters["_galaxyssi_task_id"] == wait.taskId,
      executionAction.parameters["_galaxyssi_session_id"] == wait.sessionId,
      executionAction.parameters["_galaxyssi_conversation_id"] == wait.conversationId,
      executionAction.parameters["_galaxyssi_turn_id"] == wait.turnId,
      executionAction.parameters["_galaxyssi_contact_id"] == wait.contactId else { return nil }
    let plan = task.activePlan ?? AgentPlanFactory.singleAction(
      request: AgentPlanRequest(goal: task.goal, screen: screen), action: original)
    guard let node = AgentSequentialPlanNodeDispatch.prepare(plan: plan, action: executionAction, screen: screen,
        sessionId: task.sessionId.ifBlank(outgoing.conversationId), conversationId: outgoing.conversationId,
        turnId: outgoing.turnId.ifBlank(outgoing.id.uuidString)) else { return nil }
    var updated = task
    updated.activePlan = node.plan; updated.planContext = AgentTaskPlanContext(plan: node.plan)
    var dispatched = AgentCapturePermissionContinuation(task: updated, outgoing: outgoing, action: original,
      kind: wait.kind, permissionMode: wait.permissionMode)
    dispatched.token = wait.token
    dispatched.dispatched = true
    updated.capturePermission = dispatched
    updated.phase = .executing; updated.verification = "User-visible capture dispatch intent saved"
    updated.updatedAtMillis = nowMillis
    return Prepared(task: updated, node: node)
  }
}
