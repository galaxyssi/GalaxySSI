package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

internal data class CollaborationMemberObservation(
    val atMillis: Long,
    val summary: String,
    val connectionState: String = "",
    val confirmed: Boolean = false
)

/** Presentation only: never changes scheduler states or dispatches another attempt. */
internal object CollaborationCurrentStatePolicy {
    fun members(team: AgentTeamExecutionSnapshot): List<AgentTeamMemberSnapshot> = team.members
        .filter { it.deliveryMode != AgentDeliveryMode.IGNORE }
        .groupBy { it.personId.ifBlank { it.memberId } }.values.map { attempts ->
            attempts.filter { it.status == AgentSubagentStatus.RUNNING }
                .maxByOrNull { it.executionStartedAtMillis }
                ?: attempts.firstOrNull { it.status == AgentSubagentStatus.QUEUED }
                ?: attempts.maxBy { maxOf(it.completedAtMillis, it.updatedAtMillis, it.executionStartedAtMillis) }
        }

    fun metadata(team: AgentTeamExecutionSnapshot, member: AgentTeamMemberSnapshot,
        observation: CollaborationMemberObservation?): CollaborationTranscriptMetadata {
        val interrupted = team.state == AgentTeamExecutionState.INTERRUPTED
        val active = !member.status.isTerminal
        val applicable = observation?.takeIf { active && it.atMillis >= member.executionStartedAtMillis }
        val confirmedAfterInterruption = applicable?.confirmed == true && applicable.atMillis > team.interruptedAtMillis &&
            applicable.connectionState.isBlank()
        val connection = if (!active || team.paused) "" else applicable?.connectionState?.takeIf(String::isNotBlank)
            ?: if (interrupted && !confirmedAfterInterruption && member.status == AgentSubagentStatus.RUNNING)
                "reconciling" else ""
        return CollaborationTranscriptMetadata(member.personId, member.displayName, member.providerLabel,
            member.role, member.status, team.supervisorRunId,
            waiting = member.waitingForDependencies, primary = member.memberId == team.primaryMemberId,
            summary = applicable?.summary.orEmpty(), researchStage = member.researchStage,
            executionMemberId = member.memberId, paused = team.paused,
            goalDisposition = if (member.memberId == team.primaryMemberId) team.goalDisposition else "",
            startedAtMillis = member.executionStartedAtMillis, completedAtMillis = member.completedAtMillis,
            clockStoppedAtMillis = if (team.paused || team.state.isTerminal && !interrupted)
                team.updatedAtMillis else 0L,
            connectionState = connection, current = true,
            updatedAtMillis = maxOf(member.updatedAtMillis, applicable?.atMillis ?: 0L),
            dependencies = member.pendingDependencyNames.joinToString(", "))
    }

    fun status(team: AgentTeamExecutionSnapshot, observations: Map<String, CollaborationMemberObservation>): ConversationHubAgentStatus = when {
        team.state == AgentTeamExecutionState.CANCELLED -> ConversationHubAgentStatus.CANCELLED
        team.paused -> ConversationHubAgentStatus.PAUSED
        team.goalDisposition == "blocked" -> ConversationHubAgentStatus.BLOCKED
        team.goalDisposition == "continue" && members(team).all { it.status.isTerminal } -> ConversationHubAgentStatus.QUEUED
        team.state == AgentTeamExecutionState.INTERRUPTED || team.state == AgentTeamExecutionState.RUNNING -> {
            val running = members(team).filter { it.status == AgentSubagentStatus.RUNNING }
            val states = running.map { metadata(team, it, observations[it.memberId]).connectionState }
            when {
                states.any { it.isBlank() } -> ConversationHubAgentStatus.RUNNING
                states.isNotEmpty() && states.all { it == "delivering" } -> ConversationHubAgentStatus.DELIVERING
                states.isNotEmpty() && states.all { it == "remote_paused" } -> ConversationHubAgentStatus.WAITING_RESPONSE
                states.isNotEmpty() && states.all { it == "remote_queued" } -> ConversationHubAgentStatus.QUEUED
                team.state == AgentTeamExecutionState.RUNNING && states.isEmpty() -> ConversationHubAgentStatus.QUEUED
                else -> ConversationHubAgentStatus.RECONNECTING
            }
        }
        team.state == AgentTeamExecutionState.QUEUED -> ConversationHubAgentStatus.QUEUED
        team.state == AgentTeamExecutionState.FAILED -> ConversationHubAgentStatus.FAILED
        else -> ConversationHubAgentStatus.DELIVERING
    }
}

/** Background writers hydrate a small read-only UI projection; rendering performs no database I/O. */
internal object CollaborationCurrentStateStore {
    private val teams = linkedMapOf<String, AgentTeamExecutionSnapshot>()
    private val observations = linkedMapOf<String, CollaborationMemberObservation>()
    private val loaded = hashSetOf<String>()
    private val persistenceLock = Any()
    private var writesSinceTrim = 0
    private fun key(run: String, member: String) = "$run:$member"
    private fun db(context: Context) = AgentEncryptedDatabase(context.applicationContext, "collaboration_current_observations")

    fun publish(context: Context, team: AgentTeamExecutionSnapshot) {
        if (team.members.none { it.collaborationGroupId == team.conversationId }) return
        if (synchronized(this) { teams[team.supervisorRunId]?.updatedAtMillis ?: 0L } > team.updatedAtMillis) return
        CollaborationCurrentStatePolicy.members(team).forEach { member ->
            val key = key(team.supervisorRunId, member.memberId)
            if (synchronized(this) { loaded.add(key) }) {
                val restored = runCatching { JSONObject(db(context).readString(key, "")) }.getOrNull()
                if (restored != null) observeMemory(key, CollaborationMemberObservation(restored.optLong("at"),
                    restored.optString("summary"), restored.optString("connection"), restored.optBoolean("confirmed")))
            }
        }
        synchronized(this) {
            if ((teams[team.supervisorRunId]?.updatedAtMillis ?: 0L) > team.updatedAtMillis) return
            teams[team.supervisorRunId] = team
            while (teams.size > 64) teams.remove(teams.keys.first())
            trim()
        }
    }

    fun observe(context: Context, metadata: CollaborationTranscriptMetadata, observation: CollaborationMemberObservation) {
        val key = key(metadata.runId, metadata.executionMemberId)
        if (!observeMemory(key, observation)) return
        synchronized(this) { loaded.add(key); trim() }
        // Disk work must never hold the monitor used by main-thread getters.
        runCatching { synchronized(persistenceLock) {
            if (synchronized(this) { observations[key] } != observation) return
            val database = db(context)
            database.writeString(key, JSONObject().put("at", observation.atMillis).put("summary", observation.summary)
                .put("connection", observation.connectionState).put("confirmed", observation.confirmed).toString())
            if (++writesSinceTrim >= 128) {
                writesSinceTrim = 0
                val keys = database.keys("")
                if (keys.size > 4096) database.mutateStrings(emptyMap(), database.oldestKeys("", keys.size - 4096))
            }
        } }.onFailure { android.util.Log.w("CollaborationState", "Could not persist progress projection", it) }
    }

    @Synchronized
    private fun observeMemory(key: String, value: CollaborationMemberObservation): Boolean {
        val old = observations[key]
        if (old != null && (value.atMillis < old.atMillis || value == old)) return false
        observations[key] = value
        return true
    }

    private fun trim() {
        while (observations.size > 4096) observations.remove(observations.keys.first())
        if (loaded.size > 4096) loaded.retainAll(observations.keys)
    }

    @Synchronized fun team(run: String): AgentTeamExecutionSnapshot? = teams[run]
    @Synchronized fun latest(conversation: String): AgentTeamExecutionSnapshot? = teams.values
        .filter { it.conversationId == conversation }.maxByOrNull { it.createdAtMillis }
    @Synchronized fun metadata(team: AgentTeamExecutionSnapshot, member: AgentTeamMemberSnapshot) =
        CollaborationCurrentStatePolicy.metadata(team, member, observations[key(team.supervisorRunId, member.memberId)])
    @Synchronized fun status(team: AgentTeamExecutionSnapshot) = CollaborationCurrentStatePolicy.status(team,
        team.members.mapNotNull { member -> observations[key(team.supervisorRunId, member.memberId)]?.let { member.memberId to it } }.toMap())

    @Synchronized fun entries(conversation: String): List<AgentTranscriptEntry> {
        val team = latest(conversation) ?: return emptyList()
        return CollaborationCurrentStatePolicy.members(team).map { member ->
            val key = "collaboration-current:${team.supervisorRunId}:${member.personId}"
            AgentTranscriptEntry(key, AgentTranscriptRole.PROCESS, member.role, team.createdAtMillis,
                dedupeKey = key, conversationId = conversation, taskId = team.taskId,
                collaborationJson = metadata(team, member).encode())
        }
    }
}
