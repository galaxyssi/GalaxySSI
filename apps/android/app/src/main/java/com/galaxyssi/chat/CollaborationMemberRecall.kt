package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

internal object CollaborationMemberRecall {
    const val FLAG = "scoped_member_recall_v1"
    enum class Generation { CURRENT, NEXT, UNAVAILABLE }
    data class Probe(val binding: CollaborationWorkspaceAccess, val generation: Generation = Generation.CURRENT)

    fun generation(observed: Long?, requested: Long): Generation = when {
        requested == (observed ?: 1L) && requested > 0 -> Generation.CURRENT
        requested > 1 && observed == requested - 1 -> Generation.NEXT
        else -> Generation.UNAVAILABLE
    }

    fun codexContact(contact: JSONObject?, desktop: String): Boolean = desktop.isNotBlank() && contact != null &&
        !contact.optBoolean("deleted") && contact.optString("trust_state") == "verified" &&
        contact.optString("desktop_id") == desktop && contact.optString("delivery_mode") == "pc_connector" &&
        contact.optString("agent_id") == "codex"

    fun assignment(context: Context, delivery: AgentPendingDelivery): CollaborationWorkspaceAccess? {
        val binding = CollaborationEvidenceLedger(context).binding(delivery.sourceMessageId,
            delivery.conversationId, delivery.turnId) ?: return null
        val owner = EncryptedAgentManagedResponseLedger(context).pendingOwner(delivery) ?: return null
        return binding.takeIf { matches(it, owner, CollaborationGroupStore(context).load(it.groupId),
            AgentTeamDurableControl(context).get(it.runId)) }
    }

    internal fun matches(binding: CollaborationWorkspaceAccess, owner: AgentManagedResponseRecord,
        group: CollaborationGroup?, control: AgentTeamUserControl): Boolean =
        control == AgentTeamUserControl.RUN && owner.state == AgentManagedResponseState.PENDING &&
            owner.deliveryMode == AgentDeliveryMode.RESPOND && binding.groupId == owner.conversationId &&
            binding.turnId == owner.turnId && binding.runId == owner.supervisorRunId &&
            binding.nodeId.isNotBlank() && binding.personId.isNotBlank() &&
            (owner.agentId == owner.contactId || owner.agentId == "codex") &&
            owner.ownerRunId == stableAgentTeamMemberRunId(binding.runId, binding.nodeId) &&
            group?.conversationId == binding.groupId &&
            group.members.singleOrNull { it.id == binding.personId }?.agentId == owner.agentId

    /** No data-phase callback is available here, including on replay. */
    fun authorize(replies: CollaborationExchangeReplay, lease: CollaborationExchangeReplay.Lease,
        access: () -> Probe?): JSONObject {
        val first = access() ?: return CollaborationRemoteRecallProtocol.unavailable()
        val last = access() ?: return CollaborationRemoteRecallProtocol.unavailable()
        if (first.binding != last.binding || first.generation == Generation.UNAVAILABLE ||
            last.generation == Generation.UNAVAILABLE) return CollaborationRemoteRecallProtocol.unavailable()
        // A status event may arrive mid-check. Only promote after two exact current observations.
        if (first.generation != last.generation && (last.generation != Generation.CURRENT || access() != last))
            return CollaborationRemoteRecallProtocol.unavailable()
        val waiting = last.generation == Generation.NEXT
        if (!replies.pinAuthorization(lease, last.binding, waiting)) return CollaborationRemoteRecallProtocol.unavailable()
        return if (waiting) JSONObject().put("success", false).put("status", "generation_not_ready")
            else JSONObject().put("success", true).put("status", "authorized")
    }
}
