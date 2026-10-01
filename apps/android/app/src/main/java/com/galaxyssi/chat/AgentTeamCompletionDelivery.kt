package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray

interface AgentTeamCompletionSink {
    fun publish(snapshot: AgentTeamExecutionSnapshot): Boolean

    fun remove(supervisorRunId: String) = Unit

    fun clear() = Unit
}

/** Delivers exactly one supervised team result into the originating Agent task. */
internal class AgentConnectorTeamCompletionSink(
    context: Context,
    private val ledger: AgentTeamCompletionDeliveryLedger = AgentTeamCompletionDeliveryLedger(context)
) : AgentTeamCompletionSink {
    private val appContext = context.applicationContext
    private val recovery = AgentTeamParentDeliveryRecovery(appContext)

    override fun publish(snapshot: AgentTeamExecutionSnapshot): Boolean {
        if (snapshot.state !in DELIVERABLE_STATES) return false
        if (ledger.contains(snapshot.supervisorRunId)) return false
        if (recovery.committed(snapshot)) {
            ledger.mark(snapshot.supervisorRunId)
            return false
        }
        if (!recovery.prepare(snapshot)) return false
        val source = AgentTeamDispatchIds.sourceMessageId(snapshot.supervisorRunId)
        val contact = AgentTeamDispatchIds.responseContactId(snapshot.teamId)
        if (AgentConnectorResponseStore.pending(appContext).any {
                it.sourceMessageId == source && it.contactId == contact && it.conversationId == snapshot.conversationId &&
                    it.turnId == snapshot.taskId }) return false
        val primaryOutput = snapshot.finalOutput.trim()
        val successful = primaryOutput.isNotBlank() && snapshot.state in setOf(
            AgentTeamExecutionState.SUCCEEDED,
            AgentTeamExecutionState.COMPLETED_WITH_FAILURES
        )
        val content = if (successful) {
            primaryOutput
        } else {
            snapshot.members.asSequence()
                .map(AgentTeamMemberSnapshot::errorMessage)
                .firstOrNull(String::isNotBlank)
                ?.let {
                    appContext.getString(
                        R.string.agent_team_failed_response_with_reason,
                        it.take(MAX_ERROR_CHARACTERS)
                    )
                }
                ?: appContext.getString(R.string.agent_team_failed_response)
        }
        AgentConnectorResponseBus.publish(
            appContext,
            AgentConnectorResponse(
                sourceMessageId = AgentTeamDispatchIds.sourceMessageId(snapshot.supervisorRunId),
                contactId = AgentTeamDispatchIds.responseContactId(snapshot.teamId),
                content = content.take(MAX_OUTPUT_CHARACTERS),
                conversationId = snapshot.conversationId,
                turnId = snapshot.taskId,
                taskId = snapshot.taskId,
                success = successful,
                receivedAtMillis = snapshot.updatedAtMillis.coerceAtLeast(System.currentTimeMillis())
            )
        )
        // Publishing is not an acknowledgement. A later sweep checks the canonical transcript commit.
        return true
    }

    override fun clear() = ledger.clear()

    override fun remove(supervisorRunId: String) = ledger.remove(supervisorRunId)

    private companion object {
        val DELIVERABLE_STATES = setOf(
            AgentTeamExecutionState.SUCCEEDED,
            AgentTeamExecutionState.COMPLETED_WITH_FAILURES,
            AgentTeamExecutionState.FAILED,
            AgentTeamExecutionState.CANCELLED
        )
        const val MAX_OUTPUT_CHARACTERS = 24_000
        const val MAX_ERROR_CHARACTERS = 1_000
    }
}

internal class AgentTeamCompletionDeliveryLedger(context: Context) {
    private val database = AgentEncryptedPreferences(context.applicationContext, DATABASE)

    @Synchronized
    fun contains(supervisorRunId: String): Boolean = supervisorRunId.trim() in read()

    @Synchronized
    fun mark(supervisorRunId: String) {
        val clean = supervisorRunId.trim()
        if (clean.isBlank()) return
        val values = read().filterNot { it == clean }.plus(clean).takeLast(MAX_RECORDS)
        database.writeString(KEY_DELIVERED, JSONArray(values).toString())
    }

    @Synchronized
    fun remove(supervisorRunId: String) {
        val clean = supervisorRunId.trim()
        if (clean.isBlank()) return
        database.writeString(KEY_DELIVERED, JSONArray(read().filterNot { it == clean }).toString())
    }

    @Synchronized
    fun clear() = database.clear()

    private fun read(): List<String> = runCatching {
        val array = JSONArray(database.readString(KEY_DELIVERED, "[]"))
        buildList {
            for (index in 0 until array.length()) {
                array.optString(index).trim().takeIf(String::isNotBlank)?.let(::add)
            }
        }
    }.getOrDefault(emptyList())

    private companion object {
        const val DATABASE = "galaxyssi_agent_team_completion_v1"
        const val KEY_DELIVERED = "committed_supervisor_runs_v2"
        const val MAX_RECORDS = 512
    }
}
