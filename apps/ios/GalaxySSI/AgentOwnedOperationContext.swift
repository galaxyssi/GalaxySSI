import Foundation

enum AgentOwnedOperationContext {
  static let processId = UUID().uuidString

  static func wantsContext(request: String, priorGoal: String) -> Bool {
    guard !priorGoal.isBlank else { return false }
    let clean = request.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    return ["resume", "resume task", "resume the task", "\u{7e7c}\u{7e8c}"].contains(clean) ||
      AgentActiveTurnPolicy.decide(request: request, activeGoal: priorGoal).disposition == .steer
  }

  static func previousRequest(before outgoing: ChatMessage, in messages: [ChatMessage]) -> ChatMessage? {
    guard outgoing.isMine, !outgoing.isSystem, !outgoing.readOnlyAnalysis,
          outgoing.sourceConversationId.isBlank, !outgoing.conversationId.isBlank,
          let index = messages.firstIndex(where: { $0.id == outgoing.id && $0.conversationId == outgoing.conversationId }),
          let previous = messages[..<index].last(where: { $0.isMine && !$0.isSystem }),
          previous.conversationId == outgoing.conversationId, previous.sourceConversationId.isBlank,
          !previous.readOnlyAnalysis,
          previous.turnId.ifBlank(previous.id.uuidString) != outgoing.turnId.ifBlank(outgoing.id.uuidString)
    else { return nil }
    return previous
  }

  static func project(
    source: ChatMessage, task: AgentTaskRecord, run: AgentRecordedRun?,
    currentProcessId: String = processId
  ) -> AgentMcpJSONObject? {
    let turn = source.turnId.ifBlank(source.id.uuidString)
    guard source.isMine, !source.isSystem, source.sourceConversationId.isBlank, !source.readOnlyAnalysis,
          !source.conversationId.isBlank, task.taskId == turn, task.sessionId == source.conversationId,
          task.executionLocationTrusted, task.executionLocationKind == .phone,
          task.phase != .cancelled else { return nil }
    var context: AgentMcpJSONObject = [
      "source_turn_id": .string(turn), "source_session_id": .string(task.sessionId),
      "summary_only": .bool(true)
    ]
    func unknown(_ reason: String) -> AgentMcpJSONObject {
      var unavailable = context
      unavailable["status"] = .string("unknown")
      unavailable["execution_state_unavailable"] = .string(reason)
      return unavailable
    }
    let sourceMillis = Int64((source.createdAt.timeIntervalSince1970 * 1_000).rounded(.down))
    guard task.updatedAtMillis >= max(task.createdAtMillis, sourceMillis) else { return unknown("task_precedes_request") }
    guard let plan = task.activePlan else {
      if task.phase == .completed, task.planContext?.executionMode == .planOnly,
         task.pendingAction == nil, task.pendingActions.isEmpty, task.lastNativeActionResult == nil {
        context["status"] = .string("planned_not_executed")
        context["goal"] = .string(AgentPlannerObservation.sanitize(task.goal, maximumCharacters: 1_200))
        return context
      }
      return unknown("missing_plan")
    }
    let actions = plan.actionHistory + plan.actions
    let owner = AgentPlanContinuationScope(conversationId: source.conversationId, turnId: turn)
    guard !plan.planId.isBlank, task.planContext.map({ $0.planId == plan.planId && $0.revision == plan.revision }) ?? true,
          actions.allSatisfy(owner.owns),
          actions.contains(where: { $0.kind == .callNativeTool &&
            $0.parameters[AgentPlanContinuationScope.conversationIdKey] == owner.conversationId &&
            $0.parameters[AgentPlanContinuationScope.turnIdKey] == owner.turnId })
    else { return unknown("plan_scope_mismatch") }

    context["goal"] = .string(AgentPlannerObservation.sanitize(task.goal, maximumCharacters: 1_200))
    context["phase"] = .string(task.phase.rawValue.lowercased())
    context["observed_at"] = .int(task.updatedAtMillis)
    context["status"] = .string(status(task: task, source: source, plan: plan, run: run, processId: currentProcessId))
    if let requirements = plan.completionRequirements,
       let data = try? JSONEncoder().encode(requirements), data.count <= 2_000,
       let encoded = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data) {
      context["completion_requirements"] = .object(encoded)
    }
    if let result = task.lastNativeActionResult,
       actions.contains(where: { $0.id == result.actionId && belongs($0, to: task) }) {
      context["action_id"] = .string(String(result.actionId.prefix(128)))
    }
    return context
  }

  private static func status(
    task: AgentTaskRecord, source: ChatMessage, plan: AgentPlan, run: AgentRecordedRun?, processId: String
  ) -> String {
    if [.paused, .blocked, .failed].contains(task.phase) { return task.phase.rawValue.lowercased() }
    if task.phase == .waitingResponse, let permission = task.capturePermission, !permission.dispatched {
      guard permission.acceptsCallback(in: task, outgoing: source),
            let pending = task.pendingAction, belongs(pending, to: task),
            plan.actions.contains(where: { $0.id == pending.id }) else { return "unverified" }
      return task.localOperationProcessId == processId ? "waiting_permission" : "interrupted"
    }
    if [.planning, .executing, .observing, .verifying].contains(task.phase),
       task.localOperationProcessId != processId {
      return "interrupted"
    }
    if plan.executionMode == .planOnly { return "planned_not_executed" }
    guard task.phase == .completed else { return task.phase.rawValue.lowercased() }
    guard task.pendingPlanning == nil, task.pendingAction == nil, task.pendingActions.isEmpty,
          task.capturePermission == nil, (task.effectRecovery ?? []).isEmpty,
          let run, run.runId == task.taskId, run.conversationId == task.sessionId,
          run.taskThreadId == task.sessionId, run.createdAtMillis == task.createdAtMillis else { return "unverified" }
    if run.toolCalls.contains(where: { $0.result["outcome_unverified"] == .bool(true) }) { return "unverified" }
    if run.status == .running { return "finalizing" }
    guard run.status == .completed, run.completedAtMillis >= task.updatedAtMillis,
          !plan.actions.isEmpty, plan.actions.allSatisfy({ $0.status == .completed }),
          let last = task.lastNativeActionResult, last.success,
          last.metadata["execution_started"] != "false",
          last.metadata["business_success_verified"] != "false",
          last.metadata["plan_node_outcome_unknown"] != "true",
          last.metadata["native_tool_receipt_status"].map({ $0 == "succeeded" }) ?? true,
          let action = (plan.actionHistory + plan.actions).last(where: { $0.id == last.actionId }),
          action.kind == .callNativeTool, action.status == .completed, belongs(action, to: task),
          !AgentCompletionEvidencePolicy.hasUnverifiedOutcome(action),
          run.toolCalls.contains(where: { call in
            call.id == AgentRecordedExecutionEvidence.logicalID(action.id) &&
              call.toolName == String((action.parameters["tool_id"] ?? "").ifBlank(action.target).prefix(AgentSkillLimits.maxIdCharacters)) &&
              call.status == .succeeded && call.result["observed"] == .bool(true) &&
              call.result["success"] == .bool(true) && !explicitlyUnverified(call.result)
          })
    else { return "unverified" }
    return "completed"
  }

  private static func belongs(_ action: AgentAction, to task: AgentTaskRecord) -> Bool {
    action.parameters[AgentPlanContinuationScope.conversationIdKey] == task.sessionId &&
      action.parameters[AgentPlanContinuationScope.turnIdKey] == task.taskId
  }

  private static func explicitlyUnverified(_ value: AgentMcpJSONObject) -> Bool {
    let metadata = value["metadata"]?.objectValue
    return value["outcome_unverified"] == .bool(true) || value["execution_started"] == .bool(false) ||
      value["state_verified"] == .bool(false) || value["delivery_verified"] == .bool(false) ||
      metadata?.string("business_success_verified") == "false" ||
      metadata?.string("completion_verified") == "false" ||
      ["dispatched", "blocked", "unknown", "failed"].contains(metadata?.string("goal_status") ?? "") ||
      (value["output"]?.objectValue.map(explicitlyUnverified) ?? false)
  }
}
