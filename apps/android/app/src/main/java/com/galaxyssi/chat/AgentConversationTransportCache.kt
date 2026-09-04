package com.galaxyssi.chat

import java.lang.ref.WeakReference

internal object AgentConversationTransportCache {
    private data class CachedTransport(
        val context: WeakReference<AgentConversationContext>,
        val maximumTokens: Int,
        val currentGoal: String,
        val includeGlobalContext: Boolean,
        val value: String
    )

    private val cacheLock = Any()
    private val cachedTransports = mutableListOf<CachedTransport>()

    fun render(
        context: AgentConversationContext,
        maximumTokens: Int,
        currentGoal: String = "",
        includeGlobalContext: Boolean = false
    ): String {
        val normalizedGoal = currentGoal.trim()
        synchronized(cacheLock) {
            takeCached(context, maximumTokens, normalizedGoal, includeGlobalContext)
        }?.let { cached ->
            return cached.value
        }

        val transportContext = context.withoutDuplicatedLatestUserText(normalizedGoal)
        val hasGlobalContext = includeGlobalContext &&
            transportContext.allowsGlobalContext &&
            transportContext.globalContext.isNotBlank()
        val value = if (
            transportContext.turns.isEmpty() &&
            transportContext.summary.isBlank() &&
            !hasGlobalContext
        ) {
            ""
        } else {
            transportContext.asTransportBlock(maximumTokens, includeGlobalContext)
        }
        return synchronized(cacheLock) {
            val cached = takeCached(context, maximumTokens, normalizedGoal, includeGlobalContext)
            if (cached != null) return@synchronized cached.value
            value.also {
                cachedTransports += CachedTransport(
                    context = WeakReference(context),
                    maximumTokens = maximumTokens,
                    currentGoal = normalizedGoal,
                    includeGlobalContext = includeGlobalContext,
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
        currentGoal: String,
        includeGlobalContext: Boolean
    ): CachedTransport? {
        cachedTransports.removeAll { cached -> cached.context.get() == null }
        val cachedIndex = cachedTransports.indexOfFirst { cached ->
            cached.context.get() === context &&
                cached.maximumTokens == maximumTokens &&
                cached.currentGoal == currentGoal &&
                cached.includeGlobalContext == includeGlobalContext
        }
        if (cachedIndex < 0) return null
        return cachedTransports.removeAt(cachedIndex).also { cached -> cachedTransports += cached }
    }

    private const val MAX_CACHED_TRANSPORTS = 8
}

internal fun AgentConversationContext.asAgentTransportBlock(currentGoal: String): String =
    AgentConversationTransportCache.render(
        context = this,
        maximumTokens = AGENT_CONVERSATION_TRANSPORT_TOKENS,
        currentGoal = currentGoal,
        includeGlobalContext = true
    )

private const val AGENT_CONVERSATION_TRANSPORT_TOKENS = 10_000
