package com.galaxyssi.chat

import java.lang.ref.WeakReference

/** Selects one live consumer; the encrypted inbox remains authoritative. */
internal class AgentConnectorResponseRouter {
    private val consumers = mutableListOf<WeakReference<AgentConnectorResponseListener>>()

    @Synchronized
    fun add(listener: AgentConnectorResponseListener) {
        consumers.removeAll { it.get() == null || it.get() === listener }
        consumers.add(WeakReference(listener))
    }

    @Synchronized
    fun remove(listener: AgentConnectorResponseListener) {
        consumers.removeAll { it.get() == null || it.get() === listener }
    }

    fun dispatch(response: AgentConnectorResponse): Boolean {
        val candidates = synchronized(this) {
            consumers.removeAll { it.get() == null }
            consumers.mapNotNull { it.get() }.asReversed()
        }.mapNotNull { listener ->
            runCatching { listener.priority(response) }.getOrNull()
                ?.takeIf { it >= 0 }?.let { priority -> listener to priority }
        }.sortedByDescending { it.second }
        return candidates.any { (listener, _) ->
            runCatching { listener.onConnectorResponse(response) }.getOrDefault(false)
        }
    }
}
