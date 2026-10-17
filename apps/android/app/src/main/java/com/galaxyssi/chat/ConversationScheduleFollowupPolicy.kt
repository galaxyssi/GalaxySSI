package com.galaxyssi.chat

/** Ambiguous edits/controls need a host-owned schedule receipt from the nearest user turn. */
internal object ConversationScheduleFollowupPolicy {
    fun hasExplicitTarget(request: String, command: ConversationScheduleCommand): Boolean =
        command.trigger != null || command.operation == ConversationScheduleOperation.LIST ||
            command.operation in setOf(ConversationScheduleOperation.PAUSE, ConversationScheduleOperation.RESUME) &&
            AgentDeviceIntent.followup(request) == null

    fun ownsLatestResult(context: AgentConversationContext, taskIds: Set<String>): Boolean {
        val latest = context.turns.lastOrNull { it.role == AgentTranscriptRole.USER } ?: return false
        if (latest.turnId.isBlank() || !owns(context, latest)) return false
        return context.turns.any { entry ->
            entry.role == AgentTranscriptRole.ASSISTANT && owns(context, entry) &&
                entry.turnId == latest.turnId && entry.dedupeKey == "schedule-command:${latest.turnId}" &&
                AgentRichContentCodec.decode(entry.richOutputJson).any { block ->
                    block.type == AgentRichBlockType.ACTIONS && block.actions.any {
                        it.verb == "edit_scheduled_task" && it.value in taskIds
                    }
                }
        }
    }

    private fun owns(context: AgentConversationContext, entry: AgentTranscriptEntry) =
        entry.conversationId == context.conversationId && entry.sourceConversationId.isBlank()
}
