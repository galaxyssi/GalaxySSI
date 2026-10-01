package com.galaxyssi.chat

import android.content.Context

internal object AgentTeamRemoteStopPolicy {
    fun owns(team: AgentTeamExecutionSnapshot, record: AgentManagedResponseRecord): Boolean =
        record.state == AgentManagedResponseState.PENDING && record.supervisorRunId == team.supervisorRunId &&
            record.conversationId == team.conversationId && record.sourceMessageId > 0 &&
            record.contactId.isNotBlank() && record.turnId.isNotBlank() && record.taskId.isNotBlank() &&
            team.members.any { stableAgentTeamMemberRunId(team.supervisorRunId, it.memberId) == record.ownerRunId }

    fun due(lastAttempt: Long, now: Long): Boolean = lastAttempt <= 0 || now < lastAttempt || now - lastAttempt >= 60_000L
}

/** Pending managed records are the durable stop outbox; receipt of a terminal reply retires them. */
internal class AgentTeamRemoteStopRecovery(private val context: Context) {
    private val attempts = AgentEncryptedDatabase(context.applicationContext, "agent_team_stop_attempts_v1")

    fun reconcile(teams: List<AgentTeamExecutionSnapshot>, ledger: AgentManagedResponseLedger,
                  isStopped: (String) -> Boolean) {
        if (!GalaxySSIMqttClient.isRequestReplyReady()) return
        teams.filter { isStopped(it.supervisorRunId) }.forEach { team ->
            ledger.pendingForSupervisor(team.supervisorRunId).forEach recordLoop@ { record ->
                if (!AgentTeamRemoteStopPolicy.owns(team, record)) return@recordLoop
                val contact = AppStore.contactById(context, record.contactId) ?: return@recordLoop
                if (contact.optString("desktop_id").isBlank()) return@recordLoop
                val now = System.currentTimeMillis()
                val claimed = synchronized(LOCK) {
                    val last = attempts.readString(record.ownerRunId, "0").toLongOrNull() ?: 0L
                    if (!AgentTeamRemoteStopPolicy.due(last, now)) false else {
                        attempts.writeString(record.ownerRunId, now.toString())
                        true
                    }
                }
                if (claimed) GalaxySSIMqttClient.publishAgentTaskCancel(
                    taskId = record.taskId, contactId = record.contactId,
                    sourceMessageId = record.sourceMessageId, conversationId = record.conversationId,
                    turnId = record.turnId,
                    topicOverride = AppStore.outgoingTopicForContact(context, record.contactId)
                )
            }
        }
    }

    private companion object { val LOCK = Any() }
}
