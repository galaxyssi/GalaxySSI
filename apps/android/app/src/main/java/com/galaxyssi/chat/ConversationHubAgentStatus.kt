package com.galaxyssi.chat

internal enum class ConversationHubAgentStatus {
    QUEUED, RUNNING, WAITING_RESPONSE, RECONNECTING, DELIVERING,
    COMPLETE_UNREAD, READ, WAITING_CONFIRMATION, PAUSED, BLOCKED, FAILED, CANCELLED;

    val animated: Boolean get() = this in setOf(QUEUED, RUNNING, WAITING_RESPONSE, RECONNECTING, DELIVERING)
}

internal object ConversationHubAgentStatusPolicy {
    fun workspace(conversationId: String, latest: AgentTranscriptEntry?, workspaces: List<AgentWorkspace>): AgentWorkspace? =
        workspaces.asSequence().filter { it.conversationId == conversationId }
            .filter { workspace ->
                if (latest?.turnId.isNullOrBlank() && latest?.taskId.isNullOrBlank()) true
                else workspace.workspaceId == latest?.turnId || workspace.taskId == latest?.turnId ||
                    (latest?.taskId?.isNotBlank() == true && workspace.taskId == latest.taskId)
            }
            .maxWithOrNull(compareBy<AgentWorkspace> { it.createdAtMillis }.thenBy { it.updatedAtMillis })

    fun resolve(workspace: AgentWorkspace?, latest: AgentTranscriptEntry?, unread: Boolean): ConversationHubAgentStatus {
        val finalReply = latest?.role == AgentTranscriptRole.ASSISTANT &&
            !AgentTranscriptRenderPolicy.isLiveStream(latest) &&
            !latest.dedupeKey.startsWith("approval:") && !latest.dedupeKey.startsWith("remote-approval:")
        return when (workspace?.status) {
            AgentWorkspaceStatus.CREATED, AgentWorkspaceStatus.QUEUED -> ConversationHubAgentStatus.QUEUED
            AgentWorkspaceStatus.RUNNING -> ConversationHubAgentStatus.RUNNING
            AgentWorkspaceStatus.WAITING_CONFIRMATION -> ConversationHubAgentStatus.WAITING_CONFIRMATION
            AgentWorkspaceStatus.PAUSED -> ConversationHubAgentStatus.PAUSED
            AgentWorkspaceStatus.BLOCKED -> ConversationHubAgentStatus.BLOCKED
            AgentWorkspaceStatus.FAILED -> ConversationHubAgentStatus.FAILED
            AgentWorkspaceStatus.CANCELLED -> ConversationHubAgentStatus.CANCELLED
            AgentWorkspaceStatus.WAITING_RESPONSE -> {
                val lastRecovery = workspace.eventJournal.lastOrNull {
                    it.kind in setOf(AgentTaskEventKinds.RECOVERY_WAITING_RESPONSE,
                        AgentTaskEventKinds.RECOVERED_INTERRUPTED, AgentTaskEventKinds.INTERRUPTED,
                        AgentTaskEventKinds.PROGRESS, AgentTaskEventKinds.RUNNING, AgentTaskEventKinds.WAITING_RESPONSE)
                }?.kind
                if (lastRecovery in setOf(AgentTaskEventKinds.RECOVERY_WAITING_RESPONSE,
                        AgentTaskEventKinds.RECOVERED_INTERRUPTED, AgentTaskEventKinds.INTERRUPTED)) {
                    ConversationHubAgentStatus.RECONNECTING
                } else ConversationHubAgentStatus.WAITING_RESPONSE
            }
            AgentWorkspaceStatus.COMPLETED -> if (!finalReply) ConversationHubAgentStatus.DELIVERING
                else if (unread) ConversationHubAgentStatus.COMPLETE_UNREAD else ConversationHubAgentStatus.READ
            null -> when {
                latest?.role == AgentTranscriptRole.USER -> ConversationHubAgentStatus.WAITING_RESPONSE
                unread && finalReply -> ConversationHubAgentStatus.COMPLETE_UNREAD
                else -> ConversationHubAgentStatus.READ
            }
        }
    }
}

internal fun ConversationHubAgentStatus.labelRes(): Int = when (this) {
    ConversationHubAgentStatus.QUEUED -> R.string.conversation_status_queued
    ConversationHubAgentStatus.RUNNING -> R.string.conversation_status_running
    ConversationHubAgentStatus.WAITING_RESPONSE -> R.string.conversation_status_waiting_response
    ConversationHubAgentStatus.RECONNECTING -> R.string.conversation_status_reconnecting
    ConversationHubAgentStatus.DELIVERING -> R.string.conversation_status_delivering
    ConversationHubAgentStatus.COMPLETE_UNREAD -> R.string.conversation_status_unread
    ConversationHubAgentStatus.READ -> R.string.conversation_status_read
    ConversationHubAgentStatus.WAITING_CONFIRMATION -> R.string.conversation_status_confirmation
    ConversationHubAgentStatus.PAUSED -> R.string.conversation_status_paused
    ConversationHubAgentStatus.BLOCKED -> R.string.conversation_status_blocked
    ConversationHubAgentStatus.FAILED -> R.string.conversation_status_failed
    ConversationHubAgentStatus.CANCELLED -> R.string.conversation_status_cancelled
}
