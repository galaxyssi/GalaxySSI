package com.galaxyssi.chat

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Carries cancellation through the synchronous compatibility client's nested HTTP rounds. */
internal object CloudBlockingRequestCancellation {
    private val current = ThreadLocal<AgentNativeToolCancellationToken>()
    fun token(): AgentNativeToolCancellationToken = current.get() ?: AgentNativeToolCancellationToken.NONE

    suspend fun <T> run(block: () -> T): T = coroutineScope {
        suspendCancellableCoroutine { continuation ->
            val source = AgentNativeToolCancellationSource()
            continuation.invokeOnCancellation { source.cancel() }
            launch(Dispatchers.IO) {
                val previous = current.get()
                current.set(source.token)
                try {
                    if (!source.token.isCancellationRequested) continuation.resume(block())
                } catch (error: Throwable) {
                    continuation.resumeWithException(error)
                } finally {
                    if (previous == null) current.remove() else current.set(previous)
                }
            }
        }
    }
}
