package com.galaxyssi.chat

internal object AgentProcessClockPolicy {
    fun startedAt(process: AgentTranscriptEntry, entries: Collection<AgentTranscriptEntry>, fallback: Long,
        persistedStartedAtMillis: Long? = null): Long {
        val visibleRequest = entries.asSequence().filter {
            it.role == AgentTranscriptRole.USER && sameTurn(process, it) && it.timestampMillis > 0
        }.minOfOrNull { it.timestampMillis }
        return listOfNotNull(visibleRequest, persistedStartedAtMillis?.takeIf { it > 0 },
            fallback.takeIf { it > 0 }).minOrNull() ?: fallback
    }

    fun isRunning(phase: AgentPhase?): Boolean = phase != null && phase !in setOf(
        AgentPhase.COMPLETED, AgentPhase.FAILED, AgentPhase.CANCELLED
    )

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

/** Missing projections keep a terminal clock frozen; an authoritative recovery resumes it. */
internal class AgentProcessClock(private val startedAtMillis: Long, completedAtMillis: Long? = null) {
    var completedAtMillis: Long? = completedAtMillis
        private set

    fun observe(completedAt: Long?, running: Boolean = false) {
        if (running) {
            completedAtMillis = null
            return
        }
        if (completedAtMillis == null && completedAt != null) {
            completedAtMillis = completedAt.coerceAtLeast(startedAtMillis)
        }
    }

    fun elapsed(nowMillis: Long): Long = ((completedAtMillis ?: nowMillis) - startedAtMillis).coerceAtLeast(0L)
}
