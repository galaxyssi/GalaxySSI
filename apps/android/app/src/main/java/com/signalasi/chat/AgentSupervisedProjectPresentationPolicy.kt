package com.signalasi.chat

/** Keeps model-authored control payloads out of the user-facing transcript. */
object AgentSupervisedProjectPresentationPolicy {
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
