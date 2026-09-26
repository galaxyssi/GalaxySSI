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
        if (latest != null && AgentDeliveryFailurePolicy.sourceMessageId(latest) != null &&
            (workspace == null || ((workspace.status in ACTIVE_STATUSES || workspace.status == AgentWorkspaceStatus.COMPLETED) &&
                AgentDeliveryFailurePolicy.matches(workspace, latest)))) {
            return ConversationHubAgentStatus.FAILED
        }
        val finalReply = latest?.role == AgentTranscriptRole.ASSISTANT &&
            !AgentTranscriptRenderPolicy.isLiveStream(latest) &&
            !latest.dedupeKey.startsWith("approval:") && !latest.dedupeKey.startsWith("remote-approval:")
        // Delivery is durable evidence for this turn; an old progress snapshot is not live execution.
        if (workspace != null && workspace.status in ACTIVE_STATUSES &&
            finalReply && hasDeliveredReply(workspace, requireNotNull(latest))) {
            return if (unread) ConversationHubAgentStatus.COMPLETE_UNREAD else ConversationHubAgentStatus.READ
        }
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

    internal fun hasDeliveredReply(workspace: AgentWorkspace, reply: AgentTranscriptEntry): Boolean {
        if (AgentDeliveryFailurePolicy.sourceMessageId(reply) != null) return false
        if (workspace.cancellationRequested || !AgentTaskTerminalReplyPolicy.isTerminalReply(reply)) return false
        if (reply.conversationId.isBlank() || reply.conversationId != workspace.conversationId) return false
        val sameTask = if (reply.taskId.isNotBlank()) {
            reply.taskId == workspace.taskId
        } else {
            reply.turnId.isNotBlank() && (reply.turnId == workspace.workspaceId || reply.turnId == workspace.taskId)
        }
        // Executor task IDs can differ from the parent turn. Only its canonical final key
        // proves whole-turn delivery; a child task's result must not finish the parent.
        val canonicalTurnFinal = reply.turnId.isNotBlank() &&
            reply.turnId == workspace.workspaceId && reply.turnId == workspace.taskId &&
            reply.dedupeKey == AgentFinalResponseIdentity.dedupeKey(reply.turnId)
        if ((!sameTask && !canonicalTurnFinal) || reply.timestampMillis < workspace.createdAtMillis) return false
        // Explicit resumption may reuse a workspace. Late progress alone must not revive a delivered turn.
        return workspace.eventJournal.none {
            it.kind == AgentTaskEventKinds.RESUMED && it.timestampMillis > reply.timestampMillis
        }
    }

    private val ACTIVE_STATUSES = setOf(AgentWorkspaceStatus.CREATED, AgentWorkspaceStatus.QUEUED,
        AgentWorkspaceStatus.RUNNING, AgentWorkspaceStatus.WAITING_RESPONSE)
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
