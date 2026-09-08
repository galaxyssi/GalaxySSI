package com.galaxyssi.chat

/** A caller's key identifies an effect only within its original execution scope. */
data class AgentNativeEffectScope(
    val clientRouteId: String = "",
    val sessionId: String = "",
    val conversationId: String = "",
    val goalId: String = "",
    val taskId: String = "",
    val turnId: String = ""
) {
    fun toJsonValue(): Map<String, String> = linkedMapOf(
        "client_route_id" to clientRouteId, "session_id" to sessionId,
        "conversation_id" to conversationId, "goal_id" to goalId,
        "task_id" to taskId, "turn_id" to turnId
    )

    companion object {
        fun from(context: AgentNativeToolInvocationContext) = AgentNativeEffectScope(
            context.attributes["client_route_id"].orEmpty(), context.sessionId,
            context.conversationId, context.attributes["goal_id"].orEmpty(),
            context.attributes["task_id"].orEmpty(), context.turnId
        )
    }
}

data class AgentNativeEffectClaim(
    val acquired: Boolean,
    val invocationId: String,
    val inputSha256: String,
    val result: AgentNativeToolResult? = null
)

internal fun AgentNativeToolReplayKey.identity(): Map<String, Any> = linkedMapOf(
    "tool_id" to toolId, "tool_version" to toolVersion,
    "idempotency_key" to idempotencyKey, "scope" to scope.toJsonValue()
)
