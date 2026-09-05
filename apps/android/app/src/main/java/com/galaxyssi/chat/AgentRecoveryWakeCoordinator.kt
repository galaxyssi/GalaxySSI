package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** Coalesces transport/lifecycle events without dropping a wake arriving during observation. */
internal class AgentRecoveryWakeCoordinator(
    private val scope: CoroutineScope,
    private val recover: suspend () -> Unit,
    private val failed: (Exception) -> Unit = {}
) {
    private val lock = Any()
    private var connected = false
    private var pending = false
    private var worker: Long? = null
    private var nextWorker = 0L

    fun connectionChanged(value: Boolean) {
        val start = synchronized(lock) {
            if (value && !connected) pending = true
            connected = value
            claimWorker()
        }
        start?.let(::launchWorker)
    }

    fun request(isConnected: Boolean? = null) {
        val start = synchronized(lock) {
            if (isConnected != null) connected = isConnected
            pending = true
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
            while (synchronized(lock) {
                (connected && pending).also { if (it) pending = false }
            }) {
                try { recover() }
                catch (cancelled: CancellationException) { throw cancelled }
                catch (error: Exception) { failed(error) }
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
