package com.signalasi.chat

internal object LocalModelConversationPolicy {
    fun shouldPersistDedicatedHistory(agentConversationId: String): Boolean =
        agentConversationId.isBlank()
}
