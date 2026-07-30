import Foundation

struct AgentConnectorSteeredResult: Equatable {
  var result: AgentActionResult
  var eventPayload: AgentRunControlPayload
}

enum AgentConnectorSteeredResultResolver {
  static func canAccept(
    pending: AgentActionResult,
    sourceMessageId: Int64,
    contactId: String,
    conversationId: String,
    turnId: String,
    taskId: String
  ) -> Bool {
    guard AgentConnectorTransportReceiptRecorder.canAcceptTransport(
      pending: pending,
      sourceMessageId: sourceMessageId,
      contactId: contactId
    ) else {
      return false
    }
    return AgentTaskIdentityPolicy.matchesDesktopResponse(
      expected: pending.metadata,
      conversationId: clean(conversationId),
      taskId: clean(taskId),
      turnId: clean(turnId)
    )
  }

  static func resolve(
    pending: AgentActionResult,
    sourceMessageId: Int64,
    contactId: String,
    mergedIntoTaskId: String,
    conversationId: String = "",
    turnId: String = "",
    taskId: String = "",
    nowMillis: Int64 = AgentControlPlaneClock.nowMillis()
  ) -> AgentConnectorSteeredResult? {
    let mergedTask = clean(mergedIntoTaskId)
    guard !mergedTask.isEmpty,
      canAccept(
        pending: pending,
        sourceMessageId: sourceMessageId,
        contactId: contactId,
        conversationId: conversationId,
        turnId: turnId,
        taskId: taskId
      ) else {
      return nil
    }
    let now = nowMillis > 0 ? nowMillis : AgentControlPlaneClock.nowMillis()
    var metadata = pending.metadata
    metadata.removeValue(forKey: "timeout_stage")
    metadata.removeValue(forKey: "timeout_elapsed_ms")
    metadata["awaiting_response"] = "false"
    metadata["response_received_at"] = String(now)
    metadata["connector_disposition"] = "steered"
    metadata["merged_into_task_id"] = mergedTask
    let completed = AgentActionResult(
      actionId: pending.actionId,
      success: true,
      message: "",
      metadata: metadata
    )
    return AgentConnectorSteeredResult(
      result: completed,
      eventPayload: [
        "source_message_id": .string(String(sourceMessageId)),
        "connector_disposition": .string("steered"),
        "merged_into_task_id": .string(mergedTask)
      ]
    )
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
