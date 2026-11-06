import Foundation

enum AgentWorkspaceToolCallProjection {
  static func records(task: AgentTaskRecord, recovered: [AgentActionResult] = []) -> [AgentWorkspaceToolCallRecord] {
    let plan = task.activePlan
    let scope = AgentPlanContinuationScope(conversationId: task.sessionId, turnId: task.taskId)
    let extras = [task.lastCompletedNativeAction].compactMap { $0 } +
      task.pendingActions + [task.pendingAction].compactMap { $0 }
    let owned = ((plan?.actionHistory ?? []) + extras + (plan?.actions ?? [])).filter(scope.owns)
    let actions = AgentDurablePlanHistoryPolicy.latestSnapshots(owned)
    var observations: [String: AgentActionResult] = [:]
    if let last = task.lastNativeActionResult, actions.contains(where: { action in
      guard action.id == last.actionId else { return false }
      if action.status == .waitingResponse { return true }
      return !isOpenAction(action.status) && (action.status == .completed) == last.success
    }) {
      observations[last.actionId] = last
    }
    for result in recovered where !result.actionId.isBlank { observations[result.actionId] = result }
    return actions.compactMap { action in
      guard !action.id.isBlank, action.kind == .callNativeTool || action.kind == .callConnector else { return nil }
      return record(action, result: observations[action.id])
    }
  }

  static func merge(_ previous: [AgentWorkspaceToolCallRecord],
                    _ incoming: [AgentWorkspaceToolCallRecord]) -> [AgentWorkspaceToolCallRecord] {
    var order: [String] = []
    var indexed: [String: AgentWorkspaceToolCallRecord] = [:]
    for next in previous + incoming {
      guard let normalized = AgentWorkspaceBoundsPolicy.normalizeToolCallOrNil(next) else { continue }
      if let old = indexed[normalized.id] {
        indexed[normalized.id] = reconcile(old, normalized)
      } else {
        order.append(normalized.id)
        indexed[normalized.id] = normalized
      }
    }
    return order.compactMap { indexed[$0] }
  }

  private static func reconcile(_ old: AgentWorkspaceToolCallRecord,
                                _ next: AgentWorkspaceToolCallRecord) -> AgentWorkspaceToolCallRecord {
    guard old.toolName == next.toolName else { return next }
    let explicitStart = next.startedAtMillis > 0 && old.startedAtMillis > 0
    if explicitStart && next.startedAtMillis < old.startedAtMillis { return old }
    let sameAttempt = !explicitStart || old.startedAtMillis == next.startedAtMillis
    if sameAttempt && next.completedAtMillis > 0 && next.completedAtMillis < old.completedAtMillis { return old }
    if sameAttempt && isTerminal(old.status) && next.status == .pending { return old }
    var merged = next
    if merged.argumentsJson.isBlank { merged.argumentsJson = old.argumentsJson }
    if sameAttempt && old.status == next.status {
      if isSummary(merged.resultJson) && !isSummary(old.resultJson) { merged.resultJson = old.resultJson }
      if merged.errorMessage.isBlank { merged.errorMessage = old.errorMessage }
      if merged.startedAtMillis == 0 { merged.startedAtMillis = old.startedAtMillis }
      if merged.completedAtMillis == 0 { merged.completedAtMillis = old.completedAtMillis }
    } else if sameAttempt && !isTerminal(old.status) && isTerminal(next.status) &&
              merged.startedAtMillis == 0 &&
              (merged.completedAtMillis == 0 || merged.completedAtMillis >= old.startedAtMillis) {
      merged.startedAtMillis = old.startedAtMillis
    }
    return merged
  }

  private static func record(_ action: AgentAction, result: AgentActionResult?) -> AgentWorkspaceToolCallRecord {
    let metadata = result?.metadata ?? [:]
    let message = result?.message ?? action.result
    let evidence = (metadata["native_tool_output"] ?? "").ifBlank(metadata["evidence"] ?? "")
      .ifBlank(metadata["receipt"] ?? "").ifBlank(action.evidence)
    let tool = (action.parameters["tool_id"] ?? "").ifBlank(action.parameters["connector_id"] ?? "")
      .ifBlank(action.target).ifBlank(action.kind.rawValue.lowercased())
    let isArtifactExport = tool == AgentPhoneNativeToolCatalog.workspaceExport
    let output = decode(evidence).map {
      isArtifactExport ? AgentVerifiedArtifactSnapshot.omittingReviewText(in: $0) : $0
    }
    let statusName = (metadata["native_tool_status"] ?? "").ifBlank(metadata["native_status"] ?? "")
      .ifBlank(output?["status"]?.stringValue ?? "").lowercased()
    let unresolved = metadata["plan_node_outcome_unknown"] == "true" ||
      metadata["error_code"] == "effect_outcome_unknown" ||
      output?["code"]?.stringValue == "effect_outcome_unknown" ||
      ["unknown", "uncertain", "unverified"].contains(output?["outcome"]?.stringValue?.lowercased() ?? "")
    let status: AgentToolCallStatus
    if statusName == "cancelled" { status = .cancelled }
    else if unresolved || action.status == .waitingResponse || metadata["awaiting_response"] == "true" ||
              output?["awaiting_response"]?.boolValue == true { status = .running }
    else if let result { status = result.success ? .succeeded : .failed }
    else {
      switch action.status {
      case .proposed, .pendingConfirmation: status = .pending
      case .running, .waitingResponse: status = .running
      case .completed: status = .succeeded
      case .failed, .blocked, .rolledBack: status = .failed
      }
    }
    var fields = output ?? [:]
    if output == nil && !isArtifactExport && !evidence.isBlank && isTerminal(status) {
      fields["raw_evidence"] = .string(String(evidence.prefix(2_048)))
    }
    if fields["message"] == nil && !message.isBlank { fields["message"] = .string(String(message.prefix(1_024))) }
    if let invocation = metadata["native_receipt_id"]?.nilIfEmpty ?? metadata["invocation_id"]?.nilIfEmpty {
      fields["invocation_id"] = .string(String(invocation.prefix(256)))
    }
    if let code = metadata["error_code"]?.nilIfEmpty ?? metadata["plan_node_journal_error"]?.nilIfEmpty {
      fields["error_code"] = .string(String(code.prefix(128)))
    }
    if unresolved { fields["outcome_unverified"] = .bool(true) }
    let start = max(0, Int64(metadata["started_at_millis"] ?? "") ?? 0)
    let end = max(0, Int64(metadata["completed_at_millis"] ?? "") ?? 0)
    let id = action.id.count <= AgentWorkspaceBoundsPolicy.maxIdentifierCharacters ? action.id : GlobalAgentText.stableKey(action.id)
    let encoded = fields.isEmpty ? "" : AgentMcpJSONCodec.stringify(fields)
    let boundedOutput = encoded.count <= AgentWorkspaceBoundsPolicy.maxToolResultCharacters ? encoded :
      AgentMcpJSONCodec.stringify(["raw_evidence": .string(String(encoded.prefix(1_024))), "truncated": .bool(true)])
    return AgentWorkspaceToolCallRecord(
      id: id,
      toolName: tool,
      status: status,
      argumentsJson: action.parameters["input_json"] ?? "",
      resultJson: boundedOutput,
      errorMessage: status == .failed || status == .cancelled ? message : "",
      startedAtMillis: status == .pending ? 0 : start,
      completedAtMillis: isTerminal(status) && end > 0 ? max(start, end) : 0
    )
  }

  private static func isOpenAction(_ status: AgentActionStatus) -> Bool {
    [.proposed, .pendingConfirmation, .running, .waitingResponse].contains(status)
  }

  private static func isTerminal(_ status: AgentToolCallStatus) -> Bool {
    [.succeeded, .failed, .cancelled].contains(status)
  }

  private static func isSummary(_ json: String) -> Bool {
    json.isBlank || decode(json)?.keys.allSatisfy { $0 == "message" } == true
  }

  private static func decode(_ json: String) -> AgentMcpJSONObject? {
    guard !json.isBlank, json.utf8.count <= 64 * 1_024 else { return nil }
    return try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(json.utf8))
  }
}
