package com.galaxyssi.chat

import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.metrics.*
import java.io.File
import java.util.Collections
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentRuntimeTimingDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val screen = ScreenContext("Test", pageTitle = "Isolated timing")
    private val points = Collections.synchronizedList(mutableListOf<AgentTimingPoint>())
    private val timing = AgentRuntimeTiming({ trace, stage, operation, outcome, at ->
        points += AgentTimingPoint(trace, "a".repeat(32), stage, at, 0, operation, outcome = outcome)
    }, SystemClock::elapsedRealtimeNanos)
    private val task = "runtime-timing-${UUID.randomUUID()}"
    private fun action(kind: AgentActionKind = AgentActionKind.CALL_NATIVE_TOOL) = AgentAction(
        UUID.randomUUID().toString(), kind, AgentHardwareNativeTools.MEMORY_STATUS, AgentRisk.LOW,
        AgentActionStatus.PROPOSED, "\u8bfb\u53d6\u624b\u673a\u5185\u5b58",
        mapOf("tool_id" to AgentHardwareNativeTools.MEMORY_STATUS, "input_json" to "{}",
            "_galaxyssi_task_id" to task, INTERNAL_CONVERSATION_ID to task, INTERNAL_TURN_ID to "turn"), false)

    @Test fun actualMemoryReadAndReceiptVerificationHaveSeparateRealSpans() {
        val agent = runtime()
        val action = action()
        val dispatched = agent.executeAction(action, screen)
        assertTrue(dispatched.message, dispatched.success)
        val output = JSONObject(dispatched.metadata.getValue("native_tool_output"))
        assertTrue(output.getLong("total_bytes") > 0)
        val observed = agent.captureVerificationScreen(action, screen, dispatched)
        val verified = requireNotNull(agent.applyObservationResult(action, dispatched, observed))
        assertTrue(verified.success)
        assertEquals(AgentObservationDecision.NO_CHANGE_REQUIRED, observed.decision)
        val metrics = AgentLatencyContract.summarize(points.toList())
        listOf("action_dispatch", "receipt_observe", "result_verify").forEach {
            assertEquals(it, 1, metrics.getValue("phone_runtime_${it}_ms").count)
        }
        assertEquals(0, metrics.getValue("phone_runtime_screen_observe_ms").count)
        assertTrue(points.all { it.traceId == AgentLatencyContract.opaqueId(task) })
        assertFalse(points.toString().contains(task))
        assertFalse(points.toString().contains("total_bytes"))
    }

    @Test fun controlledScreenTimeoutIsNotSuccessfulVerificationLatency() {
        val agent = runtime()
        val action = action(AgentActionKind.OPEN_APP)
        val accepted = AgentActionResult(action.id, true, "Accepted")
        val observed = agent.captureVerificationScreen(action, screen, accepted)
        assertEquals(AgentObservationDecision.TIMED_OUT, observed.decision)
        assertFalse(agent.applyObservationResult(action, accepted, observed)!!.success)
        val metrics = AgentLatencyContract.summarize(points.toList())
        assertEquals(1, metrics.getValue("phone_runtime_screen_observe_ms").unsuccessful)
        assertEquals(0, metrics.getValue("phone_runtime_screen_observe_ms").count)
        assertEquals(1, metrics.getValue("phone_runtime_result_verify_ms").unsuccessful)
    }

    @Test fun failedDispatchAndReplayedReceiptKeepTheirActualOutcomes() {
        var calls = 0
        val agent = runtime(object : AgentActionExecutor {
            override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                calls++
                return AgentActionResult(action.id, false, "Test failure", mapOf("native_tool_status" to "cancelled"))
            }
        })
        val action = action(AgentActionKind.OPEN_APP)
        repeat(2) { assertFalse(agent.executeAction(action, screen).success) }
        assertEquals(1, calls)
        val metric = AgentLatencyContract.summarize(points.toList()).getValue("phone_runtime_action_dispatch_ms")
        assertEquals(0, metric.count)
        assertEquals(2, metric.unsuccessful)
        assertEquals(2, points.count { it.outcome == "cancelled" })
    }

    @Test fun realHardwareProbeTimingHasBoundedAdditionalP95Cost() {
        val directory = File(context.cacheDir, "runtime-stage-${UUID.randomUUID()}")
        try {
            AgentTimingJournal(File(directory, "timings.jsonl")).use { journal ->
                benchmarkWithProductionJournal(journal)
            }
        } finally { directory.deleteRecursively() }
    }

    private fun benchmarkWithProductionJournal(journal: AgentTimingJournal) {
        val agent = runtime()
        val action = action()
        val tracer = AgentLatencyTracer(journal, SystemClock::elapsedRealtimeNanos)
        val recording = AgentRuntimeTiming({ trace, stage, operation, outcome, at ->
            tracer.recordOpaque(trace, stage, operation, outcome, at)
        }, SystemClock::elapsedRealtimeNanos)
        agent.runtimeTiming = recording
        val warmup = action.copy(parameters = action.parameters + ("_galaxyssi_task_id" to "$task-warmup"))
        repeat(20) { assertTrue(agent.executeAction(warmup, screen).success) }
        val enabled = mutableListOf<Double>()
        val disabled = mutableListOf<Double>()
        fun probe(recorder: AgentRuntimeTiming, samples: MutableList<Double>) {
            agent.runtimeTiming = recorder
            val start = SystemClock.elapsedRealtimeNanos()
            val result = agent.executeAction(action, screen)
            samples += (SystemClock.elapsedRealtimeNanos() - start) / 1_000_000.0
            assertTrue(result.message, result.success)
        }
        repeat(100) { index ->
            if (index % 2 == 0) { probe(recording, enabled); probe(AgentRuntimeTiming.NONE, disabled) }
            else { probe(AgentRuntimeTiming.NONE, disabled); probe(recording, enabled) }
        }
        journal.close()
        fun p95(samples: List<Double>) = samples.sorted()[94]
        val measured = AgentLatencyContract.summarize(journal.snapshot().filter {
            it.traceId == AgentLatencyContract.opaqueId(task)
        }).getValue("phone_runtime_action_dispatch_ms")
        assertEquals(100, measured.count)
        assertEquals(0L, journal.health()["dropped_events"])
        assertEquals(0L, journal.health()["write_failures"])
        Log.i("GalaxySSIStageTimingTest", "sink=production_journal real_memory_probes=200 traced=100 baseline_p95_ms=${p95(disabled)} " +
            "traced_p95_ms=${p95(enabled)} span_p50_ms=${measured.p50Ms} span_p95_ms=${measured.p95Ms} span_p99_ms=${measured.p99Ms}")
        assertTrue("Tracing added over 10 ms to real probe P95: baseline=${p95(disabled)} traced=${p95(enabled)}",
            p95(enabled) <= p95(disabled) + 10.0)
    }

    private fun runtime(executor: AgentActionExecutor = object : AgentActionExecutor {
        override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult = error("Unexpected platform action")
    }): MobileNativeAgent = MobileNativeAgent(context,
        sessionStore = InMemoryAgentSessionStore(), memoryStore = InMemoryAgentMemoryStore(),
        actionExecutor = executor, actionEffectReplayStore = InMemoryAgentNativeToolReplayStore(),
        screenObservationOverride = false,
        observationController = AgentContinuousObservationController(maxSamples = 2, stableSampleCount = 2, sampleIntervalMillis = 0),
        nativeToolRegistryProvider = { AgentNativeToolRegistry().registerAll(AgentHardwareNativeTools.definitions(
            AgentAndroidHardwarePlatformFacade(context))) },
        perceptionProvider = object : ScreenPerceptionProvider {
            override fun capture() = screen
            override fun capture(foregroundApp: String, pageTitle: String) = screen
        },
        planner = object : AgentPlanner { override fun plan(request: AgentRequest): AgentPlan = error("No cloud request") },
        connectorRegistry = object : AgentConnectorRegistry { override fun availableTargets() = emptyList<AgentCallableTarget>() },
        taskStore = object : AgentTaskStore {
            override fun upsert(record: AgentTaskRecord) = Unit
            override fun recent(limit: Int) = emptyList<AgentTaskRecord>()
            override fun forSession(sessionId: String, limit: Int) = emptyList<AgentTaskRecord>()
            override fun find(taskId: String): AgentTaskRecord? = null
            override fun search(query: String, limit: Int) = emptyList<AgentTaskRecord>()
            override fun rebindSession(sourceSessionId: String, targetSessionId: String) = 0
            override fun delete(taskIds: Set<String>) = Unit
            override fun clear() = Unit
        }).apply { runtimeTiming = timing; sessionId = task; currentScreen = screen }
}
