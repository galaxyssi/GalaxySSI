package com.galaxyssi.chat

import android.os.SystemClock

internal fun MainActivity.agentProcessPhase(entry: AgentTranscriptEntry): AgentPhase? {
    val live = agentTimelineRuntime(entry)?.snapshot()?.phase
        ?: lastRenderedAgentState?.takeIf { it.sessionId == entry.turnId || it.sessionId == entry.taskId }?.phase
        ?: agentExecutionPresentations[entry.taskId]?.phase
    return AgentProcessClockPolicy.phase(processLookup(entry)?.status, live)
}

internal fun MainActivity.agentProcessIsRunning(entry: AgentTranscriptEntry): Boolean =
    AgentProcessClockPolicy.isRunning(agentProcessPhase(entry))

private fun MainActivity.processLookup(entry: AgentTranscriptEntry): AgentProcessCompletionLookup? =
    agentProcessCompletionLookups[entry.turnId.trim()]?.takeIf { it.conversationId == entry.conversationId }

internal fun MainActivity.agentProcessStartTimestamp(
    entry: AgentTranscriptEntry,
    entries: List<AgentTranscriptEntry>,
    fallback: Long
): Long = AgentProcessClockPolicy.startedAt(entry, entries, fallback, processLookup(entry)?.startedAtMillis)

internal fun MainActivity.agentProcessCompletionTimestamp(
    entry: AgentTranscriptEntry,
    entries: List<AgentTranscriptEntry>
): Long? {
    val workspaceId = entry.turnId.trim()
    val cached = processLookup(entry)
    // Check the committed user turn even if a retained runtime still says it is waiting.
    // A completed Desktop attempt or an interim answer cannot complete a multi-step turn.
    if (workspaceId.isNotBlank() && (cached == null ||
            SystemClock.elapsedRealtime() - cached.checkedAtElapsedRealtime >= AGENT_PROCESS_COMPLETION_LOOKUP_RETRY_MS)) {
        scheduleAgentProcessCompletionLookup(entry, workspaceId)
    }
    if (agentProcessIsRunning(entry)) return null
    if (workspaceId.isBlank()) {
        agentExecutionPresentations[entry.taskId]
            ?.takeIf { !it.cancellable && !AgentExecutionPresentationPolicy.isCancellable(it.phase) }
            ?.completedAtMillis?.takeIf { it > 0L }
            ?.let { return it.coerceAtLeast(entry.timestampMillis) }
    } else {
        if (cached == null) return null
        if (cached.status != null && !cached.status.isTerminal) return null
        cached.completedAtMillis?.let { return it.coerceAtLeast(entry.timestampMillis) }
    }
    return AgentProcessClockPolicy.finalReplyTimestamp(entry, entries.filterNot(::isAgentApprovalEntry))
        ?.coerceAtLeast(entry.timestampMillis)
}

internal fun MainActivity.scheduleAgentProcessCompletionLookup(entry: AgentTranscriptEntry, workspaceId: String) {
    if (workspaceId.isBlank() || !agentProcessCompletionLookupInFlight.add(workspaceId)) return
    agentTranscriptContentExecutor.execute {
        val lookup = runCatching {
            val workspace = EncryptedAgentWorkspaceStore(this).find(workspaceId)
                ?.takeIf { it.conversationId == entry.conversationId }
            val startedAt = agentTranscriptStore.firstTimestampForTurn(entry.conversationId, workspaceId)
                ?: workspace?.createdAtMillis?.takeIf { it > 0L }
            AgentProcessCompletionLookup(
                completedAtMillis = workspace?.takeIf { it.status.isTerminal }?.updatedAtMillis?.takeIf { it > 0L },
                checkedAtElapsedRealtime = SystemClock.elapsedRealtime(),
                status = workspace?.status,
                startedAtMillis = startedAt,
                conversationId = entry.conversationId,
                revision = workspace?.revision ?: -1L
            )
        }
        runOnUiThread {
            agentProcessCompletionLookupInFlight.remove(workspaceId)
            lookup.onSuccess { applyAgentProcessCompletionLookup(entry.conversationId, workspaceId, it) }
        }
    }
}

internal fun MainActivity.applyAgentProcessCompletionLookup(
    conversationId: String,
    turnId: String,
    incoming: AgentProcessCompletionLookup
) {
    if (isFinishing || isDestroyed || runtimePlaintextCleared || incoming.conversationId != conversationId) return
    val rows = renderedAgentTranscriptSourceEntries.filter {
        it.conversationId == conversationId && it.turnId == turnId && it.role == AgentTranscriptRole.PROCESS
    }
    if (rows.isEmpty()) return
    val previous = agentProcessCompletionLookups[turnId]
    val next = AgentProcessClockPolicy.merge(previous, incoming)
    agentProcessCompletionLookups[turnId] = next
    if (previous?.status == next.status && previous?.completedAtMillis == next.completedAtMillis &&
        previous?.startedAtMillis == next.startedAtMillis) return
    if (!isAgentTranscriptAdapterInitialized()) return
    // The adapter contains collapsed process-group IDs, not the original event IDs.
    AgentTranscriptPresentationPolicy.collapseProcessGroups(rows).map(AgentTranscriptEntry::id).distinct()
        .map(agentTranscriptAdapter::indexOfEntry).filter { it >= 0 }.forEach(agentTranscriptAdapter::notifyItemChanged)
}
