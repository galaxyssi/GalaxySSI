package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

internal enum class AgentManagedBrowserState { READY, PAUSED, STOPPED, OBSOLETE, DELIVERED, UNVERIFIED }

/** A member assignment is not the ordinary parent UI Run or its file workspace. */
internal data class AgentManagedBrowserOwner(val ownerRunId: String, val supervisorRunId: String,
    val memberId: String, val assignmentSha256: String, val groupId: String) {
    fun toJson() = JSONObject().put("owner", ownerRunId).put("supervisor", supervisorRunId)
        .put("member", memberId).put("assignment", assignmentSha256).put("group", groupId)

    companion object {
        fun fromJson(value: JSONObject) = AgentManagedBrowserOwner(value.getString("owner"), value.getString("supervisor"),
            value.getString("member"), value.getString("assignment"), value.getString("group")).also {
            require(it.ownerRunId == stableAgentTeamMemberRunId(it.supervisorRunId, it.memberId) &&
                it.supervisorRunId.isNotBlank() && it.memberId.isNotBlank() && it.assignmentSha256.matches(Regex("[a-f0-9]{64}")))
        }

        fun capture(id: AgentLocalDispatchIdentity, record: AgentManagedResponseRecord,
            checkpoint: AgentTeamExecutionCheckpoint): AgentManagedBrowserOwner? {
            if (!correlates(id, record)) return null
            val execution = CollaborationLateResult.execution(checkpoint, record) ?: return null
            val member = execution.member
            if (record.agentId != member.agentId || record.deliveryMode != member.deliveryMode ||
                id.sourceMessageId != AgentTeamDispatchIds.sourceMessageId("member:${execution.request.idempotencyKey}") ||
                checkpoint.request.messageId != id.turnId || checkpoint.request.taskId != id.taskId) return null
            val request = checkpoint.request
            val binding = AgentNativeJsonCodec.sha256(mapOf("supervisor" to request.runId, "team" to checkpoint.definition.teamId,
                "conversation" to request.conversationId, "turn" to request.messageId, "task" to request.taskId,
                "goal" to request.goal, "idempotency" to request.idempotencyKey, "member" to member.memberId,
                "agent" to member.agentId, "delivery" to member.deliveryMode.name, "role" to member.role,
                "objective" to member.objective, "dependencies" to member.dependsOnAgentIds.sorted(),
                "capabilities" to member.requiredCapabilities.map { it.name }.sorted(), "context" to member.context))
            return AgentManagedBrowserOwner(record.ownerRunId, record.supervisorRunId, member.memberId, binding,
                member.context["collaboration_group_id"].orEmpty())
        }

        fun correlates(id: AgentLocalDispatchIdentity, record: AgentManagedResponseRecord): Boolean =
            id.actionId == "team-${record.ownerRunId}" && record.sourceMessageId == id.sourceMessageId &&
                record.contactId == id.contactId && record.conversationId == id.conversationId &&
                record.turnId == id.turnId && record.taskId == id.taskId

        fun decide(owner: AgentManagedBrowserOwner, id: AgentLocalDispatchIdentity,
            record: AgentManagedResponseRecord?, checkpoint: AgentTeamExecutionCheckpoint?, snapshot: AgentTeamExecutionSnapshot?,
            control: AgentTeamUserControl): AgentManagedBrowserState {
            if (record == null || record.ownerRunId != owner.ownerRunId || record.supervisorRunId != owner.supervisorRunId ||
                !correlates(id, record)) return AgentManagedBrowserState.UNVERIFIED
            if (record.state != AgentManagedResponseState.PENDING) return AgentManagedBrowserState.DELIVERED
            if (control == AgentTeamUserControl.STOP) return AgentManagedBrowserState.STOPPED
            if (checkpoint == null || snapshot == null) return AgentManagedBrowserState.UNVERIFIED
            if (capture(id, record, checkpoint) != owner) return AgentManagedBrowserState.OBSOLETE
            if (snapshot.supervisorRunId != owner.supervisorRunId || snapshot.teamId != checkpoint.definition.teamId ||
                snapshot.conversationId != id.conversationId || snapshot.taskId != id.taskId) return AgentManagedBrowserState.UNVERIFIED
            val member = snapshot.members.singleOrNull { it.memberId == owner.memberId }
                ?: return AgentManagedBrowserState.OBSOLETE
            if (member.status.isTerminal || owner.memberId in checkpoint.completed ||
                snapshot.state.isTerminal && snapshot.state != AgentTeamExecutionState.INTERRUPTED) return AgentManagedBrowserState.OBSOLETE
            if (member.status != AgentSubagentStatus.RUNNING) return AgentManagedBrowserState.UNVERIFIED
            return if (control == AgentTeamUserControl.PAUSE || snapshot.paused) AgentManagedBrowserState.PAUSED
                else AgentManagedBrowserState.READY
        }
    }
}

internal class AgentManagedBrowserOwners(context: Context) {
    private val app = context.applicationContext
    private val ledger = EncryptedAgentManagedResponseLedger(app)

    fun capture(id: AgentLocalDispatchIdentity): AgentManagedBrowserOwner? {
        val pending = ledger.pendingRecoveryDelivery(id.sourceMessageId, id.contactId, id.conversationId, id.turnId, id.taskId)
            ?: return null
        val record = ledger.pendingOwner(pending) ?: return null
        val (checkpoint, snapshot) = AgentTeamExecutionLocations(app).state(record.supervisorRunId,
            id.conversationId, id.turnId, id.taskId)
        val owner = AgentManagedBrowserOwner.capture(id, record, checkpoint) ?: return null
        return owner.takeIf { state(it, id, record, checkpoint, snapshot) in setOf(AgentManagedBrowserState.READY, AgentManagedBrowserState.PAUSED) }
    }

    fun state(owner: AgentManagedBrowserOwner, id: AgentLocalDispatchIdentity): AgentManagedBrowserState = try {
        val record = ledger.findOwner(owner.ownerRunId)
        val control = AgentTeamDurableControl(app).get(owner.supervisorRunId)
        val early = AgentManagedBrowserOwner.decide(owner, id, record, null, null, control)
        if (early != AgentManagedBrowserState.UNVERIFIED) early else {
            val (checkpoint, snapshot) = AgentTeamExecutionLocations(app).state(owner.supervisorRunId,
                id.conversationId, id.turnId, id.taskId)
            state(owner, id, record, checkpoint, snapshot)
        }
    } catch (_: Exception) { AgentManagedBrowserState.UNVERIFIED }

    private fun state(owner: AgentManagedBrowserOwner, id: AgentLocalDispatchIdentity, record: AgentManagedResponseRecord?,
        checkpoint: AgentTeamExecutionCheckpoint, snapshot: AgentTeamExecutionSnapshot): AgentManagedBrowserState {
        val result = AgentManagedBrowserOwner.decide(owner, id, record, checkpoint, snapshot,
            AgentTeamDurableControl(app).get(owner.supervisorRunId))
        if (result !in setOf(AgentManagedBrowserState.READY, AgentManagedBrowserState.PAUSED) || owner.groupId.isBlank()) return result
        if (CollaborationGroupStore(app).load(owner.groupId) == null) return AgentManagedBrowserState.OBSOLETE
        val access = CollaborationEvidenceLedger(app).binding(id.sourceMessageId, id.conversationId, id.turnId)
        val execution = record?.let { CollaborationLateResult.execution(checkpoint, it) }
            ?: return AgentManagedBrowserState.UNVERIFIED
        return if (access == CollaborationWorkspaceAccess.from(execution)) result else AgentManagedBrowserState.UNVERIFIED
    }
}
