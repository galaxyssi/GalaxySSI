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
internal class AgentTeamRemoteStopRecovery(
    private val isRequestReplyReady: () -> Boolean,
    private val cancelDesktop: (AgentManagedResponseRecord) -> Unit
) {
    constructor(context: Context) : this(
        { GalaxySSIMqttClient.isRequestReplyReady() }, desktopStop(context.applicationContext))

    fun reconcile(teams: List<AgentTeamExecutionSnapshot>, ledger: AgentManagedResponseLedger,
                  isStopped: (String) -> Boolean) {
        val pending = teams.filter { isStopped(it.supervisorRunId) }.flatMap { team ->
            ledger.pendingForSupervisor(team.supervisorRunId).filter { AgentTeamRemoteStopPolicy.owns(team, it) }
        }
        // An interrupted worker may have detached while its cloud request is still running.
        // Cancel only its exact lease; cancellation is not a terminal response acknowledgment.
        pending.forEach { record ->
            AgentCloudDispatchRegistry.cancelExact(AgentCloudDispatchIdentity(
                sourceMessageId = record.sourceMessageId, contactId = record.contactId,
                conversationId = record.conversationId, turnId = record.turnId, taskId = record.taskId,
                actionId = "team-${record.ownerRunId}"))
        }
        if (!isRequestReplyReady()) return
        pending.forEach(cancelDesktop)
    }

    private companion object {
        val LOCK = Any()

        fun desktopStop(context: Context): (AgentManagedResponseRecord) -> Unit {
            val attempts = AgentEncryptedDatabase(context, "agent_team_stop_attempts_v1")
            return stop@ { record ->
                val contact = AppStore.contactById(context, record.contactId) ?: return@stop
                if (contact.optString("desktop_id").isBlank()) return@stop
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
}
