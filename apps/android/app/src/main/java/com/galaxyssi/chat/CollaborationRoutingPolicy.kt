package com.galaxyssi.chat

/** Explicit group membership precedes heuristic single-provider/phone-plan routing. */
internal object CollaborationRoutingPolicy {
    fun seed(turnId: String, members: List<AgentRequestedMember>): AgentAction? {
        val first = members.firstOrNull() ?: return null
        if (first.collaborationGroupId.isBlank() || members.any { it.collaborationGroupId != first.collaborationGroupId }) return null
        return AgentAction(id = "collaboration-seed-$turnId", kind = AgentActionKind.CALL_CONNECTOR,
            target = first.displayName, risk = AgentRisk.LOW, status = AgentActionStatus.PROPOSED,
            description = "Dispatch to the explicitly selected collaboration group",
            parameters = mapOf("connector_id" to first.agentId), requiresConfirmation = false)
    }
}
