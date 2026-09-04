import Foundation

enum AgentNativeToolRunControlAdapter {
  static func controlEvent(
    from event: AgentNativeToolLifecycleEvent,
    runId: String,
    conversationId: String = "",
    messageId: String = "",
    taskId: String = "",
    agentId: String = "galaxyssi-mobile",
    deviceId: String = "",
    sequence: Int64? = nil
  ) -> AgentRunControlEvent {
    AgentRunControlEvent(
      conversationId: firstNonBlank(conversationId, event.conversationId),
      messageId: firstNonBlank(messageId, event.turnId, event.invocationId),
      taskId: firstNonBlank(taskId, event.turnId, runId),
      runId: runId,
      stepId: firstNonBlank(event.stepId, event.invocationId),
      toolCallId: event.invocationId,
      agentId: agentId,
      deviceId: deviceId,
      type: controlType(event.stage),
      sequence: max(sequence ?? event.sequence, 0),
      timestampMillis: event.timestampMillis,
      payload: payload(event)
    )
  }

  private static func controlType(_ stage: AgentNativeToolLifecycleStage) -> AgentRunControlEventType {
    switch stage {
    case .started:
      return .toolStarted
    case .progress:
      return .toolProgress
    case .finished:
      return .toolCompleted
    }
  }

  private static func payload(_ event: AgentNativeToolLifecycleEvent) -> AgentRunControlPayload {
    var payload: AgentRunControlPayload = [
      "timeline_contract": .string(AgentRunTimelineContract.version),
      "timeline_kind": .string(AgentRunTimelineKind.tool.payloadValue),
      "tool_id": .string(event.toolId),
      "timestamp_millis": .int(event.timestampMillis)
    ]
    if let status = event.status {
      payload["status"] = .string(status.rawValue)
    }
    if !event.progressStage.isEmpty {
      payload["progress_stage"] = .string(event.progressStage)
    }
    if !event.message.isEmpty {
      payload["message"] = .string(event.message)
    }
    if let percent = event.percent {
      payload["percent"] = .int(Int64(percent))
    }
    if event.sequence > 0 {
      payload["progress_sequence"] = .int(event.sequence)
    }
    return payload
  }

  private static func firstNonBlank(_ values: String...) -> String {
    values
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? ""
  }
}
