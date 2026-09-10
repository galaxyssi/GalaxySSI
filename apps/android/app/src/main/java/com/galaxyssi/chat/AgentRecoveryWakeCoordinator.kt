package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/** Coalesces transport/lifecycle events without dropping a wake arriving during observation. */
internal class AgentRecoveryWakeCoordinator(
    private val scope: CoroutineScope,
    private val recover: suspend (retry: () -> Unit) -> Unit,
    private val failed: (Exception) -> Unit = {},
    private val initialRetryMillis: Long = 1_000L,
    private val maxRetryMillis: Long = 30_000L
) {
    init { require(initialRetryMillis > 0 && maxRetryMillis >= initialRetryMillis) }
    private val lock = Any()
    private val wakeEvents = Channel<Unit>(Channel.CONFLATED)
    private var connected = false
    private var pending = false
    private var worker: Long? = null
    private var nextWorker = 0L

    fun connectionChanged(value: Boolean) {
        val start = synchronized(lock) {
            val changed = value != connected
            if (value && !connected) pending = true
            connected = value
            if (changed && worker != null) wakeEvents.trySend(Unit)
            claimWorker()
        }
        start?.let(::launchWorker)
    }

    fun request(isConnected: Boolean? = null) {
        val start = synchronized(lock) {
            if (isConnected != null) connected = isConnected
            pending = true
            if (worker != null) wakeEvents.trySend(Unit)
            claimWorker()
        }
        start?.let(::launchWorker)
    }

    private fun claimWorker(): Long? {
        if (!connected || !pending || worker != null || !scope.isActive) return null
        return (++nextWorker).also { worker = it }
    }

    private fun launchWorker(id: Long) {
        val job = scope.launch {
            var retryMillis = initialRetryMillis
            while (synchronized(lock) {
                (connected && pending).also { if (it) pending = false }
            }) {
                wakeEvents.tryReceive()
                var retry = false
                try { recover { retry = true } }
                catch (cancelled: CancellationException) { throw cancelled }
                catch (error: Exception) { failed(error) }
                if (retry) {
                    // A timed-out read is unresolved work, not a completed recovery pass.
                    val wait = synchronized(lock) {
                        val needsDelay = connected && !pending
                        pending = true
                        needsDelay
                    }
                    if (wait) withTimeoutOrNull(retryMillis) { wakeEvents.receive() }
                    retryMillis = (retryMillis + retryMillis.coerceAtMost(maxRetryMillis - retryMillis))
                        .coerceAtMost(maxRetryMillis)
                } else retryMillis = initialRetryMillis
            }
        }
        job.invokeOnCompletion {
            val next = synchronized(lock) {
                if (worker != id) null else { worker = null; claimWorker() }
            }
            next?.let(::launchWorker)
        }
    }

    internal val isRunning: Boolean get() = synchronized(lock) { worker != null }
    internal val hasPendingWake: Boolean get() = synchronized(lock) { pending }
}
