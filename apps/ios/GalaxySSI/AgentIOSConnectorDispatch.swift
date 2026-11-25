import CryptoKit
import Foundation

protocol AgentQueuedConnectorDispatching {
  func startQueuedConnector(action: AgentAction, receipt: AgentActionResult)
}

struct AgentIOSQueuedConnectorExecutor: AgentActionExecutor, AgentQueuedConnectorDispatching {
  let delegate: AgentActionExecutor
  let start: (AgentAction, AgentActionResult) -> Void

  func execute(action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
    guard action.kind == .callConnector else { return delegate.execute(action: action, screen: screen) }
    return AgentIOSConnectorDispatch.prepare(action)
  }

  func startQueuedConnector(action: AgentAction, receipt: AgentActionResult) {
    guard receipt.metadata["awaiting_response"] == "true", receipt.actionId == action.id else { return }
    start(action, receipt)
  }
}

struct AgentIOSConnectorDispatch {
  static let sourceKey = "_galaxyssi_connector_source_message_uuid"
  static let profileKey = "_galaxyssi_connector_profile_fingerprint"
  static let permissionKey = "_galaxyssi_connector_permission_mode"
  let action: AgentAction
  let receipt: AgentActionResult
  let sourceMessageId: Int64
  let outgoingId: UUID

  var owner: String { receipt.metadata["control_plane_run_id"] ?? "" }
  var contactId: String { receipt.metadata["contact_id"] ?? "" }
  var conversationId: String { receipt.metadata["conversation_id"] ?? "" }
  var turnId: String { receipt.metadata["turn_id"] ?? "" }
  var taskId: String { receipt.metadata["task_id"] ?? "" }
  var prompt: String { action.parameters["prompt"] ?? "" }
  var executionPrompt: String {
    let policy = action.parameters[AgentExecutionPolicyPrompt.contextKey] ?? ""
    return policy.isBlank ? prompt : policy + "\n\n" + prompt
  }

  init?(action: AgentAction, receipt: AgentActionResult) {
    guard action.kind == .callConnector, receipt.actionId == action.id,
          receipt.metadata["awaiting_response"] == "true",
          let source = Int64(receipt.metadata["source_message_id"] ?? ""), source > 0,
          let id = action.parameters[Self.sourceKey].flatMap(UUID.init(uuidString:)),
          !(receipt.metadata["control_plane_run_id"] ?? "").isBlank,
          receipt.metadata["contact_id"] == action.parameters["connector_id"],
          receipt.metadata["conversation_id"] == action.parameters["_galaxyssi_conversation_id"],
          receipt.metadata["turn_id"] == action.parameters["_galaxyssi_turn_id"] else { return nil }
    self.action = action
    self.receipt = receipt
    sourceMessageId = source
    outgoingId = id
  }

  static func prepare(_ action: AgentAction) -> AgentActionResult {
    let conversation = action.parameters["_galaxyssi_conversation_id"] ?? ""
    let turn = action.parameters["_galaxyssi_turn_id"] ?? ""
    let target = action.parameters["connector_id"] ?? ""
    let prompt = action.parameters["prompt"] ?? ""
    guard !action.id.isBlank, !conversation.isBlank, !turn.isBlank, !target.isBlank,
          action.parameters["_galaxyssi_task_id"] == turn,
          !(action.parameters["_galaxyssi_session_id"] ?? "").isBlank,
          action.parameters[sourceKey].flatMap(UUID.init(uuidString:)) != nil,
          !(action.parameters[profileKey] ?? "").isBlank,
          !(action.parameters[permissionKey] ?? "").isBlank,
          (action.parameters["_galaxyssi_agent_team_spec"] ?? "").isBlank,
          !prompt.isBlank, prompt.utf8.count <= 256 * 1_024,
          target != AgentPlanFactory.unavailableReasoningConnectorId else {
      return AgentActionResult(actionId: action.id, success: false,
        message: "The connector request has no valid owned scope or prompt. Nothing was sent.",
        metadata: ["error_code": "invalid_owned_connector_request", "execution_started": "false",
          "non_retriable": "true", "completion_verified": "false"])
    }
    let task = AgentControlPlaneActionExecutor.stableRunId(conversationId: conversation,
      turnId: turn, actionId: AgentConnectorHandoffRecovery.effectAttemptKey(action) + "|" +
        (action.parameters[profileKey] ?? ""), agentId: target)
    let digest = SHA256.hash(data: Data(task.utf8)).map { String(format: "%02x", $0) }.joined()
    let source = max(1, Int64(digest.prefix(13), radix: 16) ?? 0)
    return AgentActionResult(actionId: action.id, success: true, message: "Queued",
      metadata: ["awaiting_response": "true", "completion_verified": "false",
        "source_message_id": String(source), "contact_id": target, "resource_id": target,
        "conversation_id": conversation, "turn_id": turn, "task_id": task, "remote_task_id": task,
        "execution_generation": "1", "remote_task_status": "queued",
        "resource_started_at": String(AgentControlPlaneClock.nowMillis())])
  }

  func matchesWaitingAction(_ waiting: AgentAction) -> Bool {
    var original = waiting
    var prepared = action
    original.parameters.removeValue(forKey: AgentNativeConnectorContinuation.receiptKey)
    original.parameters.removeValue(forKey: AgentNativeConnectorContinuation.sourceKey)
    // The provider appends this host policy after the original action was checkpointed.
    original.parameters.removeValue(forKey: AgentExecutionPolicyPrompt.contextKey)
    prepared.parameters.removeValue(forKey: AgentExecutionPolicyPrompt.contextKey)
    original.status = action.status
    original.result = action.result
    original.evidence = action.evidence
    return original == prepared
  }

  func response(_ text: String, success: Bool) -> AgentConnectorResponse {
    AgentConnectorResponse(sourceMessageId: sourceMessageId, contactId: contactId, content: text,
      conversationId: conversationId, turnId: turnId, taskId: taskId, success: success,
      receivedAtMillis: AgentControlPlaneClock.nowMillis(), taskStatus: success ? "completed" : "failed")
  }
}
