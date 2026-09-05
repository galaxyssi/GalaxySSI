package com.galaxyssi.chat

import com.galaxyssi.chat.metrics.*
import org.junit.Assert.*
import org.junit.Test

class AgentReplyTraceBindingsTest {
    @Test fun finalRowUsesTransportTraceWithoutChangingItsRuntimeIdentity() {
        val bindings = AgentReplyTraceBindings()
        val points = mutableListOf<AgentTimingPoint>()
        val tracer = AgentLatencyTracer(object : AgentTimingSink {
            override fun append(point: AgentTimingPoint) { points += point }
            override fun snapshot() = points.toList()
        })
        tracer.record("transport", "phone_publish_started")
        tracer.record("transport", "phone_response_received")
        tracer.record("transport", "phone_final_received")
        assertFalse(tracer.shouldObserve("runtime", true))
        bindings.bind("conversation", "turn", "runtime", "transport")
        tracer.visible(bindings.resolve("conversation", "turn", "runtime"), true)
        assertEquals(1, points.count { it.stage == "phone_final_output_visible" })
        assertEquals(AgentLatencyContract.opaqueId("transport"), points.last().traceId)
    }

    @Test fun everyIdentityDimensionMustMatch() {
        val bindings = AgentReplyTraceBindings()
        bindings.bind("c", "t", "local", "remote")
        assertEquals("local", bindings.resolve("another-c", "t", "local"))
        assertEquals("local", bindings.resolve("c", "another-t", "local"))
        assertEquals("another-local", bindings.resolve("c", "t", "another-local"))
        assertEquals("remote", bindings.resolve("c", "t", "local"))
    }

    @Test fun blankIdentityIsNotAConversationWideAlias() {
        val bindings = AgentReplyTraceBindings()
        bindings.bind("c", "", "local", "remote")
        bindings.bind("", "t", "local", "remote")
        bindings.bind("c", "t", "local", "")
        assertEquals("local", bindings.resolve("c", "t", "local"))
        assertEquals("local", bindings.resolve("c", "", "local"))
    }

    @Test fun delimitersCannotJoinDifferentTurns() {
        val bindings = AgentReplyTraceBindings()
        bindings.bind("a:b", "c", "local", "remote")
        assertEquals("local", bindings.resolve("a", "b:c", "local"))
    }

    @Test fun continuationUpdatesOnlyItsExactRowIdentity() {
        val bindings = AgentReplyTraceBindings()
        bindings.bind("c", "t", "local", "first")
        bindings.bind("other", "t", "local", "other-remote")
        bindings.bind("c", "t", "local", "second")
        assertEquals("second", bindings.resolve("c", "t", "local"))
        assertEquals("other-remote", bindings.resolve("other", "t", "local"))
    }

    @Test fun diagnosticEvictionOnlyDropsCorrelationNotTaskIdentity() {
        val bindings = AgentReplyTraceBindings(capacity = 1)
        bindings.bind("c", "first", "local-1", "remote-1")
        bindings.bind("c", "second", "local-2", "remote-2")
        assertEquals("local-1", bindings.resolve("c", "first", "local-1"))
        assertEquals("remote-2", bindings.resolve("c", "second", "local-2"))
    }

    @Test fun everyReplyPipelinePairCanBeMeasuredWithoutJoiningDifferentClocks() {
        val task = AgentLatencyContract.opaqueId("remote")
        for ((name, stages) in AgentLatencyContract.pairs.filterKeys {
            it.startsWith("phone_final_") || it.startsWith("phone_transcript_")
        }) {
            fun point(stage: String, ms: Long, clock: String = "a".repeat(32)) =
                AgentTimingPoint(task, clock, stage, ms * 1_000_000, 0)
            val metric = AgentLatencyContract.summarize(listOf(point(stages.first, 10), point(stages.second, 20)))
                .getValue(name)
            assertEquals(name, 10.0, metric.p95Ms!!, .001)
            val unjoined = AgentLatencyContract.summarize(listOf(point(stages.first, 10),
                point(stages.second, 20, "b".repeat(32)))).getValue(name)
            assertEquals(name, 0, unjoined.count)
            assertEquals(name, 1, unjoined.incomplete)
        }
    }
}
