package com.galaxyssi.chat.voice.modelstream

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import java.util.concurrent.ConcurrentHashMap

/** Includes preparation, HTTP rounds, and tool work, not only the current socket. */
internal class ModelStreamRequestLifetimes {
    private val active = ConcurrentHashMap<String, Job>()

    suspend fun <T> run(requestId: String, block: suspend () -> T): T = coroutineScope {
        val owner = requireNotNull(currentCoroutineContext()[Job])
        check(active.putIfAbsent(requestId, owner) == null) { "Model request is already active" }
        try { block() } finally { active.remove(requestId, owner) }
    }

    fun cancel(requestId: String, reason: ModelStreamCancelReason): Boolean {
        val owner = active[requestId] ?: return false
        owner.cancel(CancellationException(reason.name))
        return true
    }

    internal fun activeRequestIds(): Set<String> = active.keys.toSet()
}
