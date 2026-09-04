package com.galaxyssi.chat

import java.util.concurrent.ConcurrentHashMap

internal class AgentPreparedConversationContextCache {
    private data class VersionedContext(
        val version: Long,
        val context: AgentConversationContext
    )

    private val contexts = ConcurrentHashMap<String, VersionedContext>()
    private val versions = ConcurrentHashMap<String, Long>()
    private val compilationLocks = Array(COMPILATION_LOCK_STRIPES) { Any() }

    fun get(conversationId: String): AgentConversationContext? =
        contexts[conversationId.trim()]?.context

    fun version(conversationId: String): Long = versions[conversationId.trim()] ?: 0L

    fun getOrCompute(
        conversationId: String,
        compute: () -> AgentConversationContext
    ): AgentConversationContext {
        val normalizedId = conversationId.trim()
        get(normalizedId)?.let { return it }
        val lock = compilationLocks[Math.floorMod(normalizedId.hashCode(), compilationLocks.size)]
        return synchronized(lock) {
            while (true) {
                get(normalizedId)?.let { return@synchronized it }
                val expectedVersion = version(normalizedId)
                val prepared = compute()
                require(prepared.conversationId.trim() == normalizedId) {
                    "Prepared context must match its conversation"
                }
                if (putIfCurrent(prepared, expectedVersion)) return@synchronized prepared
            }
            error("Unreachable")
        }
    }

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

    private companion object {
        const val COMPILATION_LOCK_STRIPES = 64
    }
}

internal object AgentPreparedConversationContextCacheRegistry {
    val shared = AgentPreparedConversationContextCache()
}
