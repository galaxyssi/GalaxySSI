import Foundation

enum AgentRecordedExecutionEvidence {
  struct Observation {
    let action: AgentAction
    let result: AgentActionResult
  }

  struct Projection {
    let plan: [AgentMcpJSONValue]
    let calls: [AgentToolCallRecord]
  }

  static func project(task: AgentTaskRecord, scope: AgentPlanContinuationScope,
                      previous: [AgentToolCallRecord], observations: [Observation],
                      now: Int64) -> Projection {
    let plan = task.activePlan
    let snapshots = AgentDurablePlanHistoryPolicy.latestSnapshots(
      ((plan?.actionHistory ?? []) + (plan?.actions ?? []) + task.pendingActions.filter { pending in
        plan?.actions.contains(where: { $0.id == pending.id }) != true
      }).filter { scope.owns($0) && !$0.id.isBlank }
    )
    let native = snapshots.filter(isTool)
    var actions = native
    var actual: [String: Observation] = [:]
    var ids = Set(native.map(\.id))
    for observation in observations where scope.owns(observation.action) &&
      !observation.action.id.isBlank && isTool(observation.action) &&
      observation.result.actionId == observation.action.id {
      actual[observation.action.id] = observation
      if ids.insert(observation.action.id).inserted { actions.append(observation.action) }
    }

    var prior = [String: AgentToolCallRecord]()
    var order: [String] = []
    for call in previous {
      if prior.updateValue(call, forKey: call.id) == nil { order.append(call.id) }
    }
    if let persisted = task.lastNativeActionResult, actual[persisted.actionId] == nil,
       prior[logicalID(persisted.actionId)]?.result["observed"]?.boolValue != true,
       let action = native.first(where: { $0.id == persisted.actionId &&
         [.completed, .failed, .blocked, .rolledBack].contains($0.status) }) {
      actual[action.id] = Observation(action: action, result: persisted)
    }
    for action in actions {
      let id = logicalID(action.id)
      if prior[id] == nil { order.append(id) }
      prior[id] = call(action, observed: actual[action.id], old: prior[id], now: now)
    }
    let planRows = snapshots.suffix(AgentLongTaskPersistenceLimits.maximumActions).map { action in
      AgentMcpJSONValue.object(["id": .string(logicalID(action.id)), "kind": .string(action.kind.rawValue),
                                "target": .string(String(action.target.prefix(AgentSkillLimits.maxIdCharacters)))])
    }
    return Projection(plan: planRows, calls: Array(order.compactMap { prior[$0] }.suffix(AgentSkillLimits.maxToolCalls)))
  }

  private static func call(_ action: AgentAction, observed: Observation?, old: AgentToolCallRecord?,
                           now: Int64) -> AgentToolCallRecord {
    let execution = observed?.action ?? action
    let receipt = observed?.result
    let metadata = receipt?.metadata ?? [:]
    let tool = (execution.parameters["tool_id"] ?? "").ifBlank(execution.parameters["connector_id"] ?? "")
      .ifBlank(execution.target).ifBlank(execution.kind.rawValue.lowercased())
    let raw = receipt == nil ? action.evidence :
      (metadata["native_tool_output"] ?? "").ifBlank(metadata["evidence"] ?? "").ifBlank(metadata["receipt"] ?? "")
    var evidence = jsonObject(raw, rawKey: "raw_evidence")
    if tool == AgentPhoneNativeToolCatalog.workspaceExport {
      evidence["raw_evidence"] = nil
      evidence = AgentVerifiedArtifactSnapshot.omittingReviewText(in: evidence)
    }
    let nativeStatus = (metadata["native_tool_status"] ?? "").ifBlank(metadata["native_status"] ?? "")
      .ifBlank(evidence["status"]?.stringValue ?? "").lowercased()
    let receiptID = (metadata["native_receipt_id"] ?? "").ifBlank(metadata["invocation_id"] ?? "")
    let explicitlyUndispatched = metadata["execution_started"] == "false" ||
      evidence["execution_started"]?.boolValue == false
    let unknown = metadata["plan_node_outcome_unknown"] == "true" ||
      metadata["error_code"] == "effect_outcome_unknown" ||
      ["unknown", "uncertain", "unverified"].contains(evidence["outcome"]?.stringValue?.lowercased() ?? "") ||
      evidence["code"]?.stringValue?.lowercased() == "effect_outcome_unknown"
    let status: AgentToolCallStatus
    if nativeStatus == "cancelled" {
      status = .cancelled
    } else if unknown {
      status = .running
    } else if let receipt {
      status = receipt.success ? .succeeded : .failed
    } else {
      switch action.status {
      case .proposed, .pendingConfirmation: status = .pending
      case .running, .waitingResponse: status = .running
      case .completed: status = .succeeded
      case .failed, .blocked: status = .failed
      case .rolledBack:
        status = raw.hasPrefix("superseded_by_plan_revision:") ? .pending : .failed
      }
    }
    let started = explicitlyUndispatched ? 0 : max(0, Int64(metadata["started_at_millis"] ?? "") ?? 0)
    let finished = max(0, Int64(metadata["completed_at_millis"] ?? "") ?? 0)
    let sameTool = old?.toolName == String(tool.prefix(AgentSkillLimits.maxIdCharacters))
    if let old, sameTool, receipt != nil,
       (started > 0 && old.startedAtMillis > started) || (finished > 0 && old.completedAtMillis > finished) {
      return old
    }

    // A later plan snapshot often has only a summary. Keep the exact receipt for the same state.
    if let old, sameTool, receipt == nil,
       (old.status == status || (old.status == .cancelled && status == .failed) ||
         (old.result["outcome_unverified"]?.boolValue == true && status == .failed)),
       old.result["observed"]?.boolValue == true {
      return old
    }

    let message = String((receipt?.message ?? action.result).prefix(2_000))
    var output: AgentMcpJSONObject = [:]
    if !message.isBlank { output["message"] = .string(message) }
    if !nativeStatus.isEmpty { output["status"] = .string(String(nativeStatus.prefix(64))) }
    if let receipt { output["observed"] = .bool(true); output["success"] = .bool(receipt.success && !unknown) }
    if explicitlyUndispatched { output["execution_started"] = .bool(false) }
    if unknown { output["outcome_unverified"] = .bool(true) }
    if !receiptID.isBlank { output["invocation_id"] = .string(String(receiptID.prefix(512))) }
    let code = (metadata["error_code"] ?? "").ifBlank(metadata["plan_node_journal_error"] ?? "")
    if !code.isBlank { output["error_code"] = .string(String(code.prefix(128))) }
    if let rawEvidence = evidence.removeValue(forKey: "raw_evidence") { output["raw_evidence"] = rawEvidence }
    if !evidence.isEmpty { output["output"] = .object(evidence) }

    let terminal = status == .succeeded || status == .failed || status == .cancelled
    let end: Int64
    if !terminal { end = 0 }
    else if finished > 0 { end = max(finished, started) }
    else if sameTool, old?.result == output, let old { end = old.completedAtMillis }
    else { end = receipt == nil ? 0 : max(now, started) }
    return AgentToolCallRecord(
      id: logicalID(action.id), toolName: tool, status: status,
      arguments: jsonObject(execution.parameters["input_json"] ?? "", rawKey: "raw_input"),
      result: output, errorMessage: status == .failed || status == .cancelled ? message : "",
      startedAtMillis: started, completedAtMillis: end
    )
  }

  static func missingLifecycle(for calls: [AgentToolCallRecord], events: [AgentRunControlEvent],
                               scope: AgentPlanContinuationScope) -> [AgentRunControlEvent] {
    guard let root = events.first, root.conversationId == scope.conversationId,
          root.turnId == scope.turnId else { return [] }
    return calls.flatMap { call -> [AgentRunControlEvent] in
      let terminal = call.status == .succeeded || call.status == .failed || call.status == .cancelled
      let candidates: [AgentRunControlEventType?] = [
        call.status != .pending && call.startedAtMillis > 0 && call.result["execution_started"]?.boolValue != false
          ? .toolStarted : nil,
        terminal && call.completedAtMillis > 0 ? .toolCompleted : nil
      ]
      return candidates.compactMap { candidate in
        guard let type = candidate else { return nil }
        let timestamp = type == .toolStarted ? call.startedAtMillis : call.completedAtMillis
        let invocation = call.result["invocation_id"]?.stringValue ?? ""
        guard !events.contains(where: { event in
          guard event.type == type, event.turnId == scope.turnId,
                AgentRunKernelContract.hasSameRoot(root, event),
                (!invocation.isEmpty && event.toolCallId == invocation) ||
                  (logicalID(event.stepId) == call.id && event.payload["tool_id"]?.stringValue == call.toolName)
          else { return false }
          guard event.timestampMillis >= call.startedAtMillis else { return false }
          if type == .toolStarted { return true }
          if call.startedAtMillis == 0 && event.timestampMillis < call.completedAtMillis { return false }
          return completionMatches(call.status, event.payload["status"]?.stringValue ?? "")
        }) else { return nil }
        var payload: AgentRunControlPayload = [
          "timeline_contract": .string(AgentRunTimelineContract.version), "timeline_kind": .string("tool"),
          "tool_id": .string(call.toolName), "timestamp_millis": .int(timestamp)
        ]
        if type == .toolCompleted { payload["status"] = .string(call.status.rawValue.lowercased()) }
        return AgentRunControlEvent(
          conversationId: root.conversationId, messageId: root.messageId, taskId: root.taskId,
          runId: root.runId, stepId: call.id, toolCallId: invocation.ifBlank(call.id),
          agentId: root.agentId, deviceId: root.deviceId, type: type, sequence: 0,
          timestampMillis: timestamp, payload: payload,
          idempotencyKey: "recorded-tool:\(call.id):\(invocation):\(type.rawValue):\(timestamp)",
          clientRouteId: root.clientRouteId, goalId: root.goalId, turnId: scope.turnId, actionId: call.id
        )
      }
    }
  }

  private static func completionMatches(_ status: AgentToolCallStatus, _ raw: String) -> Bool {
    switch status {
    case .succeeded: return ["succeeded", "success", "completed"].contains(raw.lowercased())
    case .failed: return ["failed", "verification_failed", "rejected", "unavailable", "timed_out"].contains(raw.lowercased())
    case .cancelled: return raw.lowercased() == "cancelled"
    case .pending, .running: return false
    }
  }

  private static func isTool(_ action: AgentAction) -> Bool {
    action.kind == .callNativeTool || action.kind == .callConnector
  }

  static func logicalID(_ id: String) -> String {
    let clean = id.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.count <= AgentSkillLimits.maxIdCharacters ? clean : GlobalAgentText.stableKey(clean)
  }

  private static func jsonObject(_ raw: String, rawKey: String) -> AgentMcpJSONObject {
    guard !raw.isBlank else { return [:] }
    if raw.utf8.count <= AgentSkillLimits.maxStepInputBytes,
       let object = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8)) {
      return object
    }
    return [rawKey: .string(String(raw.prefix(8_000)))]
  }
}
