package com.galaxyssi.chat.voice.reliability

import android.os.PowerManager
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceReliabilityStressTest {
    @Test
    fun `ten thousand network transitions never admit online work while offline`() {
        var now = 0L
        val governor = VoiceResourceGovernor(
            thermalController = VoiceThermalController({ now }, 5, 10, 20)
        )
        val workload = VoiceWorkloadProfile(
            VoicePipelineFeature.ONLINE_REALTIME_ASR,
            requiresNetwork = true
        )
        repeat(10_000) { index ->
            now += 1
            val online = index % 3 != 0
            val decision = governor.evaluate(snapshot(now).copy(networkAvailable = online), workload)
            if (online) assertTrue(decision.allowed) else assertFalse(decision.allowed)
        }
    }

    @Test
    fun `thermal churn cannot bypass critical cooldown`() {
        var now = 0L
        val governor = VoiceResourceGovernor(
            thermalController = VoiceThermalController({ now }, 4, 8, 16)
        )
        val workload = VoiceWorkloadProfile(
            VoicePipelineFeature.LOCAL_WHISPER_REALTIME,
            certifiedPeakPssBytes = 500L * 1024L * 1024L,
            localInference = true
        )
        repeat(2_000) { index ->
            now += 1
            val thermal = if (index % 31 == 0) PowerManager.THERMAL_STATUS_CRITICAL else 0
            val decision = governor.evaluate(snapshot(now).copy(thermalStatus = thermal), workload)
            if (thermal == PowerManager.THERMAL_STATUS_CRITICAL) assertFalse(decision.allowed)
        }
    }

    @Test
    fun `repeated provider failures stay bounded and recover through one probe`() {
        var now = 1L
        val breaker = VoiceCircuitBreaker(
            elapsedRealtime = { now },
            config = VoiceCircuitBreakerConfig(
                transientFailureThreshold = 3,
                defaultOpenMs = 10L
            )
        )
        val key = VoiceCircuitKey(VoicePipelineFeature.ONLINE_REALTIME_ASR)
        repeat(1_000) {
            if (breaker.admit(key).allowed) {
                breaker.failure(key, VoiceFailureKind.TRANSIENT_NETWORK)
            }
            now += 1L
        }
        now += 20L
        assertTrue(breaker.admit(key).allowed)
        assertFalse(breaker.admit(key).allowed)
        breaker.success(key)
        assertTrue(breaker.admit(key).allowed)
    }

    private fun snapshot(now: Long) = VoiceResourceSnapshot(
        elapsedRealtimeMs = now,
        availableMemoryBytes = 3L * 1024L * 1024L * 1024L,
        totalMemoryBytes = 8L * 1024L * 1024L * 1024L,
        currentPssBytes = 300L * 1024L * 1024L
    )
}
