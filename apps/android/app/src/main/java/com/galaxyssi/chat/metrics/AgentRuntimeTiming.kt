package com.galaxyssi.chat.metrics

import java.util.UUID
import java.util.concurrent.CancellationException
import java.util.concurrent.TimeoutException

/** Content-free synchronous spans; telemetry must never change the action result. */
internal class AgentRuntimeTiming(
    private val emit: ((String, String, String, String, Long) -> Unit)?,
    private val nowNs: () -> Long = System::nanoTime
) {
    fun <T> measure(taskId: String, phase: String, outcomeOf: (T) -> String, block: () -> T): T {
        val output = emit ?: return block()
        if (taskId.isBlank() || phase !in phases) return block()
        val ids = runCatching {
            AgentLatencyContract.opaqueId(taskId) to AgentLatencyContract.opaqueId(UUID.randomUUID().toString())
        }.getOrNull() ?: return block()
        fun record(boundary: String, outcome: String) {
            runCatching { output(ids.first, "phone_runtime_${phase}_$boundary", ids.second, outcome, nowNs()) }
        }
        record("started", "")
        var outcome = "failed"
        return try {
            block().also { result ->
                outcome = runCatching { outcomeOf(result) }.getOrDefault("failed")
                    .takeIf { it in AgentLatencyContract.outcomes && it.isNotBlank() } ?: "failed"
            }
        } catch (error: CancellationException) {
            outcome = "cancelled"
            throw error
        } catch (error: InterruptedException) {
            outcome = "cancelled"
            throw error
        } catch (error: TimeoutException) {
            outcome = "timed_out"
            throw error
        } finally { record("finished", outcome) }
    }

    companion object {
        val phases = setOf("action_dispatch", "screen_observe", "receipt_observe", "result_verify")
        val NONE = AgentRuntimeTiming(null)
    }
}
