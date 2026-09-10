package com.galaxyssi.chat

import com.galaxyssi.chat.metrics.*
import java.util.Collections
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import org.junit.Assert.*
import org.junit.Test

class AgentRuntimeTimingTest {
    private val points = Collections.synchronizedList(mutableListOf<AgentTimingPoint>())
    private var now = 0L
    private val emit: (String, String, String, String, Long) -> Unit = { trace, stage, operation, outcome, at ->
        points += AgentTimingPoint(trace, "a".repeat(32), stage, at, 0, operation, outcome = outcome)
    }
    private val timing = AgentRuntimeTiming(emit) { now }
    private fun metric(phase: String = "action_dispatch") =
        AgentLatencyContract.summarize(points.toList()).getValue("phone_runtime_${phase}_ms")

    @Test fun exactSuccessfulDurationsHaveNoActionOrResultContents() {
        val output = timing.measure("private task", "action_dispatch", { "completed" }) {
            now += 12_000_000
            "secret result"
        }
        assertEquals("secret result", output)
        assertEquals(12.0, metric().p95Ms!!, 0.0)
        assertTrue(points.all(AgentLatencyContract::valid))
        assertFalse(points.toString().contains("private"))
        assertFalse(points.toString().contains("secret"))
    }

    @Test fun returnedFailuresAndTimeoutsNeverEnterSuccessPercentiles() {
        for (outcome in listOf("completed", "failed", "cancelled", "timed_out")) {
            timing.measure("task", "result_verify", { it }) { now += 2_000_000; outcome }
        }
        assertEquals(1, metric("result_verify").count)
        assertEquals(3, metric("result_verify").unsuccessful)
        assertEquals(2.0, metric("result_verify").p99Ms!!, 0.0)
    }

    @Test fun exceptionsKeepTheirIdentityAndClassification() {
        for ((exception, outcome) in listOf(CancellationException("private") to "cancelled",
            InterruptedException("private") to "cancelled", TimeoutException("private") to "timed_out",
            IllegalStateException("private") to "failed")) {
            try {
                timing.measure<Unit>("task", "action_dispatch", { "completed" }) { throw exception }
                fail("Expected original exception")
            } catch (actual: Exception) { assertSame(exception, actual) }
            assertEquals(outcome, points.last().outcome)
        }
        assertEquals(0, metric().count)
        assertEquals(4, metric().unsuccessful)
    }

    @Test fun telemetryFailureCannotRetryOrReplaceTheBusinessResult() {
        var calls = 0
        val broken = AgentRuntimeTiming({ _, _, _, _, _ -> error("writer") }) { error("clock") }
        assertEquals(42, broken.measure("task", "action_dispatch", { "completed" }) { calls++; 42 })
        assertEquals(1, calls)
        assertEquals(7, timing.measure("task", "action_dispatch", { error("classifier") }) { 7 })
        assertEquals(1, metric().unsuccessful)
    }

    @Test fun concurrentAndRepeatedActionsStayIndependentWithinTheSameTask() {
        val recorder = AgentRuntimeTiming(emit)
        val pool = Executors.newFixedThreadPool(4)
        try {
            (1..40).map { pool.submit<Int> {
                recorder.measure("same task", "action_dispatch", { "completed" }) { it }
            } }.forEach { assertTrue(it.get(10, TimeUnit.SECONDS) > 0) }
        } finally { pool.shutdownNow(); assertTrue(pool.awaitTermination(10, TimeUnit.SECONDS)) }
        assertEquals(40, metric().count)
        assertEquals(40, points.map { it.operationId }.distinct().size)
        assertEquals(1, points.map { it.traceId }.distinct().size)
    }

    @Test fun unknownOrDisabledMeasurementsDoNotEmitAndDoNotSuppressActions() {
        assertEquals(1, timing.measure("task", "sensitive phase", { "completed" }) { 1 })
        assertEquals(2, timing.measure("", "action_dispatch", { "completed" }) { 2 })
        assertEquals(3, AgentRuntimeTiming.NONE.measure("task", "action_dispatch", { "completed" }) { 3 })
        assertTrue(points.isEmpty())
    }

    @Test fun differentClockLifetimesAndMissingFinishesStayIncomplete() {
        timing.measure("task", "action_dispatch", { "completed" }) { now += 1_000_000 }
        val wrongClock = listOf(points.first(), points.last().copy(clockId = "b".repeat(32)))
        val result = AgentLatencyContract.summarize(wrongClock).getValue("phone_runtime_action_dispatch_ms")
        assertEquals(0, result.count)
        assertEquals(1, result.incomplete)
    }
}
