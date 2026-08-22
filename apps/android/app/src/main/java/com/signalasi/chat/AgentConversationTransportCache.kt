package com.signalasi.chat

import java.lang.ref.WeakReference

internal object AgentConversationTransportCache {
    private data class CachedTransport(
        val context: WeakReference<AgentConversationContext>,
        val maximumTokens: Int,
        val currentGoal: String,
        val value: String
    )

    private val cacheLock = Any()
    private val cachedTransports = mutableListOf<CachedTransport>()

    fun render(
        context: AgentConversationContext,
        maximumTokens: Int,
        currentGoal: String = ""
    ): String {
        val normalizedGoal = currentGoal.trim()
        synchronized(cacheLock) {
            takeCached(context, maximumTokens, normalizedGoal)
        }?.let { cached ->
            return cached.value
        }

        val transportContext = context.withoutDuplicatedLatestUserText(normalizedGoal)
        val value = if (transportContext.turns.isEmpty() && transportContext.summary.isBlank()) {
            ""
        } else {
            transportContext.asTransportBlock(maximumTokens)
        }
        return synchronized(cacheLock) {
            val cached = takeCached(context, maximumTokens, normalizedGoal)
            if (cached != null) return@synchronized cached.value
            value.also {
                cachedTransports += CachedTransport(
                    context = WeakReference(context),
                    maximumTokens = maximumTokens,
                    currentGoal = normalizedGoal,
                    value = value
                )
                while (cachedTransports.size > MAX_CACHED_TRANSPORTS) {
                    cachedTransports.removeAt(0)
                }
            }
        }
    }

    private fun takeCached(
        context: AgentConversationContext,
        maximumTokens: Int,
        currentGoal: String
    ): CachedTransport? {
        cachedTransports.removeAll { cached -> cached.context.get() == null }
        val cachedIndex = cachedTransports.indexOfFirst { cached ->
            cached.context.get() === context &&
                cached.maximumTokens == maximumTokens &&
                cached.currentGoal == currentGoal
        }
        if (cachedIndex < 0) return null
        return cachedTransports.removeAt(cachedIndex).also { cached -> cachedTransports += cached }
    }

    private const val MAX_CACHED_TRANSPORTS = 8
}
