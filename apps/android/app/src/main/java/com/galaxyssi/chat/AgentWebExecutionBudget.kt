package com.galaxyssi.chat

import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runInterruptible

internal class AgentWebBudgetExceededException : RuntimeException("The shared web evidence deadline was reached")

/** One monotonic deadline across model rounds, search plans and queued web calls. */
internal class AgentWebExecutionBudget(
    durationMillis: Long,
    private val clockNanos: () -> Long = System::nanoTime
) {
    private val startedNanos = clockNanos()
    private val durationNanos = durationMillis.coerceIn(1L, 300_000L) * 1_000_000L
    val remainingMillis: Long
        get() = ((durationNanos - (clockNanos() - startedNanos)) / 1_000_000L).coerceAtLeast(0L)
    val expired: Boolean get() = remainingMillis == 0L

    suspend fun <T> execute(block: (AgentNativeToolCancellationToken, () -> Unit) -> T): T = coroutineScope {
        if (expired) throw AgentWebBudgetExceededException()
        val source = AgentNativeToolCancellationSource()
        // Cancels actual transport listeners on both timeout and parent coroutine cancellation.
        // Cleanup must run immediately on cancellation, before the interrupted worker unregisters its listener.
        val watchdog = launch(Dispatchers.Unconfined, start = CoroutineStart.UNDISPATCHED) {
            try { delay(remainingMillis) } finally { source.cancel() }
        }
        val checkpoint = {
            if (expired) throw AgentWebBudgetExceededException()
            if (source.token.isCancellationRequested || Thread.currentThread().isInterrupted) {
                throw AgentNativeToolCancelledException()
            }
        }
        try {
            runInterruptible(Dispatchers.IO) {
                checkpoint()
                block(source.token, checkpoint)
            }
        } finally {
            watchdog.cancel()
            source.cancel()
        }
    }
}
