import Foundation

enum AgentNativeConnectorContinuation {
  static let receiptKey = "_galaxyssi_native_connector_wait_receipt"
  static let sourceKey = "_galaxyssi_native_connector_wait_source"

  static func waitingAction(_ action: AgentAction, result: AgentActionResult,
                            task: AgentTaskRecord, outgoing: ChatMessage) -> AgentAction? {
    let conversation = outgoing.conversationId
    let turn = outgoing.turnId.ifBlank(outgoing.id.uuidString)
    let metadata = result.metadata
    guard outgoing.isMine, outgoing.contactId == "hermes", !outgoing.readOnlyAnalysis,
          !conversation.isBlank, !turn.isBlank, task.sessionId == conversation, task.taskId == turn,
          action.kind == .callConnector, action.id == result.actionId,
          (action.parameters["_galaxyssi_agent_team_spec"] ?? "").isBlank,
          action.parameters["_galaxyssi_conversation_id"] == conversation,
          action.parameters["_galaxyssi_turn_id"] == turn,
          action.parameters["_galaxyssi_task_id"] == task.taskId,
          metadata["awaiting_response"] == "true",
          let source = Int64(metadata["source_message_id"] ?? ""), source > 0,
          let generation = Int64(metadata["execution_generation"] ?? "1"),
          AgentRemoteOutcomePolicy.validGeneration(generation),
          metadata["conversation_id"] == conversation, metadata["turn_id"] == turn,
          !(metadata["contact_id"] ?? "").isBlank, !(metadata["task_id"] ?? "").isBlank,
          let owner = metadata["control_plane_run_id"], !owner.isBlank,
          let agent = metadata["control_plane_agent_id"], !agent.isBlank,
          owner == AgentControlPlaneActionExecutor.stableRunId(conversationId: conversation,
            turnId: turn, actionId: action.id, agentId: agent),
          let encoded = try? JSONEncoder().encode(result), encoded.count <= 128 * 1_024 else { return nil }
    var waiting = action
    waiting.status = .waitingResponse
    waiting.result = ""
    waiting.evidence = "awaiting_connector_response"
    waiting.parameters[receiptKey] = String(decoding: encoded, as: UTF8.self)
    waiting.parameters[sourceKey] = outgoing.id.uuidString
    return waiting
  }

  static func pendingResult(_ action: AgentAction) -> AgentActionResult? {
    guard action.kind == .callConnector, action.status == .waitingResponse,
          let raw = action.parameters[receiptKey], raw.utf8.count <= 128 * 1_024,
          let result = try? JSONDecoder().decode(AgentActionResult.self, from: Data(raw.utf8)),
          result.actionId == action.id, result.metadata["awaiting_response"] == "true" else { return nil }
    return result
  }

  static func hasWaitingAction(_ task: AgentTaskRecord) -> Bool {
    task.activePlan?.actions.contains { $0.parameters[receiptKey] != nil } == true
  }

  static func settle(_ pending: AgentActionResult, record: AgentManagedResponseRecord) -> AgentActionResult? {
    guard record.state != .pending, let response = record.response,
          record.matchesCommittedResult(response),
          record.ownerRunId == pending.metadata["control_plane_run_id"],
          record.agentId == pending.metadata["control_plane_agent_id"],
          record.sourceMessageId == Int64(pending.metadata["source_message_id"] ?? ""),
          record.contactId == pending.metadata["contact_id"], response.contactId == record.contactId,
          record.conversationId == pending.metadata["conversation_id"], response.conversationId == record.conversationId,
          record.turnId == pending.metadata["turn_id"], response.turnId == record.turnId,
          record.taskId == pending.metadata["task_id"], response.taskId == record.taskId,
          record.executionGeneration == Int64(pending.metadata["execution_generation"] ?? "1"),
          response.executionGeneration == record.executionGeneration,
          response.taskStatus.isEmpty || AgentRemoteOutcomePolicy.isTerminal(response.taskStatus) else { return nil }
    var result = AgentConnectorResponseResolver.settle(pending: pending, response: response)?.result
    if !response.taskStatus.isEmpty { result?.metadata["remote_task_status"] = response.taskStatus }
    return result
  }
}

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
    if let expectedGeneration = Int64(pending.metadata["execution_generation"] ?? ""),
       expectedGeneration != response.executionGeneration {
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
    metadata["task_status"] = response.taskStatus
    metadata["execution_generation"] = String(response.executionGeneration)
    metadata["status_sequence"] = String(response.statusSequence)
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
    if !response.deliveryFailureCode.isEmpty {
      guard !response.success,
            response.taskStatus.isEmpty,
            AgentAttachmentDeliveryFailureContract.isTerminal(response.deliveryFailureCode) else {
        return nil
      }
      metadata["delivery_failure_code"] = response.deliveryFailureCode
      metadata["attachment_verified"] = "false"
      metadata["connector_disposition"] = "delivery_failure"
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
        "task_status": .string(response.taskStatus),
        "execution_generation": .int(response.executionGeneration),
        "status_sequence": .int(response.statusSequence),
        "delivery_failure_code": .string(response.deliveryFailureCode),
        "result": .string(response.content),
        "rich_output": .string(response.success ? response.richOutputJson : ""),
        "error": .string(response.success ? "" : response.content)
      ]
    )
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
