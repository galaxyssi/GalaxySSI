package com.galaxyssi.chat.voice.asr.local

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer

class AdaptiveAsrRuntimePolicyTest {
    private val planner = AdaptiveAsrRuntimePolicyPlanner()

    @Test
    fun `performance modes map to their product update strategy`() {
        val fast = planner.resolve(
            AsrConfig(updateIntervalMs = 600L, performanceMode = AsrPerformanceMode.FAST),
            continuousUseMs = 0L,
            thermalStatus = AsrRuntimePolicy.THERMAL_STATUS_NONE,
            systemPowerSaveMode = false
        )
        val balanced = planner.resolve(
            AsrConfig(),
            continuousUseMs = 0L,
            thermalStatus = AsrRuntimePolicy.THERMAL_STATUS_NONE,
            systemPowerSaveMode = false
        )
        val saver = planner.resolve(
            AsrConfig(updateIntervalMs = 1_200L, performanceMode = AsrPerformanceMode.POWER_SAVER),
            continuousUseMs = 0L,
            thermalStatus = AsrRuntimePolicy.THERMAL_STATUS_NONE,
            systemPowerSaveMode = false
        )

        assertEquals(600L, fast.partialIntervalMs)
        assertTrue(fast.emitIntermediateResults)
        assertEquals(900L, balanced.partialIntervalMs)
        assertTrue(balanced.emitIntermediateResults)
        assertEquals(1_200L, saver.partialIntervalMs)
        assertFalse(saver.emitIntermediateResults)
    }

    @Test
    fun `continuous use and thermal pressure progressively reduce NPU work`() {
        val config = AsrConfig(updateIntervalMs = 600L, performanceMode = AsrPerformanceMode.FAST)
        val longRunning = planner.resolve(
            config,
            continuousUseMs = 5L * 60L * 1_000L,
            thermalStatus = AsrRuntimePolicy.THERMAL_STATUS_NONE,
            systemPowerSaveMode = false
        )
        val warm = planner.resolve(
            config,
            continuousUseMs = 0L,
            thermalStatus = AsrRuntimePolicy.THERMAL_STATUS_MODERATE,
            systemPowerSaveMode = false
        )
        val severe = planner.resolve(
            config,
            continuousUseMs = 0L,
            thermalStatus = AsrRuntimePolicy.THERMAL_STATUS_SEVERE,
            systemPowerSaveMode = false
        )

        assertEquals(1_200L, longRunning.partialIntervalMs)
        assertTrue(AsrRuntimePolicyReason.CONTINUOUS_USE in longRunning.reasons)
        assertEquals(1_000L, warm.partialIntervalMs)
        assertTrue(warm.emitIntermediateResults)
        assertFalse(severe.emitIntermediateResults)
        assertTrue(AsrRuntimePolicyReason.THERMAL_SEVERE in severe.reasons)
    }

    @Test
    fun `runtime environment updates active session and pauses only at critical thermal status`() {
        var now = 1_000L
        val engine = RecordingEngine()
        val lifecycle = LocalAsrLifecycleCoordinator(engine)
        val controller = LocalAsrRuntimeEnvironmentController(engine, lifecycle, { now })
        val config = AsrConfig(updateIntervalMs = 600L, performanceMode = AsrPerformanceMode.FAST)

        engine.transition(LocalAsrState.Starting(11L, config))
        controller.onEngineStateChanged(LocalAsrState.Starting(11L, config))
        assertEquals(600L, engine.policies.last().partialIntervalMs)
        now += 5L * 60L * 1_000L
        controller.tick()
        assertEquals(1_200L, engine.policies.last().partialIntervalMs)

        controller.onThermalStatusChanged(AsrRuntimePolicy.THERMAL_STATUS_SEVERE)
        assertFalse(engine.policies.last().emitIntermediateResults)
        assertEquals(0, engine.pauseCount)
        controller.onThermalStatusChanged(AsrRuntimePolicy.THERMAL_STATUS_CRITICAL)
        assertEquals(1, engine.pauseCount)
        controller.onThermalStatusChanged(AsrRuntimePolicy.THERMAL_STATUS_NONE)
        assertEquals(1, engine.resumeCount)
    }

    private class RecordingEngine : LocalAsrEngine {
        private val mutableState = MutableStateFlow<LocalAsrState>(LocalAsrState.Unprepared)
        override val state: StateFlow<LocalAsrState> = mutableState
        override val events: Flow<AsrEvent> = MutableSharedFlow()
        val policies = mutableListOf<AsrRuntimePolicy>()
        var pauseCount = 0
        var resumeCount = 0

        override suspend fun prepare(modelDirectory: String) = Unit
        override fun start(config: AsrConfig) = Unit
        override fun pushPcm(pcm: ByteBuffer, sampleCount: Int): Boolean = true
        override fun stop() = Unit
        override fun cancel() = Unit

        override fun pause(reason: LocalAsrPauseReason) {
            pauseCount += 1
            mutableState.value = LocalAsrState.Paused(11L, AsrConfig(), setOf(reason))
        }

        override fun resume(reason: LocalAsrPauseReason) {
            resumeCount += 1
            mutableState.value = LocalAsrState.Listening(11L, AsrConfig())
        }

        override fun updateRuntimePolicy(policy: AsrRuntimePolicy) {
            policies += policy
        }

        fun transition(state: LocalAsrState) {
            mutableState.value = state
        }

        override fun close() = Unit
    }
}
