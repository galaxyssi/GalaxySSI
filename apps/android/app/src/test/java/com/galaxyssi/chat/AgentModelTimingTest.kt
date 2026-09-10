package com.galaxyssi.chat

import com.galaxyssi.chat.metrics.*
import java.util.Collections
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test

class AgentModelTimingTest {
    private val points = Collections.synchronizedList(mutableListOf<AgentTimingPoint>())
    private val trace = AgentLatencyContract.opaqueId("private-task")
    private var now = 0L
    private val timing = AgentModelTiming(trace, { points += it }, "LEGACY_LLAMA", "c".repeat(32)) { now }
    private fun metric(phase: String) = AgentLatencyContract.summarize(points.toList()).getValue("phone_model_${phase}_ms")

    @Test fun actualBoundariesSeparateColdLoadReuseAndGeneration() {
        timing.measure("load") { now += 12_000_000 }
        timing.measure("reuse") { now += 1_000_000 }
        assertEquals("private reply", timing.measure("generate") { now += 4_000_000; "private reply" })
        assertEquals(12.0, metric("load").p95Ms!!, 0.0)
        assertEquals(1.0, metric("reuse").p95Ms!!, 0.0)
        assertEquals(4.0, metric("generate").p95Ms!!, 0.0)
        assertEquals(1, metric("load").count)
        assertFalse(points.toString().contains("private"))
    }

    @Test fun failuresKeepTheirIdentityAndStayOutOfSuccessPercentiles() {
        for ((error, outcome) in listOf(IllegalStateException("private") to "failed",
            CancellationException("private") to "cancelled", InterruptedException("private") to "cancelled",
            TimeoutException("private") to "timed_out")) {
            try { timing.measure<Unit>("load") { throw error }; fail("Expected failure") }
            catch (actual: Exception) { assertSame(error, actual) }
            assertEquals(outcome, points.last().outcome)
        }
        assertEquals(0, metric("load").count)
        assertEquals(4, metric("load").unsuccessful)
    }

    @Test fun firstTokenIsCompletedOnceAndNotRewrittenByLaterFailure() {
        val first = timing.begin("first_token")
        now = 2_000_000
        first.completed()
        repeat(100) { now++; first.completed() }
        first.failed(IllegalStateException("later generation failure"))
        first.close()
        assertEquals(2, points.size)
        assertEquals(2.0, metric("first_token").p99Ms!!, 0.0)
        timing.begin("load")
        assertEquals(1, metric("load").incomplete)
    }

    @Test fun brokenClockAndSinkDoNotChangeOrRetryModelWork() {
        var calls = 0
        val broken = AgentModelTiming(trace, { error("writer") }, nowNs = { error("clock") })
        assertEquals(7, broken.measure("load") { calls++; 7 })
        assertEquals(1, calls)
        assertEquals(8, AgentModelTiming.NONE.measure("generate") { 8 })
        assertEquals(9, timing.measure("private unknown phase") { 9 })
        assertTrue(points.isEmpty())
    }

    @Test fun explicitScopeSurvivesCoroutineDispatcherChanges() = runBlocking {
        val result = withContext(Dispatchers.Default) {
            timing.measureSuspend("sdk_init") { withContext(Dispatchers.IO) { now += 5_000_000; 42 } }
        }
        assertEquals(42, result)
        assertEquals(5.0, metric("sdk_init").p50Ms!!, 0.0)
    }

    @Test fun remotePointsRetainWorkerClockAndRejectWrongTaskProviderOrStage() {
        val remote = AgentTimingPoint(trace, "d".repeat(32), "phone_model_load_started", 10L, 0,
            "e".repeat(64), "LEGACY_LLAMA")
        for (invalid in listOf(remote.copy(traceId = "f".repeat(64)), remote.copy(provider = "GENIEX_NPU"),
            remote.copy(stage = "phone_publish_started"), remote.copy(operationId = ""))) {
            timing.acceptRemote(AgentTimingJournal.encode(invalid).toString())
        }
        timing.acceptRemote("not json")
        timing.acceptRemote("x".repeat(2049))
        assertTrue(points.isEmpty())
        timing.acceptRemote(AgentTimingJournal.encode(remote).toString())
        timing.acceptRemote(AgentTimingJournal.encode(remote.copy(stage = "phone_model_load_finished",
            monotonicNs = 2_000_010L, outcome = "completed")).toString())
        assertTrue(points.all { it.clockId == "d".repeat(32) })
        assertEquals(2.0, metric("load").p95Ms!!, 0.0)
    }

    @Test fun workerRestartCannotCompleteAnOldLoadSpan() {
        val operation = "e".repeat(64)
        points += AgentTimingPoint(trace, "a".repeat(32), "phone_model_load_started", 1, 0, operation)
        points += AgentTimingPoint(trace, "b".repeat(32), "phone_model_load_finished", 2, 0, operation,
            outcome = "completed")
        assertEquals(0, metric("load").count)
        assertEquals(1, metric("load").incomplete)
    }

    @Test fun concurrentRequestsDoNotOverwriteSamples() {
        val pool = Executors.newFixedThreadPool(4)
        try {
            (0 until 40).map { index -> pool.submit {
                AgentModelTiming(AgentLatencyContract.opaqueId("task-${index % 2}"), { points += it })
                    .measure("generate") { index }
            } }.forEach { it.get(10, TimeUnit.SECONDS) }
        } finally { pool.shutdownNow(); assertTrue(pool.awaitTermination(10, TimeUnit.SECONDS)) }
        assertEquals(40, metric("generate").count)
        assertEquals(40, points.map { it.operationId }.distinct().size)
        assertEquals(2, points.map { it.traceId }.distinct().size)
    }
}
