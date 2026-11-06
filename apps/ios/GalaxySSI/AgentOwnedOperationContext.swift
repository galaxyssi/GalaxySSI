import Foundation

enum AgentOwnedOperationContext {
  static let processId = UUID().uuidString

  static func wantsContext(request: String, priorGoal: String) -> Bool {
    guard !priorGoal.isBlank else { return false }
    return AgentActiveTurnPolicy.decide(request: request, activeGoal: priorGoal).disposition != .interrupt &&
      (AgentActiveTurnPolicy.hasExplicitContinuationLead(request) || bareContinuation(request) ||
       ["start", "begin", "execute", "\u{5f00}\u{59cb}", "\u{6267}\u{884c}"].contains(normalized(request)))
  }

  static func continuationSource(
    before outgoing: ChatMessage, in messages: [ChatMessage], hasTask: (ChatMessage) -> Bool
  ) -> ChatMessage? {
    var next = outgoing
    while let previous = previousRequest(before: next, in: messages) {
      if hasTask(previous) || !bareContinuation(previous.content) { return previous }
      next = previous
    }
    return nil
  }

  static func transcriptGoal(_ message: ChatMessage) -> AgentMcpJSONObject? {
    let goal = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !goal.isEmpty, !wantsContext(request: goal, priorGoal: "prior task"),
          AgentActiveTurnPolicy.decide(request: goal, activeGoal: "prior task").disposition != .interrupt else { return nil }
    let intent = AgentTaskIntentClassifier.classify(goal: goal)
    let requestsWork = goal.range(of: #"(?i)^(?:please\s+)?(?:create|write|edit|update|save|export|convert|generate|build|implement|fix|run|install|search|find|open|inspect|read)\b"#,
      options: .regularExpression) != nil ||
      ["\u{521b}\u{5efa}", "\u{751f}\u{6210}", "\u{5bfc}\u{51fa}", "\u{4fdd}\u{5b58}", "\u{7f16}\u{5199}",
       "\u{5b9e}\u{73b0}", "\u{67e5}\u{627e}", "\u{6253}\u{5f00}"].contains(where: goal.hasPrefix)
    let namesFile = goal.range(of: #"(?i)\b[\w.-]+\.(?:txt|md|json|png|jpg|jpeg|wav|mp4)\b"#,
      options: .regularExpression) != nil
    guard requestsWork, namesFile || [.file, .code, .phoneControl, .research].contains(intent.intent) else { return nil }
    return ["source_turn_id": .string(message.turnId.ifBlank(message.id.uuidString)),
      "source_session_id": .string(message.conversationId), "status": .string("goal_only"),
      "goal": .string(AgentPlannerObservation.sanitize(goal, maximumCharacters: 1_200)), "summary_only": .bool(true)]
  }

  private static func normalized(_ request: String) -> String {
    request.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
  }

  private static func bareContinuation(_ request: String) -> Bool {
    ["continue", "resume", "resume task", "resume the task", "keep going", "go on", "retry", "try again",
     "\u{7ee7}\u{7eed}", "\u{7e7c}\u{7e8c}", "\u{63a5}\u{7740}", "\u{91cd}\u{8bd5}", "\u{518d}\u{8bd5}\u{8bd5}"].contains(normalized(request))
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
