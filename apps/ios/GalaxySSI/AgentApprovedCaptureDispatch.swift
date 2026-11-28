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
    let plan: AgentPlan
    if let active = task.activePlan { plan = active }
    else {
      let actions = task.pendingActions
      let scope = AgentPlanContinuationScope(conversationId: wait.conversationId, turnId: wait.turnId)
      guard task.planContext == nil, task.pendingPlanning == nil, !task.blocked,
        task.taskId == wait.turnId, task.sessionId == wait.conversationId,
        actions.first == original, Set(actions.map(\.id)).count == actions.count,
        actions.allSatisfy({ !$0.id.isBlank && [.callNativeTool, .callConnector].contains($0.kind) &&
          [.proposed, .pendingConfirmation].contains($0.status) && scope.owns($0) }) else { return nil }
      // Retain the queue without rewriting actions or approving their later execution.
      plan = AgentPlan(goal: task.goal, screen: screen, steps: [], actions: actions,
        selectedAgentOrModel: task.targetTitle, plannerProfile: "legacy-capture-dispatch")
    }
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
