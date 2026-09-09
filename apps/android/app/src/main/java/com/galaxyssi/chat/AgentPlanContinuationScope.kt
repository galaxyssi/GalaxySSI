package com.galaxyssi.chat

/** Recover scope from persisted current actions, never from unrelated history. */
internal data class AgentPlanContinuationScope(val conversationId: String, val turnId: String) {
    fun owns(action: AgentAction): Boolean {
        val owner = action.parameters[INTERNAL_CONVERSATION_ID].orEmpty()
        val turn = action.parameters[INTERNAL_TURN_ID].orEmpty()
        return (owner.isBlank() || owner == conversationId) &&
            (turn.isBlank() || turnId.isBlank() || turn == turnId)
    }

    fun bind(action: AgentAction): AgentAction = action.copy(parameters = action.parameters + mapOf(
        INTERNAL_CONVERSATION_ID to conversationId,
        INTERNAL_TURN_ID to turnId
    ))

    fun context(source: AgentConversationContext) = AgentConversationContext(
        conversationId, "", emptyList(), source.privateMode, trackingPaused = source.trackingPaused
    )

    companion object {
        fun resolve(
            plan: AgentPlan,
            activeConversationId: String,
            activeTurnId: String,
            sessionId: String
        ): AgentPlanContinuationScope? {
            fun identifiers(key: String, active: String) = (plan.actions.map {
                it.parameters[key].orEmpty()
            } + active).filter(String::isNotBlank).distinct()
            val conversations = identifiers(INTERNAL_CONVERSATION_ID, activeConversationId)
            // A new control message can request continuation without owning the running task.
            val turns = identifiers(INTERNAL_TURN_ID, "")
            if (conversations.size > 1 || turns.size > 1) return null
            return AgentPlanContinuationScope(conversations.singleOrNull() ?: sessionId,
                turns.singleOrNull() ?: activeTurnId)
        }
    }
}
