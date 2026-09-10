package com.galaxyssi.chat

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.metrics.*
import java.io.File
import java.util.Collections
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentModelTimingDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun realLlamaServiceFailureRelaysWorkerEventsToTheCallerJournal() {
        verifyMissingModel(LocalModelRuntimeProfiles.GEMMA_3_1B_Q4)
    }

    @Test fun realQnnServiceFailureRelaysWorkerEventsWithoutInitializingAModel() {
        verifyMissingModel(LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN)
    }

    @Test fun brokenTimingSinkDoesNotReplaceTheActualServiceError() {
        requireEmptyModelInventory()
        val profile = LocalModelRuntimeProfiles.GEMMA_3_1B_Q4
        val baseline = failure(profile, AgentModelTiming.NONE)
        val broken = AgentModelTiming(AgentLatencyContract.opaqueId("broken-model-timing"),
            { error("diagnostic writer failure") }, provider = LocalModelInferenceRuntime.engineFor(profile).name)
        val actual = failure(profile, broken)
        assertEquals(baseline::class.java, actual::class.java)
        assertEquals(baseline.message, actual.message)
        assertFalse(actual.message.orEmpty().contains("diagnostic writer"))
    }

    private fun verifyMissingModel(profile: LocalModelRuntimeProfile) {
        requireEmptyModelInventory()
        val directory = File(context.cacheDir, "model-timing-${UUID.randomUUID()}").apply { mkdirs() }
        val file = File(directory, "timings.jsonl")
        val journal = AgentTimingJournal(file)
        val received = Collections.synchronizedList(mutableListOf<AgentTimingPoint>())
        val trace = AgentLatencyContract.opaqueId("private-model-task-${UUID.randomUUID()}")
        val timing = AgentModelTiming(trace, { received += it; journal.append(it) },
            provider = LocalModelInferenceRuntime.engineFor(profile).name,
            clockId = "1".repeat(32), nowNs = SystemClock::elapsedRealtimeNanos)
        try {
            try { assertTrue(failure(profile, timing).message.orEmpty().isNotBlank()) }
            finally { journal.close() }
            val metrics = AgentLatencyContract.summarize(journal.snapshot())
            assertEquals(1, metrics.getValue("phone_model_service_bind_ms").count)
            assertEquals(1, metrics.getValue("phone_model_service_queue_ms").count)
            assertEquals(1, metrics.getValue("phone_model_process_roundtrip_ms").unsuccessful)
            assertEquals(0, metrics.getValue("phone_model_process_roundtrip_ms").count)
            assertEquals(0, metrics.getValue("phone_model_load_ms").count)
            assertEquals(0, metrics.getValue("phone_model_generate_ms").count)
            val release = metrics.getValue("phone_model_release_ms")
            assertEquals(1, release.count + release.unsuccessful)
            val worker = received.filter { it.stage.startsWith("phone_model_service_queue_") }
            assertEquals(2, worker.size)
            assertTrue(worker.all { it.clockId != "1".repeat(32) && it.traceId == trace })
            assertEquals(2, received.map { it.clockId }.distinct().size)
            assertEquals(0L, journal.health()["dropped_events"])
            assertEquals(0L, journal.health()["write_failures"])
            assertFalse(file.readText().contains("private-model-task"))
            assertFalse(file.readText().contains("\u4f60\u597d"))
        } finally { journal.close(); directory.deleteRecursively() }
    }

    private fun requireEmptyModelInventory() {
        assumeTrue("This failure test must not unload a user's installed local model",
            LocalModelCatalog.profiles(context).none { LocalModelManager.isInstalled(context, it) })
    }

    private fun failure(profile: LocalModelRuntimeProfile, timing: AgentModelTiming): Throwable {
        val error = runCatching {
            LocalModelInferenceProcessClient.generate(context, profile, "", "\u4f60\u597d",
                1, 0.0f, LocalModelThinkingMode.NO_THINK, LocalModelWorkClass.INTERACTIVE, timing)
        }.exceptionOrNull()
        assertNotNull("Missing model must fail, not manufacture a response", error)
        return checkNotNull(error)
    }
}
