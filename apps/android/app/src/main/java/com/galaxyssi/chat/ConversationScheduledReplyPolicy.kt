package com.galaxyssi.chat

/** A delivered result belongs to the chat, not to the scheduler's execution turn. */
internal object ConversationScheduledReplyPolicy {
    const val RESULT_PREFIX = "scheduled-result:"

    fun turnId(conversationId: String, runId: String): String =
        "scheduled-delivery:$conversationId:$runId"

    fun projectLegacy(
        entry: AgentTranscriptEntry,
        owner: (String) -> String?,
        taskDestination: (String) -> String?,
        canonical: (String) -> String?
    ): AgentTranscriptEntry {
        if (entry.role != AgentTranscriptRole.ASSISTANT || entry.turnId.isBlank() ||
            entry.taskId != entry.turnId || entry.dedupeKey != "$RESULT_PREFIX${entry.turnId}") return entry
        val executionOwner = owner(entry.turnId)?.takeIf { it.startsWith("proactive:") } ?: return entry
        val destination = taskDestination(executionOwner.removePrefix("proactive:")) ?: return entry
        if (!AgentTranscriptOwnership.accepts(entry.conversationId, listOf(destination), canonical)) return entry
        // Preserve the persisted entry/dedupe identity so reading it clears the original unread token.
        return entry.copy(turnId = turnId(entry.conversationId, entry.turnId))
    }
}
