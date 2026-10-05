package com.galaxyssi.chat

/** Restores the original host-owned assignment; never chooses a new member by provider or name. */
internal object CollaborationLateResult {
    fun execution(checkpoint: AgentTeamExecutionCheckpoint, response: AgentManagedResponseRecord): AgentTeamMemberExecutionContext? {
        val request = checkpoint.request
        if (response.supervisorRunId != request.runId ||
            response.conversationId.isNotBlank() && response.conversationId != request.conversationId) return null
        val member = checkpoint.definition.members.singleOrNull {
            it.deliveryMode != AgentDeliveryMode.IGNORE &&
                stableAgentTeamMemberRunId(request.runId, it.memberId) == response.ownerRunId
        } ?: return null
        return AgentTeamMemberExecutionContext(member,
            request.copy(parentRunId = request.runId, runId = response.ownerRunId,
                deliveryMode = member.deliveryMode, idempotencyKey = "${request.idempotencyKey}:${member.memberId}",
                context = request.context + member.context + mapOf("team_id" to checkpoint.definition.teamId,
                    "team_role" to member.role, "agent_instance_id" to member.memberId)),
            AgentSubagentContextHandoff("", emptyList(), 0, 0, false), 1,
            AgentSubagentProvenance(source = "late-managed-response", sourceId = response.sourceMessageId.toString()))
    }
}
