import Foundation

struct AgentConnectorTerminalStatusEnvelope: Equatable {
  var sourceMessageId: Int64
  var contactId: String
  var taskId: String
  var taskStatus: String
  var statusSeq: Int64
  var message: String
  var conversationId: String
  var turnId: String
  var nowMillis: Int64

  init(
    sourceMessageId: Int64,
    contactId: String,
    taskId: String,
    taskStatus: String,
    statusSeq: Int64,
    message: String = "",
    conversationId: String = "",
    turnId: String = "",
    nowMillis: Int64 = AgentControlPlaneClock.nowMillis()
  ) {
    self.sourceMessageId = sourceMessageId
    self.contactId = contactId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.taskId = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.taskStatus = taskStatus
    self.statusSeq = max(statusSeq, 0)
    self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
    self.conversationId = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.turnId = turnId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.nowMillis = max(nowMillis, 0)
  }
}

struct AgentConnectorTerminalStatusSettlement: Equatable {
  var result: AgentActionResult
  var eventType: AgentRunControlEventType?
  var eventPayload: AgentRunControlPayload
  var shouldDeactivateRun: Bool
}

enum AgentConnectorTerminalStatusResolver {
  static func canAccept(pending: AgentActionResult, envelope: AgentConnectorTerminalStatusEnvelope) -> Bool {
    guard envelope.sourceMessageId > 0,
      pending.metadata["awaiting_response"] == "true",
      Int64(pending.metadata["source_message_id"] ?? "") == envelope.sourceMessageId else {
      return false
    }
    let expectedContactId = clean(pending.metadata["contact_id"] ?? "")
    if !expectedContactId.isEmpty && !envelope.contactId.isEmpty && expectedContactId != envelope.contactId {
      return false
    }
    return AgentTaskIdentityPolicy.matchesDesktopResponse(
      expected: pending.metadata,
      conversationId: envelope.conversationId,
      taskId: envelope.taskId,
      turnId: envelope.turnId
    )
  }

  static func settle(
    pending: AgentActionResult,
    envelope: AgentConnectorTerminalStatusEnvelope
  ) -> AgentConnectorTerminalStatusSettlement? {
    let normalizedStatus = AgentRemoteTaskStatusPolicy.normalize(envelope.taskStatus)
    guard !envelope.taskId.isEmpty,
      AgentRemoteTaskStatusPolicy.settlesWithoutResponse(normalizedStatus) else {
      return nil
    }
    let previousSeq = Int64(pending.metadata["remote_task_status_seq"] ?? "") ?? -1
    if envelope.statusSeq > 0 && envelope.statusSeq < previousSeq {
      return AgentConnectorTerminalStatusSettlement(
        result: pending,
        eventType: nil,
        eventPayload: [:],
        shouldDeactivateRun: false
      )
    }
    let now = envelope.nowMillis > 0 ? envelope.nowMillis : AgentControlPlaneClock.nowMillis()
    let startedAt = Int64(pending.metadata["resource_started_at"] ?? "") ?? now
    let elapsedMillis = max(0, now - startedAt)
    let terminalMessage = envelope.message.isEmpty
      ? defaultMessage(status: normalizedStatus)
      : envelope.message
    var metadata = pending.metadata
    metadata["awaiting_response"] = "false"
    metadata["remote_task_id"] = envelope.taskId
    metadata["remote_task_status"] = normalizedStatus
    metadata["remote_task_status_seq"] = String(max(previousSeq, envelope.statusSeq))
    metadata["remote_task_status_updated_at"] = String(now)
    metadata["remote_task_terminal_at"] = String(now)
    let timeoutStage = AgentRemoteTaskStatusPolicy.timeoutStage(normalizedStatus)
    if !timeoutStage.isEmpty {
      metadata["timeout_stage"] = timeoutStage
      metadata["timeout_elapsed_ms"] = String(elapsedMillis)
    }
    let failed = AgentActionResult(
      actionId: pending.actionId,
      success: false,
      message: terminalMessage,
      metadata: metadata
    )
    return AgentConnectorTerminalStatusSettlement(
      result: failed,
      eventType: normalizedStatus == "cancelled" ? .runCancelled : .runFailed,
      eventPayload: [
        "message": .string(terminalMessage),
        "remote_task_id": .string(envelope.taskId),
        "remote_task_status": .string(normalizedStatus),
        "remote_task_status_seq": .int(max(previousSeq, envelope.statusSeq)),
        "source_message_id": .string(String(envelope.sourceMessageId))
      ],
      shouldDeactivateRun: true
    )
  }

  private static func defaultMessage(status: String) -> String {
    switch status {
    case "cancelled":
      return "The remote task was cancelled."
    case "timed_out":
      return "The remote task timed out."
    case "not_found":
      return "The remote task is no longer available."
    default:
      return "The remote task failed."
    }
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
