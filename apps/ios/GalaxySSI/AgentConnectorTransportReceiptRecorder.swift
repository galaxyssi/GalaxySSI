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

// Only the authenticated, durably journaled message-delivery completion may call this policy.
enum AgentNativeConnectorTransportAcceptance {
  static func apply(action: AgentAction, pending: AgentActionResult, managed: AgentManagedResponseRecord,
    event: MqttDeliveryCompletions.Event, taskIdentity: AgentTaskIdentity,
    expectedIdentity: MqttBusinessIdentity, expectedTopic: String, expectedRouteID: String) throws -> AgentActionResult? {
    try expectedIdentity.validate()
    guard let dispatch = AgentIOSConnectorDispatch(action: action, receipt: pending),
          dispatch.sourceMessageId <= 9_007_199_254_740_991,
          event.isPending, event.identity == expectedIdentity, event.topic == expectedTopic,
          event.traffic == MqttMultipathPolicy.Traffic.message.rawValue, event.attachmentTransferID.isEmpty,
          MqttRouteProtocol.hex(event.wireHash, count: 64),
          event.requestHash.map({ MqttRouteProtocol.hex($0, count: 64) }) == true,
          event.sourceMessageID == String(dispatch.sourceMessageId), event.contactID == dispatch.contactId,
          taskIdentity.isComplete, taskIdentity.clientRouteId == expectedRouteID,
          taskIdentity.conversationId == dispatch.conversationId,
          taskIdentity.turnId == dispatch.turnId, taskIdentity.taskId == dispatch.taskId,
          managed.state == .pending, managed.response == nil, managed.ownerRunId == dispatch.owner,
          !managed.agentId.isBlank, managed.agentId == pending.metadata["control_plane_agent_id"],
          dispatch.owner == AgentControlPlaneActionExecutor.connectorRunId(action: action, agentId: managed.agentId),
          managed.sourceMessageId == dispatch.sourceMessageId, managed.contactId == dispatch.contactId,
          managed.conversationId == dispatch.conversationId, managed.turnId == dispatch.turnId, managed.taskId == dispatch.taskId,
          managed.executionGeneration == Int64(pending.metadata["execution_generation"] ?? ""),
          managed.correlates(dispatch.response("", success: false)),
          let started = Int64(pending.metadata["resource_started_at"] ?? ""), started > 0,
          event.receivedAt >= started else { throw MqttRouteError.identityChanged }
    let messageID: String
    if pending.metadata["has_attachments"] == "true" {
      guard let body = pending.metadata["native_connector_attachment_body_id"],
            body == UUID(uuidString: dispatch.taskId)?.uuidString else { throw MqttRouteError.identityChanged }
      messageID = body
    } else {
      guard let owner = UUID(uuidString: dispatch.owner) else { throw MqttRouteError.identityChanged }
      messageID = owner.uuidString
    }
    guard event.messageID == messageID else { throw MqttRouteError.identityChanged }
    // Completion replay must not refresh acceptance or overwrite later remote progress.
    guard pending.metadata["transport_accepted_at"] == nil else { return nil }
    var updated = pending
    updated.metadata["transport_accepted_at"] = String(event.receivedAt)
    if (pending.metadata["remote_task_status"] ?? "").isBlank {
      updated.metadata["remote_task_status"] = "accepted"
      updated.metadata["remote_task_status_updated_at"] = String(event.receivedAt)
    }
    return updated
  }
}
