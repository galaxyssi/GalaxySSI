package com.signalasi.chat

import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import kotlin.math.min

internal data class AgentWebFetchFlightResult(
    val value: Triple<AgentWebIntelligenceDocument, Boolean, AgentWebIntelligenceReceipt>,
    val shared: Boolean,
    val waitedMillis: Long
)

/** Coalesces concurrent default fetches for one canonical URL across Android web service instances. */
internal object AgentWebFetchSingleFlight {
    private val flights = ConcurrentHashMap<
        String,
        CompletableFuture<Triple<AgentWebIntelligenceDocument, Boolean, AgentWebIntelligenceReceipt>>
    >()

    fun execute(
        canonicalUrl: String,
        timeoutMillis: Long,
        cancellationToken: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit,
        fetch: () -> Triple<AgentWebIntelligenceDocument, Boolean, AgentWebIntelligenceReceipt>
    ): AgentWebFetchFlightResult {
        val promise = CompletableFuture<Triple<AgentWebIntelligenceDocument, Boolean, AgentWebIntelligenceReceipt>>()
        val active = flights.putIfAbsent(canonicalUrl, promise)
        if (active != null) {
            val started = System.nanoTime()
            val value = await(active, timeoutMillis, cancellationToken, checkpoint)
            return AgentWebFetchFlightResult(
                value = value,
                shared = true,
                waitedMillis = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started)
            )
        }
        return try {
            val value = fetch()
            promise.complete(value)
            AgentWebFetchFlightResult(value, shared = false, waitedMillis = 0L)
        } catch (error: Throwable) {
            promise.completeExceptionally(error)
            throw error
        } finally {
            flights.remove(canonicalUrl, promise)
        }
    }

    private fun await(
        future: CompletableFuture<Triple<AgentWebIntelligenceDocument, Boolean, AgentWebIntelligenceReceipt>>,
        timeoutMillis: Long,
        cancellationToken: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ): Triple<AgentWebIntelligenceDocument, Boolean, AgentWebIntelligenceReceipt> {
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMillis)
        while (true) {
            if (cancellationToken.isCancellationRequested) throw AgentNativeToolCancelledException()
            checkpoint()
            val remainingMillis = TimeUnit.NANOSECONDS
                .toMillis(deadline - System.nanoTime())
                .coerceAtLeast(0L)
            if (remainingMillis <= 0L) throw AgentNativeToolTimeoutException()
            try {
                return future.get(min(remainingMillis, 100L), TimeUnit.MILLISECONDS)
            } catch (_: TimeoutException) {
                continue
            } catch (error: InterruptedException) {
                Thread.currentThread().interrupt()
                throw AgentNativeToolCancelledException()
            } catch (error: ExecutionException) {
                throwCause(error.cause ?: error)
            }
        }
    }

    private fun throwCause(error: Throwable): Nothing = when (error) {
        is Error -> throw error
        is RuntimeException -> throw error
        else -> throw IllegalStateException(error.message.orEmpty(), error)
    }
}
