package com.galaxyssi.chat.metrics

import java.util.UUID

/** Synchronous planning scope only; no task data or scope escapes to worker threads. */
internal object AgentPlanningTiming {
    val phases = setOf("total", "progress", "inventory", "goal", "context", "conversation", "prompt", "plan")
    private data class Scope(
        val trace: String,
        val emit: (String, String, String, String, Long) -> Unit,
        val nowNs: () -> Long
    )
    private val current = ThreadLocal<Scope>()

    fun <T> capture(
        taskId: String,
        emit: (String, String, String, String, Long) -> Unit,
        nowNs: () -> Long = System::nanoTime,
        block: () -> T
    ): T {
        if (taskId.isBlank()) return block()
        val previous = current.get()
        val scope = runCatching { Scope(AgentLatencyContract.opaqueId(taskId), emit, nowNs) }.getOrNull()
            ?: return block()
        current.set(scope)
        return try { measure("total", block) } finally {
            if (previous == null) current.remove() else current.set(previous)
        }
    }

    fun <T> measure(phase: String, block: () -> T): T {
        val scope = current.get() ?: return block()
        if (phase !in phases) return block()
        val operation = runCatching { AgentLatencyContract.opaqueId(UUID.randomUUID().toString()) }.getOrNull()
            ?: return block()
        fun record(boundary: String, outcome: String) {
            runCatching {
                scope.emit(scope.trace, "phone_planning_${phase}_$boundary", operation, outcome, scope.nowNs())
            }
        }
        record("started", "")
        var outcome = "failed"
        return try {
            block().also { outcome = "completed" }
        } catch (cancelled: java.util.concurrent.CancellationException) {
            outcome = "cancelled"
            throw cancelled
        } finally { record("finished", outcome) }
    }
}
