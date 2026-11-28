import Foundation

struct AgentNativeConnectorRecoveryWake: Equatable {
  static let terminalDeliveryMillis: Int64 = 15 * 60_000
  let clock: String
  let delayMillis: Int64

  static func stage(metadata: [String: String], nowMillis: Int64, lastWakeMillis: Int64?) -> Self? {
    guard let wake = AgentNativeConnectorObservationWakePolicy.next(metadata: metadata,
      nowMillis: nowMillis, lastWakeMillis: lastWakeMillis) else { return nil }
    return .init(clock: wake.clock, delayMillis: wake.delayMillis)
  }

  static func terminalResult(pending: AgentActionResult, managed: AgentManagedResponseRecord,
      observation: AgentDesktopReplyRecoveryRecord, nowMillis: Int64, lastWakeMillis: Int64?) -> Self? {
    let binding = observation.binding
    guard nowMillis > 0, !pending.actionId.isBlank, pending.metadata["awaiting_response"] == "true",
      managed.state == .pending, managed.response == nil, binding.isValid,
      binding.goalWork != true, binding.teamSource == nil, binding.attemptSourceId == nil,
      let owner = binding.managedSource,
      owner.ownerRunId == managed.ownerRunId, owner.sourceMessageId == managed.sourceMessageId,
      owner.executionGeneration == managed.executionGeneration,
      binding.contactId == managed.contactId, binding.identity.conversationId == managed.conversationId,
      binding.identity.turnId == managed.turnId, binding.identity.taskId == managed.taskId,
      pending.metadata["control_plane_run_id"] == managed.ownerRunId,
      pending.metadata["control_plane_agent_id"] == managed.agentId,
      Int64(pending.metadata["source_message_id"] ?? "") == managed.sourceMessageId,
      pending.metadata["contact_id"] == managed.contactId,
      pending.metadata["conversation_id"] == managed.conversationId,
      pending.metadata["turn_id"] == managed.turnId, pending.metadata["task_id"] == managed.taskId,
      Int64(pending.metadata["execution_generation"] ?? "") == managed.executionGeneration,
      observation.generation == managed.executionGeneration, observation.sequence >= 0,
      observation.sequence <= 9_007_199_254_740_991,
      AgentRemoteOutcomePolicy.isTerminal(observation.status),
      AgentRemoteTaskStatusPolicy.normalize(pending.metadata["remote_task_status"] ?? "") == observation.status,
      Int64(pending.metadata["remote_task_status_seq"] ?? "") == observation.sequence,
      observation.acceptedReply == nil, observation.pinnedTeamReply == nil,
      observation.terminalObservedAt > 0, observation.terminalObservedAt <= nowMillis,
      observation.lastResponseAt >= observation.terminalObservedAt, observation.lastResponseAt <= nowMillis,
      let projectedAt = Int64(pending.metadata["remote_task_status_updated_at"] ?? ""),
      projectedAt >= observation.terminalObservedAt, projectedAt <= observation.lastResponseAt else { return nil }
    let remaining = AgentRemoteTaskStatusPolicy.remainingDeadlineMillis(deadlineMillis: terminalDeliveryMillis,
      startedAtMillis: observation.terminalObservedAt, nowMillis: nowMillis)
    let throttle: Int64
    if let lastWakeMillis {
      throttle = lastWakeMillis > 0 && nowMillis >= lastWakeMillis
        ? AgentRemoteTaskStatusPolicy.remainingDeadlineMillis(deadlineMillis: AgentDesktopReplyRecoveryRecord.probeInterval,
          startedAtMillis: lastWakeMillis, nowMillis: nowMillis)
        : AgentDesktopReplyRecoveryRecord.probeInterval
    } else { throttle = 0 }
    // A failed query or checked projection must not turn an expired record into a busy loop.
    return .init(clock: "terminal-result|\(observation.generation)|\(observation.sequence)|\(observation.terminalObservedAt)",
      delayMillis: remaining == 0 ? throttle : min(remaining, throttle))
  }
}
