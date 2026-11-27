import Foundation

struct AgentNativeConnectorObservationExpiry {
  let pending: AgentActionResult
  let reason: String
  var missingResult: Bool { reason == "desktop_result_unavailable" }

  static func project(pending: AgentActionResult, managed: AgentManagedResponseRecord,
                      observation: AgentDesktopReplyRecoveryRecord, nowMillis: Int64) -> Self? {
    let binding = observation.binding
    guard !pending.actionId.isBlank, !managed.agentId.isBlank, managed.state == .pending, managed.response == nil,
          binding.isValid, binding.goalWork != true, binding.teamSource == nil,
          let owner = binding.managedSource,
          owner.ownerRunId == managed.ownerRunId, owner.sourceMessageId == managed.sourceMessageId,
          owner.executionGeneration == managed.executionGeneration,
          binding.contactId == managed.contactId, binding.identity.conversationId == managed.conversationId,
          binding.identity.turnId == managed.turnId, binding.identity.taskId == managed.taskId,
          pending.metadata["awaiting_response"] == "true",
          pending.metadata["control_plane_run_id"] == managed.ownerRunId,
          pending.metadata["control_plane_agent_id"] == managed.agentId,
          Int64(pending.metadata["source_message_id"] ?? "") == managed.sourceMessageId,
          pending.metadata["contact_id"] == managed.contactId,
          pending.metadata["conversation_id"] == managed.conversationId,
          pending.metadata["turn_id"] == managed.turnId, pending.metadata["task_id"] == managed.taskId,
          Int64(pending.metadata["execution_generation"] ?? "") == managed.executionGeneration,
          observation.generation == managed.executionGeneration ||
            (observation.generation == 0 && observation.sequence == -1 && observation.status.isEmpty),
          let reason = observation.expiryReason(now: nowMillis) else { return nil }
    let missing = reason == "desktop_result_unavailable"
    guard reason == "desktop_status_unavailable" || missing else { return nil }
    if missing {
      guard observation.generation == managed.executionGeneration, observation.sequence >= 0,
            observation.sequence <= 9_007_199_254_740_991,
            observation.lastResponseAt > 0, observation.lastResponseAt <= nowMillis,
            AgentRemoteOutcomePolicy.isTerminal(observation.status) else { return nil }
    }
    let clock = [reason, String(observation.generation), String(observation.sequence),
      String(observation.lastResponseAt), String(observation.terminalObservedAt)].joined(separator: "|")
    guard pending.metadata["native_connector_observation_expiry_clock"] != clock else { return nil }
    var updated = pending
    updated.metadata["native_connector_observation_overdue"] = "true"
    updated.metadata["native_connector_observation_expiry_reason"] = reason
    updated.metadata["native_connector_observation_expiry_clock"] = clock
    updated.metadata.merge(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: pending.metadata,
      nowMillis: nowMillis)) { _, latest in latest }
    if missing {
      updated.metadata["effect_outcome_unknown"] = "true"
      updated.metadata["non_retriable"] = "true"
      updated.metadata["error_code"] = "effect_outcome_unknown"
      updated.metadata["native_connector_dispatch_uncertain"] = "true"
      updated.metadata["evidence"] = AgentMcpJSONCodec.stringify([
        "outcome": .string("unknown"), "code": .string("effect_outcome_unknown"),
        "observed_failure": .bool(false), "terminal_failure": .bool(false),
        "delivery_failure": .string(reason)])
    }
    return .init(pending: updated, reason: reason)
  }
}
