package com.galaxyssi.chat

import java.lang.ref.WeakReference

internal object AgentSupervisedProjectContextCache {
    private data class CachedContext(
        val conversationContext: WeakReference<AgentConversationContext>,
        val goal: String,
        val value: String?
    )

    private val cacheLock = Any()
    private val cachedContexts = mutableListOf<CachedContext>()

    fun render(request: AgentRequest): String? {
        synchronized(cacheLock) {
            takeCached(request)
        }?.let { cached ->
            return cached.value
        }

        val value = AgentSupervisedProjectContext.promptBlock(request)
        return synchronized(cacheLock) {
            val cached = takeCached(request)
            if (cached != null) return@synchronized cached.value
            value.also {
                cachedContexts += CachedContext(
                    conversationContext = WeakReference(request.conversationContext),
                    goal = request.goal,
                    value = value
                )
                while (cachedContexts.size > MAX_CACHED_CONTEXTS) {
                    cachedContexts.removeAt(0)
                }
            }
        }
    }

    private fun takeCached(request: AgentRequest): CachedContext? {
        cachedContexts.removeAll { cached -> cached.conversationContext.get() == null }
        val cachedIndex = cachedContexts.indexOfFirst { cached ->
            cached.conversationContext.get() === request.conversationContext &&
                cached.goal == request.goal
        }
        if (cachedIndex < 0) return null
        return cachedContexts.removeAt(cachedIndex).also { cached -> cachedContexts += cached }
    }

    private const val MAX_CACHED_CONTEXTS = 8
}
