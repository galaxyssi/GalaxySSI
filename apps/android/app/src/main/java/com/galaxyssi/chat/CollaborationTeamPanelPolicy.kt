package com.galaxyssi.chat

internal data class CollaborationTeamPanelMember(
    val member: CollaborationMember,
    val entry: AgentTranscriptEntry? = null,
    val metadata: CollaborationTranscriptMetadata? = null
)

/** A read-only roster projection. Published replies remain in the conversation. */
internal object CollaborationTeamPanelPolicy {
    fun rows(group: CollaborationGroup, history: List<AgentTranscriptEntry>,
        current: List<AgentTranscriptEntry>): List<CollaborationTeamPanelMember> {
        val latest = linkedMapOf<String, Pair<AgentTranscriptEntry, CollaborationTranscriptMetadata>>()
        history.filter { it.conversationId == group.conversationId }.forEach { entry ->
            val metadata = CollaborationTranscriptMetadata.decode(entry.collaborationJson) ?: return@forEach
            val old = latest[metadata.memberId]
            val time = maxOf(metadata.updatedAtMillis, metadata.completedAtMillis, entry.timestampMillis)
            val previous = old?.let { maxOf(it.second.updatedAtMillis, it.second.completedAtMillis, it.first.timestampMillis) } ?: -1L
            val pendingWins = !metadata.result && old?.second?.result == true
            val sameKind = old == null || metadata.result == old.second.result
            if (pendingWins || sameKind && time >= previous) latest[metadata.memberId] = entry to metadata
        }
        val roster = group.members.associateByTo(linkedMapOf()) { it.id }
        var currentRun: String? = null
        current.filter { it.conversationId == group.conversationId }.forEach { entry ->
            val metadata = CollaborationTranscriptMetadata.decode(entry.collaborationJson) ?: return@forEach
            currentRun = metadata.runId
            val old = latest[metadata.memberId]?.second
            val details = old?.takeIf { it.traceTurnId == metadata.traceTurnId }?.details.orEmpty()
            latest[metadata.memberId] = entry to metadata.copy(details = metadata.details.ifBlank { details })
            roster.putIfAbsent(metadata.memberId, CollaborationMember(metadata.memberId, metadata.name,
                metadata.memberId, metadata.provider, metadata.role))
        }
        return roster.values.map { member ->
            val value = latest[member.id]?.takeIf { currentRun == null || it.second.runId == currentRun || it.second.status.isTerminal }
            val metadata = value?.second?.let { if (currentRun != null && it.runId != currentRun)
                it.copy(paused = false, goalDisposition = "", connectionState = "") else it }
            CollaborationTeamPanelMember(member, value?.first, metadata)
        }
    }

    fun replies(entries: List<AgentTranscriptEntry>): List<AgentTranscriptEntry> = entries.filter {
        CollaborationTranscriptMetadata.decode(it.collaborationJson)?.result != false
    }

    fun running(rows: List<CollaborationTeamPanelMember>): Int = rows.count {
        it.metadata?.let { state -> state.status == AgentSubagentStatus.RUNNING && !state.paused &&
            state.goalDisposition != "blocked" && state.connectionState.isBlank() } == true
    }

    fun waiting(rows: List<CollaborationTeamPanelMember>): Int = rows.count {
        it.metadata?.let { state -> !state.status.isTerminal && !state.paused &&
            (state.status == AgentSubagentStatus.QUEUED || state.connectionState.isNotBlank() || state.goalDisposition == "blocked") } == true
    }

    fun status(rows: List<CollaborationTeamPanelMember>): ConversationHubAgentStatus? {
        val states = rows.mapNotNull { it.metadata }
        return when {
            states.isEmpty() -> null
            states.any { it.paused } -> ConversationHubAgentStatus.PAUSED
            states.any { it.goalDisposition == "blocked" } -> ConversationHubAgentStatus.BLOCKED
            running(rows) > 0 -> ConversationHubAgentStatus.RUNNING
            states.any { !it.status.isTerminal && it.connectionState in setOf("waiting", "reconciling") } -> ConversationHubAgentStatus.RECONNECTING
            states.any { !it.status.isTerminal && it.connectionState in setOf("delivering", "evidence_sync") } -> ConversationHubAgentStatus.DELIVERING
            states.any { !it.status.isTerminal && it.connectionState == "remote_paused" } -> ConversationHubAgentStatus.PAUSED
            waiting(rows) > 0 -> ConversationHubAgentStatus.QUEUED
            states.any { it.goalDisposition == "continue" } -> ConversationHubAgentStatus.QUEUED
            states.any { it.status == AgentSubagentStatus.FAILED } -> ConversationHubAgentStatus.FAILED
            states.all { it.status == AgentSubagentStatus.CANCELLED } -> ConversationHubAgentStatus.CANCELLED
            else -> ConversationHubAgentStatus.READ
        }
    }
}
