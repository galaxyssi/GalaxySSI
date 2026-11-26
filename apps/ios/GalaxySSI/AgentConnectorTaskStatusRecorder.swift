import Foundation

struct AgentConnectorTaskStatusRecord: Equatable {
  var result: AgentActionResult
  var didApplyStatus: Bool
}

enum AgentConnectorTaskStatusRecorder {
  static func record(
    pending: AgentActionResult,
    envelope: AgentConnectorTerminalStatusEnvelope
  ) -> AgentConnectorTaskStatusRecord? {
    let normalizedStatus = AgentRemoteTaskStatusPolicy.normalize(envelope.taskStatus)
    guard !envelope.taskId.isEmpty, !normalizedStatus.isEmpty else {
      return nil
    }
    let previousSeq = Int64(pending.metadata["remote_task_status_seq"] ?? "") ?? -1
    if envelope.statusSeq > 0 && envelope.statusSeq < previousSeq {
      return AgentConnectorTaskStatusRecord(result: pending, didApplyStatus: false)
    }
    let now = envelope.nowMillis > 0 ? envelope.nowMillis : AgentControlPlaneClock.nowMillis()
    var metadata = pending.metadata
    metadata["remote_task_id"] = envelope.taskId
    metadata["remote_task_status"] = normalizedStatus
    metadata["remote_task_status_seq"] = String(max(previousSeq, envelope.statusSeq))
    metadata["remote_task_status_updated_at"] = String(now)
    return AgentConnectorTaskStatusRecord(
      result: AgentActionResult(
        actionId: pending.actionId,
        success: pending.success,
        message: pending.message,
        metadata: metadata
      ),
      didApplyStatus: true
    )
  }
}

// The caller must supply an already authenticated, durably accepted recovery observation.
enum AgentNativeConnectorStatusObservation {
  static func apply(pending: AgentActionResult, managed: AgentManagedResponseRecord,
                    observation: AgentDesktopReplyRecoveryRecord) -> AgentActionResult? {
    let binding = observation.binding
    guard !pending.actionId.isBlank, !managed.agentId.isBlank,
          binding.isValid, binding.goalWork != true, binding.teamSource == nil,
          let owner = binding.managedSource, managed.state == .pending, managed.response == nil,
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
          observation.generation == managed.executionGeneration, observation.sequence >= 0,
          observation.sequence <= 9_007_199_254_740_991,
          observation.lastResponseAt > 0, !observation.status.isBlank,
          !AgentRemoteOutcomePolicy.isTerminal(pending.metadata["remote_task_status"] ?? "") else { return nil }
    let previousSequence = pending.metadata["remote_task_status_seq"].flatMap(Int64.init) ?? -1
    guard pending.metadata["remote_task_status_seq"] == nil || previousSequence >= 0,
          observation.sequence > previousSequence else { return nil }
    if let raw = pending.metadata["remote_task_status_updated_at"] {
      guard let previousTime = Int64(raw), previousTime >= 0, observation.lastResponseAt >= previousTime else { return nil }
    }
    let envelope = AgentConnectorTerminalStatusEnvelope(sourceMessageId: managed.sourceMessageId,
      contactId: managed.contactId, taskId: managed.taskId, taskStatus: observation.status,
      statusSeq: observation.sequence, conversationId: managed.conversationId, turnId: managed.turnId,
      nowMillis: observation.lastResponseAt)
    guard var result = AgentConnectorTaskStatusRecorder.record(pending: pending, envelope: envelope)?.result else { return nil }
    // A known remote status is not a delivered result and never authorizes another execution.
    for key in ["native_connector_observation_overdue", "native_connector_observation_timeout_stage",
      "native_connector_observation_started_at", "native_connector_observation_elapsed_ms",
      "native_connector_observation_deadline_ms"] { result.metadata.removeValue(forKey: key) }
    return result
  }
}
