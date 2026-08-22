package com.signalasi.chat

import java.lang.ref.WeakReference

internal object AgentConversationTransportCache {
    private data class CachedTransport(
        val context: WeakReference<AgentConversationContext>,
        val maximumTokens: Int,
        val value: String
    )

    private val cacheLock = Any()
    private val cachedTransports = mutableListOf<CachedTransport>()

    fun render(context: AgentConversationContext, maximumTokens: Int): String = synchronized(cacheLock) {
        cachedTransports.removeAll { cached -> cached.context.get() == null }
        val cachedIndex = cachedTransports.indexOfFirst { cached ->
            cached.context.get() === context && cached.maximumTokens == maximumTokens
        }
        if (cachedIndex >= 0) {
            val cached = cachedTransports.removeAt(cachedIndex)
            cachedTransports += cached
            return@synchronized cached.value
        }

        val value = context.asTransportBlock(maximumTokens)
        cachedTransports += CachedTransport(
            context = WeakReference(context),
            maximumTokens = maximumTokens,
            value = value
        )
        while (cachedTransports.size > MAX_CACHED_TRANSPORTS) {
            cachedTransports.removeAt(0)
        }
        value
    }

    private const val MAX_CACHED_TRANSPORTS = 8
}
