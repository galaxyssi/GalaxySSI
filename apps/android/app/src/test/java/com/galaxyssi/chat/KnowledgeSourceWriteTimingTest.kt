package com.galaxyssi.chat

import com.galaxyssi.chat.metrics.*
import org.junit.Assert.*
import org.junit.Test

class KnowledgeSourceWriteTimingTest {
    private val points = mutableListOf<AgentTimingPoint>()
    private var now = 0L
    private fun timing() = KnowledgeSourceWriteTiming(AgentRuntimeTiming({ trace, stage, operation, outcome, at ->
        points += AgentTimingPoint(trace, "a".repeat(32), stage, at, 0, operation, outcome = outcome)
    }) { now })

    @Test fun everyProductionPhaseEntersTheExistingPercentileContract() {
        val timing = timing()
        for (phase in listOf("total", "stage", "prepare", "commit", "ownership", "apply", "observe")) {
            assertEquals("private body", timing.measure(phase) { now += 2_000_000; "private body" })
            val result = AgentLatencyContract.summarize(points).getValue("phone_runtime_knowledge_source_${phase}_ms")
            assertEquals(1, result.count)
            assertEquals(2.0, result.p95Ms!!, 0.0)
        }
        assertEquals(1, points.map { it.traceId }.distinct().size)
        assertTrue(points.all(AgentLatencyContract::valid))
        assertFalse(points.toString().contains("private"))
    }

    @Test fun repeatedAndNestedReplacementsHaveIndependentCorrelation() {
        val first = timing()
        first.measure("total") { timing().measure("total") { now++ }; now++ }
        assertEquals(2, points.map { it.traceId }.distinct().size)
        repeat(2) { first.measure("apply") { now++ } }
        assertEquals(2, AgentLatencyContract.summarize(points).getValue("phone_runtime_knowledge_source_apply_ms").count)
    }

    @Test fun failuresAndCancellationDoNotCountAsSuccessfulWrites() {
        for (error in listOf(IllegalStateException("secret"), java.util.concurrent.CancellationException("secret"),
            InterruptedException("secret"), java.util.concurrent.TimeoutException("secret"))) {
            try { timing().measure<Unit>("commit") { throw error }; fail("Expected failure") }
            catch (actual: Exception) { assertSame(error, actual) }
        }
        val result = AgentLatencyContract.summarize(points).getValue("phone_runtime_knowledge_source_commit_ms")
        assertEquals(0, result.count); assertEquals(4, result.unsuccessful)
    }

    @Test fun telemetryFailureCannotChangeTheResultOrRunItTwice() {
        val broken = KnowledgeSourceWriteTiming(AgentRuntimeTiming({ _, _, _, _, _ -> error("sink") }) { error("clock") })
        var calls = 0
        assertEquals(42, broken.measure("apply") { calls++; 42 })
        assertEquals(1, calls)
    }

    @Test fun MissingFinishIsIncompleteRatherThanFastSuccess() {
        timing().measure("apply") { now += 5 }
        val result = AgentLatencyContract.summarize(points.take(1)).getValue("phone_runtime_knowledge_source_apply_ms")
        assertEquals(0, result.count); assertEquals(1, result.incomplete)
    }

    @Test fun disabledAndUnknownPhasesStillExecuteWithoutEvents() {
        assertEquals(1, KnowledgeSourceWriteTiming.NONE.measure("stage") { 1 })
        assertEquals(2, timing().measure("private source") { 2 })
        assertTrue(points.isEmpty())
    }
}
