package com.galaxyssi.chat

import com.galaxyssi.chat.metrics.*
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class AgentPlanningTimingTest {
    private val points = mutableListOf<AgentTimingPoint>()
    private var now = 0L
    private val emit: (String, String, String, String, Long) -> Unit = { trace, stage, operation, outcome, at ->
        points += AgentTimingPoint(trace, "a".repeat(32), stage, at, 0, operation, outcome = outcome)
    }
    private fun <T> capture(task: String = "private-task", block: () -> T): T =
        AgentPlanningTiming.capture(task, emit, { now }, block)
    private fun metric(phase: String) = AgentLatencyContract.summarize(points).getValue("phone_planning_${phase}_ms")

    @Test fun recordsExactPhaseDurationsWithoutPayloads() {
        val result = capture {
            AgentPlanningTiming.measure("inventory") { now += 4_000_000 }
            AgentPlanningTiming.measure("plan") { now += 2_000_000 }
            "private answer"
        }
        assertEquals("private answer", result)
        assertEquals(6.0, metric("total").p95Ms!!, 0.0)
        assertEquals(4.0, metric("inventory").p95Ms!!, 0.0)
        assertTrue(points.all(AgentLatencyContract::valid))
        assertFalse(points.toString().contains("private"))
    }

    @Test fun repeatedPlansAndStagesRemainSeparateSamples() {
        repeat(3) { capture { repeat(2) { AgentPlanningTiming.measure("plan") { now += 1_000_000 } } } }
        assertEquals(3, metric("total").count)
        assertEquals(6, metric("plan").count)
        assertEquals(9, points.map { it.operationId }.distinct().size)
    }

    @Test fun nestedScopesRestoreParentAndDoNotLeakAfterExit() {
        capture("parent") {
            capture("child") { AgentPlanningTiming.measure("plan") {} }
            AgentPlanningTiming.measure("context") {}
        }
        val size = points.size
        AgentPlanningTiming.measure("plan") {}
        assertEquals(size, points.size)
        assertEquals(AgentLatencyContract.opaqueId("parent"), points.first { it.stage == "phone_planning_context_started" }.traceId)
        assertEquals(AgentLatencyContract.opaqueId("child"), points.first { it.stage == "phone_planning_plan_started" }.traceId)
    }

    @Test fun originalFailureIsPreservedAndScopeRemoved() {
        val failure = IllegalStateException("business failure")
        try {
            capture { AgentPlanningTiming.measure("plan") { throw failure } }
            fail("Expected failure")
        } catch (actual: IllegalStateException) { assertSame(failure, actual) }
        assertEquals(1, metric("total").unsuccessful)
        assertEquals(1, metric("plan").unsuccessful)
        val size = points.size
        AgentPlanningTiming.measure("plan") {}
        assertEquals(size, points.size)
    }

    @Test fun cancellationIsNotSuccessfulPlanning() {
        val cancelled = CancellationException("cancel")
        try { capture { throw cancelled } } catch (actual: CancellationException) { assertSame(cancelled, actual) }
        assertEquals("cancelled", points.last().outcome)
        assertEquals(0, metric("total").count)
    }

    @Test fun failingDiagnosticWriterCannotRepeatOrBreakBusinessWork() {
        var calls = 0
        val result = AgentPlanningTiming.capture("task", { _, _, _, _, _ -> error("writer") }) {
            AgentPlanningTiming.measure("plan") { calls++; 42 }
        }
        assertEquals(42, result)
        assertEquals(1, calls)
    }

    @Test fun failingClockCannotBreakBusinessWork() {
        assertEquals(42, AgentPlanningTiming.capture("task", emit, { error("clock") }) { 42 })
        assertTrue(points.isEmpty())
    }

    @Test fun unknownPhasesAndUnscopedWorkAreNotRecorded() {
        capture("") { AgentPlanningTiming.measure("plan") {} }
        assertTrue(points.isEmpty())
        capture { AgentPlanningTiming.measure("sensitive user text") {} }
        assertEquals(2, points.size)
        assertTrue(points.all { "total" in it.stage })
    }

    @Test fun workerThreadsNeverInheritAnotherTaskScope() {
        val worker = Executors.newSingleThreadExecutor()
        try {
            capture {
                worker.submit<Int> { AgentPlanningTiming.measure("plan") { 7 } }.get(5, TimeUnit.SECONDS)
            }
            assertEquals(0, metric("plan").count)
        } finally { worker.shutdownNow() }
    }
}
