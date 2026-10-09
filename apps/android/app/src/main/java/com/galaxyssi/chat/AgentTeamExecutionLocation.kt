package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** Host-owned location, not a tool selector or permission to start/resume a run. */
internal data class AgentTeamExecutionLocation(
    val namespace: String,
    val runId: String,
    val conversationId: String,
    val turnId: String,
    val taskId: String,
    val teamId: String
) {
    init {
        require(namespace.matches(Regex("[A-Za-z0-9][A-Za-z0-9_.-]{0,199}"))) { "Invalid execution namespace" }
        require(listOf(runId, conversationId, turnId, taskId, teamId).all { it.isNotBlank() }) { "Incomplete execution owner" }
        require(runId == runId.trim()) { "Execution run ID must be canonical" }
    }

    fun requireAccess(access: CollaborationWorkspaceAccess) {
        require(runId == access.runId && conversationId == access.groupId && turnId == access.turnId) {
            "Execution location belongs to another task"
        }
    }

    fun encode(): String = JSONObject().put("format", FORMAT).put("namespace", namespace).put("run_id", runId)
        .put("conversation_id", conversationId).put("turn_id", turnId).put("task_id", taskId).put("team_id", teamId).toString()

    companion object {
        const val DEFAULT_NAMESPACE = "galaxyssi_agent_teams_v1"
        private const val FORMAT = "galaxyssi.team-execution-location.v1"

        fun from(namespace: String, definition: AgentTeamDefinition, request: AgentRunRequest) =
            AgentTeamExecutionLocation(namespace, request.runId, request.conversationId, request.messageId, request.taskId, definition.teamId)

        fun decode(raw: String, runId: String): AgentTeamExecutionLocation {
            val value = JSONObject(raw)
            require(value.getString("format") == FORMAT) { "Unknown execution location format" }
            return AgentTeamExecutionLocation(value.getString("namespace"), value.getString("run_id"),
                value.getString("conversation_id"), value.getString("turn_id"), value.getString("task_id"), value.getString("team_id"))
                .also { require(it.runId == runId) { "Execution location key mismatch" } }
        }
    }
}

internal class AgentTeamExecutionLocations(context: Context) {
    private val app = context.applicationContext
    private val database = AgentEncryptedDatabase(app, "galaxyssi_team_execution_locations_v1")

    private fun read(runId: String): AgentTeamExecutionLocation? {
        val raw = database.readString(runId, "")
        if (raw.isEmpty()) {
            check(!database.contains(runId)) { "Execution location is unreadable" }
            return null
        }
        return AgentTeamExecutionLocation.decode(raw, runId)
    }

    fun claim(location: AgentTeamExecutionLocation) = synchronized(LOCK) {
        val existing = read(location.runId)
        if (existing != null) {
            check(existing == location) { "A different execution store or task already owns this run" }
            return@synchronized
        }
        if (location.namespace != AgentTeamExecutionLocation.DEFAULT_NAMESPACE) {
            check(EncryptedAgentTeamExecutionStore(app).deliveryCheckpoint(location.runId) == null) {
                "The default execution store already owns this run"
            }
        }
        database.writeString(location.runId, location.encode())
    }

    fun requireOwner(runId: String, namespace: String) = synchronized(LOCK) {
        val existing = read(runId) ?: return@synchronized
        check(existing.namespace == namespace) { "Cannot release another execution store's run" }
    }

    fun release(runId: String, namespace: String) = synchronized(LOCK) {
        requireOwner(runId, namespace)
        database.remove(runId)
    }

    fun state(access: CollaborationWorkspaceAccess): Pair<AgentTeamExecutionCheckpoint, AgentTeamExecutionSnapshot> {
        val location = synchronized(LOCK) { read(access.runId) }
        location?.requireAccess(access)
        // An absent legacy binding uses the original store. A bad/missing mapped store never falls back.
        val store = EncryptedAgentTeamExecutionStore(app,
            AgentEncryptedDatabase(app, location?.namespace ?: AgentTeamExecutionLocation.DEFAULT_NAMESPACE))
        val (checkpoint, snapshot) = requireNotNull(store.executionState(access.runId)) { "Team checkpoint is unavailable" }
        if (location != null) check(location == AgentTeamExecutionLocation.from(location.namespace, checkpoint.definition, checkpoint.request)) {
            "Execution checkpoint owner differs from its registered location"
        }
        require(checkpoint.request.conversationId == access.groupId && checkpoint.request.messageId == access.turnId) {
            "Team checkpoint belongs to another task"
        }
        return checkpoint to snapshot
    }

    private companion object { val LOCK = Any() }
}

internal class AgentTeamExecutionRegistration(context: Context, private val namespace: String) {
    private val locations = AgentTeamExecutionLocations(context)
    fun claim(definition: AgentTeamDefinition, request: AgentRunRequest) =
        locations.claim(AgentTeamExecutionLocation.from(namespace, definition, request))
    fun requireOwner(runId: String) = locations.requireOwner(runId, namespace)
    fun release(runId: String) = locations.release(runId, namespace)
}
