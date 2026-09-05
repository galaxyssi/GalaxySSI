package com.galaxyssi.chat

import com.galaxyssi.chat.metrics.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class AgentLatencyTraceTest {
    @Test fun userSendClockBindsOnlyToTheFirstConnectorRequestInItsOwnTurn() {
        val starts = AgentLatencyTurnStarts()
        starts.begin("one", 10)
        starts.begin("two", 20)
        starts.begin("one", 99)
        assertNull(starts.take("another"))
        assertEquals(10L, starts.take("one"))
        assertNull(starts.take("one"))
        assertEquals(20L, starts.take("two"))
    }
    private class Sink : AgentTimingSink {
        val points = mutableListOf<AgentTimingPoint>()
        override fun append(point: AgentTimingPoint) { points += point }
        override fun snapshot() = points.toList()
    }

    private fun point(stage: String, ms: Long, task: String = "t", clock: String = "a".repeat(32), outcome: String = "") =
        AgentTimingPoint(AgentLatencyContract.opaqueId(task), clock, stage, ms * 1_000_000, 1000, outcome = outcome)

    @Test fun durationDisplayRemainsCompactForLongRunningTasks() {
        assertEquals("50.0 ms", agentLatencyDisplayValue(50.0))
        assertEquals("1.0 s", agentLatencyDisplayValue(1000.0))
        assertEquals("1.0 min", agentLatencyDisplayValue(60000.0))
        assertEquals("1.0 h", agentLatencyDisplayValue(3600000.0))
        assertEquals("30.0 d", agentLatencyDisplayValue(2592000000.0))
        assertEquals("-", agentLatencyDisplayValue(null))
        assertEquals("-", agentLatencyDisplayValue(Double.NaN))
    }

    @Test fun exactPercentiles() {
        val points = (1L..100L).flatMap { i -> listOf(
            point("phone_publish_started", 0, i.toString()), point("phone_first_output_visible", i, i.toString())
        ) }
        val metric = AgentLatencyContract.summarize(points).getValue("phone_connector_first_visible_ms")
        assertEquals(100, metric.count)
        assertEquals(50.0, metric.p50Ms!!, .001)
        assertEquals(95.0, metric.p95Ms!!, .001)
        assertEquals(99.0, metric.p99Ms!!, .001)
    }

    @Test fun clockAndTaskIsolation() {
        val result = AgentLatencyContract.summarize(listOf(
            point("phone_publish_started", 0),
            point("phone_first_output_visible", 10, clock = "b".repeat(32)),
            point("phone_first_output_visible", 10, task = "another")
        )).getValue("phone_connector_first_visible_ms")
        assertEquals(0, result.count)
        assertEquals(1, result.incomplete)
        assertNull(result.p95Ms)
    }

    @Test fun failuresAreNotFastSuccess() {
        for (outcome in listOf("failed", "cancelled", "timed_out")) {
            val metric = AgentLatencyContract.summarize(listOf(
                point("phone_publish_started", 0), point("phone_request_queued", 1, outcome = outcome)
            )).getValue("phone_publish_prepare_ms")
            assertEquals(0, metric.count)
            assertEquals(1, metric.unsuccessful)
            assertNull(metric.p50Ms)
        }
    }

    @Test fun duplicatesOutOfOrderAndWallAdjustments() {
        val start = point("phone_request_queued", 100)
        val end = point("phone_response_received", 200).copy(wallClockMs = 0)
        val metric = AgentLatencyContract.summarize(listOf(end, start, start, end,
            point("phone_response_received", 50))).getValue("phone_response_roundtrip_ms")
        assertEquals(1, metric.count)
        assertEquals(100.0, metric.p95Ms!!, .001)
    }

    @Test fun noInputContentAndOnlyOneEventPerStage() {
        val sink = Sink()
        val tracer = AgentLatencyTracer(sink)
        repeat(100) { tracer.record("private-task-id", "phone_publish_started") }
        assertEquals(1, sink.points.size)
        val encoded = AgentTimingJournal.encode(sink.points.single()).toString()
        assertFalse(encoded.contains("private-task-id"))
        assertEquals(64, sink.points.single().traceId.length)
    }

    @Test fun historicalOrUnreceivedRowsAreNotLiveMeasurements() {
        val sink = Sink()
        val tracer = AgentLatencyTracer(sink)
        assertFalse(tracer.shouldObserve("old-task", true))
        tracer.record("t", "phone_publish_started")
        assertFalse(tracer.shouldObserve("t", true))
        tracer.record("t", "phone_response_received")
        assertTrue(tracer.shouldObserve("t", false))
        tracer.visible("t", final = false)
        assertFalse(tracer.shouldObserve("t", false))
        assertFalse(tracer.shouldObserve("t", true))
        tracer.record("t", "phone_final_received")
        assertTrue(tracer.shouldObserve("t", true))
        tracer.visible("t", final = true)
        assertFalse(tracer.shouldObserve("t", true))
        assertEquals(1, sink.points.count { it.stage == "phone_final_output_visible" })
    }

    @Test fun nonStreamingIntermediateReplyCannotCountAsFinal() {
        val sink = Sink()
        val tracer = AgentLatencyTracer(sink)
        tracer.record("t", "phone_publish_started")
        tracer.record("t", "phone_response_received")
        tracer.visible("t", final = true)
        assertFalse(sink.points.any { it.stage == "phone_final_output_visible" })
    }

    @Test fun earlierSendBoundaryIsPreserved() {
        val sink = Sink()
        AgentLatencyTracer(sink, monotonicNs = { 999 }).record("t", "phone_publish_started", atNs = 10)
        assertEquals(10, sink.points.single().monotonicNs)
    }

    @Test fun renderedErrorIsNotACompletedResponseSample() {
        val sink = Sink()
        val tracer = AgentLatencyTracer(sink)
        tracer.record("t", "phone_publish_started")
        tracer.record("t", "phone_response_received")
        tracer.record("t", "phone_final_received", outcome = "failed")
        tracer.visible("t", final = true)
        val metric = AgentLatencyContract.summarize(sink.points).getValue("phone_connector_complete_visible_ms")
        assertEquals(0, metric.count)
        assertEquals(1, metric.unsuccessful)
        val first = AgentLatencyContract.summarize(sink.points).getValue("phone_connector_first_visible_ms")
        assertEquals(0, first.count)
        assertEquals(1, first.unsuccessful)
    }

    @Test fun laterFailureDoesNotEraseAnAlreadyVisiblePartial() {
        val sink = Sink()
        val tracer = AgentLatencyTracer(sink)
        tracer.record("t", "phone_publish_started")
        tracer.record("t", "phone_response_received")
        tracer.visible("t", final = false)
        tracer.record("t", "phone_final_received", outcome = "failed")
        tracer.visible("t", final = true)
        val metrics = AgentLatencyContract.summarize(sink.points)
        assertEquals(1, metrics.getValue("phone_connector_first_visible_ms").count)
        assertEquals(1, metrics.getValue("phone_connector_complete_visible_ms").unsuccessful)
    }

    @Test fun journalReopensAndSnapshotHasNoDiskDependency() {
        val dir = Files.createTempDirectory("agent-latency-test").toFile()
        try {
            val file = File(dir, "timings.jsonl")
            AgentTimingJournal(file).use { it.append(point("phone_publish_started", 0)) }
            val journal = AgentTimingJournal(file)
            journal.close()
            assertEquals(1, journal.snapshot().size)
            assertTrue(file.delete())
            assertEquals(1, journal.snapshot().size)
        } finally { dir.deleteRecursively() }
    }

    @Test fun corruptHugeAndPartialRecordsAreSkipped() {
        val dir = Files.createTempDirectory("agent-latency-corrupt").toFile()
        try {
            val file = File(dir, "timings.jsonl")
            file.writeText("x".repeat(100_000) + "\n" +
                AgentTimingJournal.encode(point("phone_publish_started", 0)) + "\n{broken")
            AgentTimingJournal(file).use { journal ->
                journal.close()
                assertEquals(1, journal.snapshot().size)
                assertEquals(2L, journal.health()["invalid_events"])
            }
        } finally { dir.deleteRecursively() }
    }

    @Test fun writerStallDoesNotBlockProducerAndPendingWorkIsBounded() {
        val dir = Files.createTempDirectory("agent-latency-stall").toFile()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        try {
            AgentTimingJournal(File(dir, "timings.jsonl"), queueLimit = 4, batchWriter = {
                entered.countDown(); release.await(5, TimeUnit.SECONDS)
            }).use { journal ->
                journal.append(point("phone_publish_started", 0))
                assertTrue(entered.await(2, TimeUnit.SECONDS))
                val start = System.nanoTime()
                repeat(100) { journal.append(point("phone_request_queued", it.toLong(), it.toString())) }
                assertTrue((System.nanoTime() - start) / 1_000_000 < 500)
                assertTrue((journal.health()["dropped_events"] as Long) >= 96)
                release.countDown()
            }
        } finally { release.countDown(); dir.deleteRecursively() }
    }

    @Test fun malformedTimingNumbersAreRejected() {
        val json = AgentTimingJournal.encode(point("phone_publish_started", 0))
        json.put("monotonic_ns", true)
        assertNull(AgentTimingJournal.decode(json.toString()))
        json.put("monotonic_ns", "123")
        assertNull(AgentTimingJournal.decode(json.toString()))
    }
}
