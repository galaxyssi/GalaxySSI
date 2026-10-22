package com.galaxyssi.chat

internal object AgentProcessClockPolicy {
    fun phase(status: AgentWorkspaceStatus?, livePhase: AgentPhase?): AgentPhase? = when (status) {
        null -> livePhase
        AgentWorkspaceStatus.CREATED, AgentWorkspaceStatus.QUEUED -> AgentPhase.PLANNING
        AgentWorkspaceStatus.RUNNING -> livePhase?.takeIf {
            it in setOf(AgentPhase.OBSERVING, AgentPhase.PLANNING, AgentPhase.EXECUTING, AgentPhase.VERIFYING)
        } ?: AgentPhase.EXECUTING
        AgentWorkspaceStatus.WAITING_CONFIRMATION -> AgentPhase.WAITING_CONFIRMATION
        AgentWorkspaceStatus.WAITING_RESPONSE -> AgentPhase.WAITING_RESPONSE
        AgentWorkspaceStatus.PAUSED -> AgentPhase.PAUSED
        AgentWorkspaceStatus.BLOCKED -> AgentPhase.BLOCKED
        AgentWorkspaceStatus.COMPLETED -> AgentPhase.COMPLETED
        AgentWorkspaceStatus.FAILED -> AgentPhase.FAILED
        AgentWorkspaceStatus.CANCELLED -> AgentPhase.CANCELLED
    }

    fun merge(previous: AgentProcessCompletionLookup?, incoming: AgentProcessCompletionLookup): AgentProcessCompletionLookup {
        if (previous == null) return incoming
        if (previous.conversationId != incoming.conversationId || previous.revision > incoming.revision) return previous
        return incoming.copy(
            startedAtMillis = listOfNotNull(previous.startedAtMillis, incoming.startedAtMillis).minOrNull(),
            completedAtMillis = if (previous.status == incoming.status) {
                previous.completedAtMillis ?: incoming.completedAtMillis
            } else incoming.completedAtMillis
        )
    }

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
