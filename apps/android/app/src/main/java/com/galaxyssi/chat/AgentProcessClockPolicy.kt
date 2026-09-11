package com.galaxyssi.chat

internal object AgentProcessClockPolicy {
    fun sameTurn(process: AgentTranscriptEntry, candidate: AgentTranscriptEntry): Boolean =
        process.conversationId == candidate.conversationId && when {
            process.turnId.isNotBlank() -> process.turnId == candidate.turnId
            process.taskId.isNotBlank() -> process.taskId == candidate.taskId
            else -> false
        }

    fun finalReplyTimestamp(process: AgentTranscriptEntry, entries: Collection<AgentTranscriptEntry>): Long? =
        entries.asSequence().filter {
            it.role == AgentTranscriptRole.ASSISTANT && !AgentTranscriptRenderPolicy.isLiveStream(it) &&
                sameTurn(process, it)
        }.maxOfOrNull(AgentTranscriptEntry::timestampMillis)
}

/** A terminal clock never starts again when a later projection temporarily lacks its terminal event. */
internal class AgentProcessClock(private val startedAtMillis: Long, completedAtMillis: Long? = null) {
    var completedAtMillis: Long? = completedAtMillis
        private set

    fun observe(completedAt: Long?) {
        if (completedAtMillis == null && completedAt != null) {
            completedAtMillis = completedAt.coerceAtLeast(startedAtMillis)
        }
    }

    fun elapsed(nowMillis: Long): Long = ((completedAtMillis ?: nowMillis) - startedAtMillis).coerceAtLeast(0L)
}
