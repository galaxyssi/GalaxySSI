package com.signalasi.chat

import java.lang.ref.WeakReference

internal object AgentSupervisedProjectContextCache {
    private data class CachedContext(
        val conversationContext: WeakReference<AgentConversationContext>,
        val goal: String,
        val value: String?
    )

    private val cacheLock = Any()
    private val cachedContexts = mutableListOf<CachedContext>()

    fun render(request: AgentRequest): String? = synchronized(cacheLock) {
        cachedContexts.removeAll { cached -> cached.conversationContext.get() == null }
        val cachedIndex = cachedContexts.indexOfFirst { cached ->
            cached.conversationContext.get() === request.conversationContext &&
                cached.goal == request.goal
        }
        if (cachedIndex >= 0) {
            val cached = cachedContexts.removeAt(cachedIndex)
            cachedContexts += cached
            return@synchronized cached.value
        }

        val value = AgentSupervisedProjectContext.promptBlock(request)
        cachedContexts += CachedContext(
            conversationContext = WeakReference(request.conversationContext),
            goal = request.goal,
            value = value
        )
        while (cachedContexts.size > MAX_CACHED_CONTEXTS) {
            cachedContexts.removeAt(0)
        }
        value
    }

    private const val MAX_CACHED_CONTEXTS = 8
}
