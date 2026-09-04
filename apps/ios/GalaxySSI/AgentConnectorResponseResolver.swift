import Foundation

struct AgentConnectorResponseSettlement: Equatable {
  var result: AgentActionResult
  var eventType: AgentRunControlEventType
  var eventPayload: AgentRunControlPayload
}

enum AgentConnectorResponseResolver {
  static func canAccept(
    pending: AgentActionResult,
    response: AgentConnectorResponse,
    managedIdentityVerified: Bool = false
  ) -> Bool {
    guard response.sourceMessageId > 0,
      pending.metadata["awaiting_response"] == "true",
      Int64(pending.metadata["source_message_id"] ?? "") == response.sourceMessageId else {
      return false
    }
    let expectedContactId = clean(pending.metadata["contact_id"] ?? "")
    if !managedIdentityVerified,
       !expectedContactId.isEmpty,
       !response.contactId.isEmpty,
       expectedContactId != response.contactId {
      return false
    }
    return AgentTaskIdentityPolicy.matchesDesktopResponse(
      expected: pending.metadata,
      conversationId: clean(response.conversationId),
      taskId: clean(response.taskId),
      turnId: clean(response.turnId)
    )
  }

  static func settle(
    pending: AgentActionResult,
    response: AgentConnectorResponse,
    managedIdentityVerified: Bool = false,
    nowMillis: Int64 = AgentControlPlaneClock.nowMillis()
  ) -> AgentConnectorResponseSettlement? {
    guard canAccept(
      pending: pending,
      response: response,
      managedIdentityVerified: managedIdentityVerified
    ) else {
      return nil
    }
    let now = nowMillis > 0 ? nowMillis : AgentControlPlaneClock.nowMillis()
    var metadata = pending.metadata
    metadata["awaiting_response"] = "false"
    metadata["response_received_at"] = String(now)
    metadata["connector_disposition"] = "response"
    if !response.conversationId.isEmpty {
      metadata["conversation_id"] = response.conversationId
    }
    if !response.turnId.isEmpty {
      metadata["turn_id"] = response.turnId
    }
    if !response.taskId.isEmpty {
      metadata["remote_task_id"] = response.taskId
    }
    if !response.richOutputJson.isEmpty {
      metadata["rich_output"] = response.richOutputJson
    }
    let result = AgentActionResult(
      actionId: pending.actionId,
      success: response.success,
      message: response.content,
      metadata: metadata
    )
    return AgentConnectorResponseSettlement(
      result: result,
      eventType: response.success ? .runCompleted : .runFailed,
      eventPayload: [
        "action_id": .string(pending.actionId),
        "source_message_id": .string(String(response.sourceMessageId)),
        "conversation_id": .string(response.conversationId),
        "turn_id": .string(response.turnId),
        "task_id": .string(response.taskId),
        "success": .bool(response.success),
        "result": .string(response.content),
        "error": .string(response.success ? "" : response.content)
      ]
    )
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
