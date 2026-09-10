package com.galaxyssi.chat.metrics

import java.util.UUID
import java.util.concurrent.CancellationException
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean

/** Explicit request scope, safe to carry across coroutine and Binder boundaries. */
internal class AgentModelTiming(
    val traceId: String,
    private val emit: ((AgentTimingPoint) -> Unit)?,
    val provider: String = "",
    private val clockId: String = processClock,
    private val nowNs: () -> Long = System::nanoTime
) {
    fun begin(phase: String): Span {
        val output = emit ?: return Span(null)
        if (phase !in phases || !tracePattern.matches(traceId)) return Span(null)
        val operation = runCatching { AgentLatencyContract.opaqueId(UUID.randomUUID().toString()) }
            .getOrNull() ?: return Span(null)
        val record: (String, String) -> Unit = { boundary, outcome ->
            runCatching {
                output(AgentTimingPoint(traceId, clockId, "phone_model_${phase}_$boundary",
                    nowNs(), System.currentTimeMillis(), operation, provider, outcome))
            }
        }
        record("started", "")
        return Span { record("finished", it) }
    }

    fun <T> measure(phase: String, block: () -> T): T {
        val span = begin(phase)
        return try { block().also { span.completed() } }
        catch (error: Throwable) { span.failed(error); throw error }
        finally { span.close() }
    }

    suspend fun <T> measureSuspend(phase: String, block: suspend () -> T): T {
        val span = begin(phase)
        return try { block().also { span.completed() } }
        catch (error: Throwable) { span.failed(error); throw error }
        finally { span.close() }
    }

    fun acceptRemote(encoded: String) {
        if (encoded.length > 2048) return
        val point = AgentTimingJournal.decode(encoded) ?: return
        if (point.traceId != traceId || point.provider != provider || point.operationId.isBlank() ||
            point.stage !in stages) return
        // Keep the worker clock: never restamp a remote event with the UI-process clock.
        runCatching { emit?.invoke(point) }
    }

    class Span(private val finish: ((String) -> Unit)?) : AutoCloseable {
        private val finished = AtomicBoolean(false)
        fun completed() = end("completed")
        fun failed(error: Throwable) = end(when (error) {
            is CancellationException, is InterruptedException -> "cancelled"
            is TimeoutException -> "timed_out"
            else -> "failed"
        })
        override fun close() = end("failed")
        private fun end(outcome: String) {
            if (finished.compareAndSet(false, true)) runCatching { finish?.invoke(outcome) }
        }
    }

    companion object {
        val phases = setOf("request", "client_lock_wait", "worker_lock_wait", "service_bind", "process_roundtrip", "service_queue",
            "preflight", "sdk_init", "load", "reuse", "generate", "first_token", "release")
        val stages = phases.flatMap { listOf("phone_model_${it}_started", "phone_model_${it}_finished") }.toSet()
        private val processClock = UUID.randomUUID().toString().replace("-", "")
        private val tracePattern = Regex("[a-f0-9]{64}")
        val NONE = AgentModelTiming("", null)
    }
}
