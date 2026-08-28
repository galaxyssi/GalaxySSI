package com.signalasi.chat

internal object AgentProviderConversationPolicy {
    fun shouldPersistDedicatedHistory(agentConversationId: String): Boolean =
        agentConversationId.isBlank()
}
