package com.galaxyssi.chat

import android.content.Context

/** Carry host ownership to the transport boundary, where the actual wire identity is known. */
internal object AgentManagedDispatchIntent {
    private const val OWNER = "_galaxyssi_managed_owner"
    private const val SUPERVISOR = "_galaxyssi_managed_supervisor"
    private const val AGENT = "_galaxyssi_managed_agent"
    private const val MODE = "_galaxyssi_managed_delivery"

    fun bind(action: AgentAction, request: AgentRunRequest, agent: String): AgentAction =
        if (request.context["managed_team"]?.toString() != "true") action else action.copy(
            parameters = action.parameters + mapOf(OWNER to request.runId, SUPERVISOR to request.parentRunId,
                AGENT to agent, MODE to request.deliveryMode.name))

    fun record(action: AgentAction, source: Long, contact: String, conversation: String, turn: String,
        task: String): AgentManagedResponseRecord? {
        if (action.parameters[MANAGED_AGENT_TEAM_ACTION_PARAMETER] != "true") return null
        val owner = action.parameters[OWNER].orEmpty()
        val supervisor = action.parameters[SUPERVISOR].orEmpty()
        val member = action.parameters["agent_instance_id"].orEmpty()
        if (listOf(owner, supervisor, member, contact, conversation, turn, task).any(String::isBlank)) return null
        require(owner == stableAgentTeamMemberRunId(supervisor, member) &&
            source == AgentTeamDispatchIds.sourceMessageId("member:${action.parameters["idempotency_key"]}")) {
            "Managed dispatch identity does not match its original assignment"
        }
        return AgentManagedResponseRecord(owner, supervisor, action.parameters[AGENT].orEmpty(),
            AgentDeliveryMode.valueOf(action.parameters.getValue(MODE)), source, contact, conversation, turn, task)
    }

    fun persist(context: Context, action: AgentAction, source: Long, contact: String, conversation: String,
        turn: String, task: String) {
        record(action, source, contact, conversation, turn, task)?.let {
            EncryptedAgentManagedResponseLedger(context).register(it)
        }
    }
}
