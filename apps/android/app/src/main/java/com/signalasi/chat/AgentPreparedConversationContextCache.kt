package com.signalasi.chat

import java.util.concurrent.ConcurrentHashMap

internal class AgentPreparedConversationContextCache {
    private data class VersionedContext(
        val version: Long,
        val context: AgentConversationContext
    )

    private val contexts = ConcurrentHashMap<String, VersionedContext>()
    private val versions = ConcurrentHashMap<String, Long>()

    fun get(conversationId: String): AgentConversationContext? =
        contexts[conversationId.trim()]?.context

    fun version(conversationId: String): Long = versions[conversationId.trim()] ?: 0L

    @Synchronized
    fun putIfCurrent(context: AgentConversationContext, expectedVersion: Long): Boolean {
        val conversationId = context.conversationId.trim()
        if (version(conversationId) != expectedVersion) return false
        contexts[conversationId] = VersionedContext(expectedVersion, context)
        return true
    }

    @Synchronized
    fun invalidate(conversationId: String) {
        val normalizedId = conversationId.trim()
        versions[normalizedId] = version(normalizedId) + 1L
        contexts.remove(normalizedId)
    }

    fun invalidate(conversationIds: Iterable<String>) {
        conversationIds.forEach(::invalidate)
    }

    fun invalidateTranscriptMutation(conversationId: String, role: AgentTranscriptRole) {
        if (role != AgentTranscriptRole.PROCESS) invalidate(conversationId)
    }

    @Synchronized
    fun clear() {
        contexts.clear()
        versions.clear()
    }
}
