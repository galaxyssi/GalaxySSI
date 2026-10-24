package com.galaxyssi.chat

import android.content.Context

/** Replays only the commit of an already accepted answer; never executes a plan or calls a provider. */
internal object AgentCompletedReplyRecovery {
    private val finalizing = setOf(AgentExecutionLoopPhase.VERIFY, AgentExecutionLoopPhase.FINALIZE,
        AgentExecutionLoopPhase.LEARN, AgentExecutionLoopPhase.COMPLETED)

    fun hasCompletedResult(session: AgentSessionSnapshot): Boolean = session.phase == AgentPhase.COMPLETED &&
        session.lastActionResult?.success == true && session.lastActionResult.message.isNotBlank() &&
        session.executionLoopSnapshot?.phase in finalizing

    fun matches(session: AgentSessionSnapshot, response: AgentConnectorResponse,
                identity: AgentConnectorResponseIdentity): Boolean {
        if (!hasCompletedResult(session) || !response.success || response.remoteFailure ||
            response.deliveryFailureCode.isNotBlank() || session.executionLoopSnapshot?.taskId != identity.turnId ||
            response.conversationId != identity.conversationId || response.turnId != identity.turnId ||
            response.taskId != identity.taskId) return false
        val metadata = checkNotNull(session.lastActionResult).metadata
        return metadata["source_message_id"] == response.sourceMessageId.toString() &&
            metadata["contact_id"] == response.contactId && response.contactId.isNotBlank() &&
            metadata["conversation_id"] == identity.conversationId && metadata["turn_id"] == identity.turnId &&
            metadata["remote_task_id"] == identity.taskId && metadata["awaiting_response"] == "false" &&
            (metadata["remote_execution_generation"]?.toLongOrNull() ?: 1L) == response.executionGeneration
    }

    fun failedDuringFinalization(workspace: AgentWorkspace): Boolean {
        // Retain commit-only recovery if a process dies after the supervisor reopens the failed run.
        if (workspace.status !in setOf(AgentWorkspaceStatus.FAILED, AgentWorkspaceStatus.WAITING_RESPONSE,
                AgentWorkspaceStatus.QUEUED, AgentWorkspaceStatus.RUNNING) || workspace.cancellationRequested) return false
        val failure = workspace.eventJournal.lastOrNull { it.kind == AgentTaskEventKinds.FAILED } ?: return false
        return failure.message == "Invalid Agent loop transition from VERIFY to LEARN" &&
            workspace.eventJournal.any { it.kind == "agent.loop.finalize" && it.sequence < failure.sequence }
    }

    fun pending(context: Context, response: AgentConnectorResponse): Boolean {
        if (response.turnId.isBlank()) return false
        val workspace = AgentTaskRuntime.supervisor(context).findWorkspace(response.turnId) ?: return false
        if (!failedDuringFinalization(workspace)) return false
        val session = SharedPreferencesAgentSessionStore(context, "task:${response.turnId}").load() ?: return false
        val identity = AgentTaskIdentityPolicy.canonicalConnectorResponseIdentity(
            AgentPendingDeliveryStore.find(context, response.sourceMessageId, response.contactId),
            response.conversationId, response.taskId, response.turnId)
        return AgentConnectorBackgroundIdentity.matches(response, identity, workspace) && matches(session, response, identity)
    }
}
