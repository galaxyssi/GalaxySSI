package com.galaxyssi.chat.voice.reliability

import com.galaxyssi.chat.voice.metrics.VoiceDiagnosticSummary
import com.galaxyssi.chat.voice.metrics.VoiceLatencyPercentiles
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VoicePerformanceDashboardTest {
    @Test
    fun `dashboard exposes p50 p95 and healthy rollout state`() {
        val dashboard = VoicePerformanceDashboard.build(
            generatedAtElapsedMs = 100,
            diagnostics = diagnostics(
                metrics = mapOf("asr_total_ms" to VoiceLatencyPercentiles(40, 300, 500, 700, 900))
            ),
            resource = resource(VoiceResourceMode.NORMAL),
            circuits = emptyList(),
            rollouts = listOf(rollout(VoicePipelineFeature.ONLINE_REALTIME_ASR, enabled = true))
        )

        assertEquals(VoicePerformanceHealth.HEALTHY, dashboard.health)
        assertEquals(300L, dashboard.metrics.single().p50Ms)
        assertEquals(700L, dashboard.metrics.single().p95Ms)
        assertTrue(dashboard.rollouts.getValue(VoicePipelineFeature.ONLINE_REALTIME_ASR).enabled)
    }

    @Test
    fun `open circuit is visible as blocked health`() {
        val circuit = VoiceCircuitRecord(
            VoiceCircuitKey(VoicePipelineFeature.LOCAL_WHISPER_REALTIME, "large"),
            state = VoiceCircuitState.OPEN
        )
        val dashboard = VoicePerformanceDashboard.build(
            100,
            diagnostics(),
            resource(VoiceResourceMode.NORMAL),
            listOf(circuit),
            emptyList()
        )

        assertEquals(VoicePerformanceHealth.BLOCKED, dashboard.health)
        assertEquals(circuit, dashboard.openCircuits.single())
    }

    @Test
    fun `slow p95 and failure rate are not hidden by successful samples`() {
        val dashboard = VoicePerformanceDashboard.build(
            100,
            diagnostics(
                failureRate = 0.12,
                metrics = mapOf("agent_first_output_ms" to VoiceLatencyPercentiles(20, 4_000, 9_000, 15_000, 20_000))
            ),
            resource(VoiceResourceMode.NORMAL),
            emptyList(),
            emptyList()
        )

        assertEquals(VoicePerformanceHealth.DEGRADED, dashboard.health)
        assertEquals(VoicePerformanceHealth.DEGRADED, dashboard.metrics.single().health)
    }

    private fun diagnostics(
        failureRate: Double = 0.0,
        metrics: Map<String, VoiceLatencyPercentiles> = emptyMap()
    ) = VoiceDiagnosticSummary(
        traceCount = 40,
        eventCount = 200,
        completedCount = 40,
        cancelledCount = 0,
        failedCount = 0,
        successRate = 1.0 - failureRate,
        cancellationRate = 0.0,
        failureRate = failureRate,
        fallbackRate = 0.0,
        oomCount = 0,
        nativeCrashCount = 0,
        thermalDegradeCount = 0,
        modelVerificationFailureCount = 0,
        metrics = metrics
    )

    private fun resource(mode: VoiceResourceMode): VoiceResourceDecision {
        val memory = VoiceMemoryGateDecision(true, 0, 1, 0)
        val thermal = VoiceThermalDecision(0, mode, 1, null, true, false)
        return VoiceResourceDecision(true, mode, emptySet(), memory, thermal, null, 1, true, false)
    }

    private fun rollout(feature: VoicePipelineFeature, enabled: Boolean) = VoiceRolloutDecision(
        feature = feature,
        enabled = enabled,
        stage = VoiceRolloutStage.DEVELOPER,
        cohortBucket = 1,
        rollbackLevel = VoiceRollbackLevel.NONE,
        reasonCodes = listOf("rollout_eligible")
    )
}
