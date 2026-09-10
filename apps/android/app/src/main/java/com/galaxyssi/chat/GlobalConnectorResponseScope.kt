package com.galaxyssi.chat

/** Structural conversation namespaces written by the global task producers. */
internal enum class GlobalConnectorResponseScope(private val prefix: String) {
    COGNITION("global-cognition:"),
    ACTION("global-run:"),
    REVIEW("global-replan:"),
    RESEARCH("global-research:");

    fun conversation(ownerId: String): String {
        require(ownerId.isNotBlank())
        return prefix + ownerId
    }

    fun matches(response: AgentConnectorResponse, ownerId: String, turnId: String? = null): Boolean =
        (response.conversationId.isEmpty() || response.conversationId == conversation(ownerId)) &&
            (turnId == null || response.turnId.isEmpty() || response.turnId == turnId)

    companion object {
        fun consume(
            response: AgentConnectorResponse,
            cognition: () -> Boolean,
            autonomous: () -> Boolean,
            research: () -> Boolean
        ): Boolean {
            if (response.sourceMessageId <= 0L) return false
            // Older durable replies can lack scope; their stores must still verify source ownership.
            if (response.conversationId.isEmpty()) return cognition() || autonomous() || research()
            val scope = entries.firstOrNull {
                response.conversationId.startsWith(it.prefix) &&
                    response.conversationId.removePrefix(it.prefix).isNotBlank()
            }
            return when (scope) {
                COGNITION -> cognition()
                ACTION, REVIEW -> autonomous()
                RESEARCH -> research()
                null -> false
            }
        }
    }
}
