package com.galaxyssi.chat

internal object AgentFinalResponseIdentity {
    fun dedupeKey(
        turnId: String,
        sourceMessageId: Long = 0L,
        taskId: String = ""
    ): String {
        val identity = when {
            turnId.isNotBlank() -> "turn:${turnId.trim()}"
            sourceMessageId > 0L -> "source:$sourceMessageId"
            taskId.isNotBlank() -> "task:${taskId.trim()}"
            else -> return ""
        }
        return "assistant-final:$identity"
    }

    fun resolveTurnId(
        explicitTurnId: String,
        taskId: String,
        turnIdForTask: (String) -> String?
    ): String = explicitTurnId.trim().ifBlank {
        taskId.trim().takeIf(String::isNotBlank)
            ?.let(turnIdForTask)
            ?.trim()
            .orEmpty()
    }

    fun coalesce(entries: List<AgentTranscriptEntry>): List<AgentTranscriptEntry> {
        val candidates = entries.filter(::isCanonicalFinalCandidate)
        if (candidates.size < 2) return entries
        val retainedIds = candidates
            .groupBy(::duplicateKey)
            .values
            .mapTo(mutableSetOf()) { duplicates ->
                duplicates.maxWithOrNull(
                    compareBy<AgentTranscriptEntry>(
                        { it.turnId.isNotBlank() },
                        { it.richOutputJson.isNotBlank() },
                        AgentTranscriptEntry::timestampMillis
                    )
                )?.id.orEmpty()
            }
        return entries.filter { entry ->
            !isCanonicalFinalCandidate(entry) || entry.id in retainedIds
        }
    }

    private fun isCanonicalFinalCandidate(entry: AgentTranscriptEntry): Boolean =
        entry.role == AgentTranscriptRole.ASSISTANT &&
            entry.dedupeKey.startsWith("assistant-final:") &&
            entry.taskId.isNotBlank() &&
            entry.text.isNotBlank()

    private fun duplicateKey(entry: AgentTranscriptEntry): String = listOf(
        entry.conversationId,
        entry.taskId.trim(),
        entry.text.trim()
    ).joinToString("\u001f")
}
