package com.galaxyssi.chat

internal object AgentProviderConversationPolicy {
    fun shouldPersistDedicatedHistory(agentConversationId: String): Boolean =
        agentConversationId.isBlank()
}
