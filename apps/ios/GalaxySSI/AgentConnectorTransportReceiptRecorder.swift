import Foundation

enum AgentConnectorTransportReceiptRecorder {
  static func canAcceptTransport(
    pending: AgentActionResult,
    sourceMessageId: Int64,
    contactId: String
  ) -> Bool {
    guard sourceMessageId > 0,
      pending.metadata["awaiting_response"] == "true",
      Int64(pending.metadata["source_message_id"] ?? "") == sourceMessageId else {
      return false
    }
    let expectedContactId = clean(pending.metadata["contact_id"] ?? "")
    let receivedContactId = clean(contactId)
    return expectedContactId.isEmpty || receivedContactId.isEmpty || expectedContactId == receivedContactId
  }

  static func recordAccepted(
    pending: AgentActionResult,
    sourceMessageId: Int64,
    contactId: String,
    nowMillis: Int64 = AgentControlPlaneClock.nowMillis()
  ) -> AgentActionResult? {
    guard canAcceptTransport(pending: pending, sourceMessageId: sourceMessageId, contactId: contactId) else {
      return nil
    }
    let now = nowMillis > 0 ? nowMillis : AgentControlPlaneClock.nowMillis()
    var metadata = pending.metadata
    let currentStatus = clean(metadata["remote_task_status"] ?? "")
    metadata["remote_task_status"] = currentStatus.isEmpty ? "accepted" : currentStatus
    metadata["remote_task_status_updated_at"] = String(now)
    metadata["transport_accepted_at"] = String(now)
    return AgentActionResult(
      actionId: pending.actionId,
      success: pending.success,
      message: pending.message,
      metadata: metadata
    )
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
