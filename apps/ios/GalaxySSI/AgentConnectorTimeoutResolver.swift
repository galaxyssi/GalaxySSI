import Foundation

struct AgentConnectorTimeoutResolution: Equatable {
  var result: AgentActionResult
  var eventPayload: AgentRunControlPayload
  var shouldDeactivateRun: Bool
}

enum AgentConnectorTimeoutResolver {
  static func resolve(
    pending: AgentActionResult,
    sourceMessageId: Int64,
    stage: AgentConnectorTimeoutStage,
    nowMillis: Int64 = AgentControlPlaneClock.nowMillis()
  ) -> AgentConnectorTimeoutResolution? {
    guard AgentConnectorTransportReceiptRecorder.canAcceptTransport(
      pending: pending,
      sourceMessageId: sourceMessageId,
      contactId: ""
    ) else {
      return nil
    }
    let status = clean(pending.metadata["remote_task_status"] ?? "")
    let liveReadOnly = pending.metadata["routing_requires_live_data"] == "true"
    let hasFallback = !fallbackIds(pending.metadata["remaining_fallback_ids"] ?? "").isEmpty
    if AgentFailoverPolicy.shouldKeepOnlyResourceAlive(stage: stage, status: status, hasFallback: hasFallback) {
      return nil
    }
    guard AgentFailoverPolicy.shouldFailOver(stage: stage, status: status, liveReadOnly: liveReadOnly) else {
      return nil
    }
    if stage == .readOnlyStale && !hasFallback {
      return nil
    }
    let now = nowMillis > 0 ? nowMillis : AgentControlPlaneClock.nowMillis()
    let startedAt = Int64(pending.metadata["resource_started_at"] ?? "") ?? now
    let elapsedMillis = max(0, now - startedAt)
    let targetName = clean(pending.metadata["target"] ?? "").isEmpty
      ? "Selected resource"
      : clean(pending.metadata["target"] ?? "")
    let message = "\(targetName) timed out"
    var metadata = pending.metadata
    metadata["awaiting_response"] = "false"
    metadata["timeout_stage"] = stage.rawValue
    metadata["timeout_elapsed_ms"] = String(elapsedMillis)
    let failed = AgentActionResult(
      actionId: pending.actionId,
      success: false,
      message: message,
      metadata: metadata
    )
    return AgentConnectorTimeoutResolution(
      result: failed,
      eventPayload: [
        "message": .string(message),
        "source_message_id": .string(String(sourceMessageId)),
        "timeout_stage": .string(stage.rawValue),
        "timeout_elapsed_ms": .int(elapsedMillis)
      ],
      shouldDeactivateRun: true
    )
  }

  private static func fallbackIds(_ value: String) -> [String] {
    let ids = value
      .split(separator: ",")
      .map { clean(String($0)) }
      .filter { !$0.isEmpty }
    return stableDistinct(ids)
  }

  private static func stableDistinct(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
