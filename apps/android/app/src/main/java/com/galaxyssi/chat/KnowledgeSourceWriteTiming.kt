package com.galaxyssi.chat

import com.galaxyssi.chat.metrics.AgentRuntimeTiming
import java.util.UUID

/** One random correlation ID per replacement, never derived from a source or record. */
internal class KnowledgeSourceWriteTiming(private val runtime: AgentRuntimeTiming) {
    private val operation = UUID.randomUUID().toString()

    fun <T> measure(phase: String, block: () -> T): T =
        runtime.measure(operation, "knowledge_source_$phase", { "completed" }, block)

    companion object {
        val NONE = KnowledgeSourceWriteTiming(AgentRuntimeTiming.NONE)
    }
}
