package com.signalasi.chat

internal object AgentConnectorStreamPresentationPolicy {
    fun merge(
        persisted: List<AgentTranscriptEntry>,
        live: Collection<AgentTranscriptEntry>
    ): List<AgentTranscriptEntry> {
        val persistedIdentities = persisted
            .mapTo(mutableSetOf(), AgentTranscriptRenderPolicy::identity)
        return (persisted + live.filterNot {
            AgentTranscriptRenderPolicy.identity(it) in persistedIdentities
        }).sortedBy(AgentTranscriptEntry::timestampMillis)
    }

    fun representedSourceIds(
        pendingSourceIds: Collection<Long>,
        liveBySourceId: Map<Long, AgentTranscriptEntry>,
        persisted: Collection<AgentTranscriptEntry>,
        conversationId: String
    ): Set<Long> {
        val persistedIdentities = persisted.asSequence()
            .filter { it.conversationId == conversationId }
            .map(AgentTranscriptRenderPolicy::identity)
            .toSet()
        return pendingSourceIds.filterTo(mutableSetOf()) { sourceMessageId ->
            val live = liveBySourceId[sourceMessageId] ?: return@filterTo true
            live.conversationId == conversationId &&
                AgentTranscriptRenderPolicy.identity(live) in persistedIdentities
        }
    }
}
