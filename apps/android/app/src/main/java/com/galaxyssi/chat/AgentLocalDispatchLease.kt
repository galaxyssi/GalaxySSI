package com.galaxyssi.chat

import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.Executor
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.runBlocking

/** One queued local dispatch owns one terminal decision and its tool cancellation token. */
internal class AgentLocalDispatchLease(taskId: String,
    upstreamCancellation: AgentNativeToolCancellationToken = AgentNativeToolCancellationToken.NONE,
    private val onClosed: (AgentLocalDispatchLease) -> Unit = {}) : AutoCloseable {
    private enum class State { ACTIVE, COMPLETED, CANCELLED }
    private val state = AtomicReference(State.ACTIVE)
    private val started = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val completion = CompletableDeferred<Unit>()
    private val source = AgentNativeToolCancellationSource()
    private val registration = PhoneExecutionAuthority.observeCancellation(taskId) { cancel() }
    private val upstreamRegistration = upstreamCancellation.invokeOnCancellation { cancel() }
    val token: AgentNativeToolCancellationToken get() = source.token
    internal suspend fun awaitClosed() = completion.await()

    internal fun cancel(): Boolean {
        if (!state.compareAndSet(State.ACTIVE, State.CANCELLED)) return false
        source.cancel()
        return true
    }

    fun <T> enqueue(executor: Executor, request: (AgentNativeToolCancellationToken) -> T,
        completed: (Result<T>) -> Unit, cancelled: () -> Unit = {}) {
        try { executor.execute { execute(request, completed, cancelled) } }
        catch (error: Throwable) { close(); throw error }
    }

    fun <T> execute(request: (AgentNativeToolCancellationToken) -> T,
        completed: (Result<T>) -> Unit, cancelled: () -> Unit = {}) {
        check(started.compareAndSet(false, true)) { "A local dispatch may only execute once" }
        try {
            if (token.isCancellationRequested) { cancelled(); return }
            val result = runCatching { request(token) }
            if (result.exceptionOrNull() is CancellationException ||
                result.exceptionOrNull() is AgentNativeToolCancelledException) cancel()
            if (state.compareAndSet(State.ACTIVE, State.COMPLETED)) completed(result)
            else cancelled()
        } finally { close() }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        try { registration.dispose(); upstreamRegistration.dispose() }
        finally { try { onClosed(this) } finally { completion.complete(Unit) } }
    }
}

internal fun <T> runCancellableLocalRequest(token: AgentNativeToolCancellationToken,
    request: suspend () -> T): T = runBlocking {
    val job = requireNotNull(coroutineContext[Job])
    val registration = token.invokeOnCancellation { job.cancel(CancellationException("Local dispatch cancelled")) }
    try {
        if (token.isCancellationRequested) throw CancellationException("Local dispatch cancelled")
        request()
    } finally { registration.dispose() }
}
