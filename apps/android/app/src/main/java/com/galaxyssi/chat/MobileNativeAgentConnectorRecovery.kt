package com.galaxyssi.chat

internal fun MobileNativeAgent.actionEffectContext(action: AgentAction,
    conversationIdOverride: String = "", turnIdOverride: String = ""): AgentNativeToolInvocationContext {
    val conversationId = conversationIdOverride.ifBlank { action.parameters[INTERNAL_CONVERSATION_ID].orEmpty() }
        .ifBlank { activeConversationContext.conversationId }.ifBlank { sessionId }
    val turnId = turnIdOverride.ifBlank { action.parameters[INTERNAL_TURN_ID].orEmpty() }
        .ifBlank { activeConversationTurnId }.ifBlank { action.id }
    val taskId = action.parameters["_galaxyssi_task_id"].orEmpty()
        .ifBlank { currentPlan?.planId.orEmpty() }.ifBlank { turnId }
    return AgentNativeToolInvocationContext(sessionId = sessionId, conversationId = conversationId, turnId = turnId,
        callerId = "galaxyssi.mobile_agent.action", attributes = mapOf(
            "client_route_id" to "galaxyssi-phone", "task_id" to taskId, "goal_id" to taskId))
}

/** Repair only the known local recovery conflict, using a matching durable dispatch receipt. */
internal fun MobileNativeAgent.restoreConflictedConnectorReceipt(source: Long, contact: String,
    conversation: String, turn: String, task: String): Boolean = synchronized(this) {
    restoreConflictedConnectorReceiptLocked(source, contact, conversation, turn, task)
}

private fun MobileNativeAgent.restoreConflictedConnectorReceiptLocked(source: Long, contact: String,
    conversation: String, turn: String, task: String): Boolean {
    if (phase != AgentPhase.FAILED || source <= 0L || contact.isBlank() || conversation.isBlank() || turn.isBlank()) return false
    val failure = lastActionResult ?: return false
    if (failure.metadata["error_code"] != "idempotency_key_conflict") return false
    val plan = currentPlan ?: return false
    val action = plan.actions.firstOrNull { it.id == failure.actionId && it.kind == AgentActionKind.CALL_CONNECTOR }
        ?: return false
    if (action.parameters["superseded_source_message_id"]?.toLongOrNull() != source ||
        AgentPendingHandoffRecoveryPolicy.recoveryAttempt(action.parameters) !in
            1..AgentPendingHandoffRecoveryPolicy.MAX_RECOVERY_ATTEMPTS) return false
    val dispatchedAction = action.copy(parameters = action.parameters + ("_galaxyssi_task_id" to sessionId))
    val receipt = actionEffectExecutor.dispatchedResult(dispatchedAction, actionEffectContext(dispatchedAction)) ?: return false
    if (!receipt.success || receipt.metadata["awaiting_response"] != "true" ||
        receipt.metadata["source_message_id"]?.toLongOrNull() != source ||
        receipt.metadata["contact_id"] != contact || receipt.metadata["conversation_id"] != conversation ||
        receipt.metadata["turn_id"] != turn ||
        !AgentTaskIdentityPolicy.matchesDesktopResponse(receipt.metadata, conversation, task, turn)) return false
    if (!reopenConnectorOutcomeLoop()) return false
    lastActionResult = receipt
    currentPlan = plan.markAction(action.id, AgentActionStatus.WAITING_RESPONSE, receipt)
    phase = AgentPhase.WAITING_RESPONSE
    saveTaskRecord()
    return true
}

internal fun MobileNativeAgent.reopenConnectorOutcomeLoop(): Boolean {
    val loop = executionLoopSnapshot() ?: return true
    if (loop.phase != AgentExecutionLoopPhase.FAILED) return !loop.phase.isTerminal
    if (loop.budgetFailure.isNotBlank()) return false
    return advanceExecutionLoop(AgentExecutionLoopPhase.REPLAN, "Reconciling a durable remote outcome", retry = true) &&
        advanceExecutionLoop(AgentExecutionLoopPhase.WAITING_RESPONSE, "Waiting for the original remote outcome")
}
