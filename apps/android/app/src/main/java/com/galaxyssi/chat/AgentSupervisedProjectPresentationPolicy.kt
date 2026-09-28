package com.galaxyssi.chat

/** Keeps model-authored control payloads out of the user-facing transcript. */
object AgentSupervisedProjectPresentationPolicy {
    internal fun ownsResponse(plan: AgentPlan?, result: AgentActionResult?, response: AgentConnectorResponse): Boolean {
        val action = plan?.actions?.firstOrNull { it.id == result?.actionId } ?: return false
        if (!action.isSupervisedProjectConnector()) return false
        val metadata = result?.metadata.orEmpty()
        return response.sourceMessageId > 0 &&
            metadata["source_message_id"]?.toLongOrNull() == response.sourceMessageId &&
            metadata["contact_id"] == response.contactId &&
            action.parameters[INTERNAL_CONVERSATION_ID] == response.conversationId &&
            action.parameters[INTERNAL_TURN_ID] == response.turnId &&
            response.conversationId.isNotBlank() && response.turnId.isNotBlank() &&
            (metadata["remote_task_id"].isNullOrBlank() || metadata["remote_task_id"] == response.taskId)
    }

    fun shouldShowFailureRecovery(
        pendingAction: AgentAction?,
        isSupervisedSource: Boolean,
        isSupervisedPlan: Boolean = false,
        terminalAccepted: Boolean = true,
        settledPhase: AgentPhase? = null
    ): Boolean = terminalAccepted &&
        (settledPhase == null || settledPhase == AgentPhase.FAILED) &&
        !isSupervisedSource &&
        !isSupervisedPlan &&
        pendingAction?.isSupervisedProjectConnector() != true

    fun shouldExposeConnectorStream(
        phase: AgentPhase,
        pendingAction: AgentAction?,
        expectedSourceMessageId: Long,
        incomingSourceMessageId: Long,
        isSupervisedSource: Boolean = false
    ): Boolean {
        if (isSupervisedSource) return false
        return !(
            phase == AgentPhase.WAITING_RESPONSE &&
                pendingAction?.isSupervisedProjectConnector() == true &&
                expectedSourceMessageId > 0L &&
                expectedSourceMessageId == incomingSourceMessageId
            )
    }

    internal fun matchesDirectConnectorTaskEvent(
        binding: PendingDirectConnectorRun?,
        contactId: String,
        conversationId: String,
        turnId: String,
        taskId: String
    ): Boolean {
        binding ?: return false
        return binding.contactId == contactId &&
            binding.conversationId == conversationId &&
            binding.turnId == turnId &&
            (binding.taskId.isBlank() || taskId.isBlank() || binding.taskId == taskId)
    }
}
