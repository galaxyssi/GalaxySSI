package com.galaxyssi.chat.voice.reliability

import android.os.PowerManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceResourceGovernorTest {
    private var now = 0L
    private val governor = VoiceResourceGovernor(
        thermalController = VoiceThermalController(
            elapsedRealtime = { now },
            moderateCooldownMs = 1_000L,
            severeCooldownMs = 2_000L,
            criticalCooldownMs = 3_000L
        )
    )

    @Test
    fun `certified peak memory is preferred and blocks unsafe load`() {
        val decision = governor.evaluate(
            snapshot(availableMb = 700, currentPssMb = 300),
            localWorkload(certifiedPeakMb = 900)
        )

        assertFalse(decision.allowed)
        assertEquals(VoiceResourceMode.BLOCKED, decision.mode)
        assertTrue(VoiceResourceReason.INSUFFICIENT_MEMORY_HEADROOM in decision.reasons)
    }

    @Test
    fun `incremental model footprint does not subtract memory already used by other models`() {
        val decision = governor.evaluate(
            snapshot(availableMb = 3_500, currentPssMb = 2_500),
            localWorkload(certifiedPeakMb = 0).copy(
                estimatedIncrementalMemoryBytes = 3_000L.mb
            )
        )

        assertFalse(decision.allowed)
        assertTrue(VoiceResourceReason.INSUFFICIENT_MEMORY_HEADROOM in decision.reasons)
    }

    @Test
    fun `low memory signal is a hard gate even with nominal bytes`() {
        val decision = governor.evaluate(
            snapshot(availableMb = 2_000, currentPssMb = 200).copy(lowMemory = true),
            localWorkload(certifiedPeakMb = 400)
        )

        assertFalse(decision.allowed)
        assertTrue(decision.releaseLargeModels)
        assertTrue(VoiceResourceReason.LOW_MEMORY_SIGNAL in decision.reasons)
    }

    @Test
    fun `moderate thermal pressure slows partials and preserves final`() {
        val decision = governor.evaluate(
            snapshot(thermal = PowerManager.THERMAL_STATUS_MODERATE),
            localWorkload(certifiedPeakMb = 400)
        )

        assertTrue(decision.allowed)
        assertEquals(VoiceResourceMode.CONSERVE, decision.mode)
        assertEquals(2, decision.partialIntervalMultiplier)
        assertTrue(decision.allowSecondPass)
    }

    @Test
    fun `severe thermal pressure disables second pass and releases large models`() {
        val decision = governor.evaluate(
            snapshot(thermal = PowerManager.THERMAL_STATUS_SEVERE),
            localWorkload(certifiedPeakMb = 400)
        )

        assertTrue(decision.allowed)
        assertEquals(VoiceResourceMode.DEGRADED, decision.mode)
        assertFalse(decision.allowSecondPass)
        assertTrue(decision.releaseLargeModels)
        assertEquals(2, decision.maximumThreads)
    }

    @Test
    fun `severe thermal pressure blocks high memory model but keeps small fallback eligible`() {
        val hot = snapshot(thermal = PowerManager.THERMAL_STATUS_SEVERE)
        val large = localWorkload(certifiedPeakMb = 400).copy(highMemoryLocalModel = true)

        assertFalse(governor.evaluate(hot, large).allowed)
        assertTrue(governor.evaluate(hot, localWorkload(certifiedPeakMb = 400)).allowed)
    }

    @Test
    fun `critical thermal pressure blocks local inference through cooldown`() {
        assertFalse(governor.evaluate(
            snapshot(thermal = PowerManager.THERMAL_STATUS_CRITICAL),
            localWorkload(certifiedPeakMb = 400)
        ).allowed)

        now += 2_999L
        assertFalse(governor.evaluate(snapshot(), localWorkload(certifiedPeakMb = 400)).allowed)

        now += 2L
        assertTrue(governor.evaluate(snapshot(), localWorkload(certifiedPeakMb = 400)).allowed)
    }

    @Test
    fun `network workload falls back immediately while offline`() {
        val decision = governor.evaluate(
            snapshot().copy(networkAvailable = false),
            VoiceWorkloadProfile(
                feature = VoicePipelineFeature.ONLINE_REALTIME_ASR,
                requiresNetwork = true
            )
        )

        assertFalse(decision.allowed)
        assertTrue(VoiceResourceReason.NETWORK_UNAVAILABLE in decision.reasons)
    }

    @Test
    fun `critical battery does not block local or online voice work`() {
        val constrained = snapshot().copy(batteryPercent = 5, charging = false)
        assertTrue(governor.evaluate(constrained, localWorkload(certifiedPeakMb = 400)).allowed)
        assertTrue(governor.evaluate(
            constrained,
            VoiceWorkloadProfile(VoicePipelineFeature.ONLINE_REALTIME_ASR, requiresNetwork = true)
        ).allowed)
    }

    private fun snapshot(
        availableMb: Long = 2_000,
        totalMb: Long = 8_000,
        currentPssMb: Long = 300,
        thermal: Int = PowerManager.THERMAL_STATUS_NONE
    ) = VoiceResourceSnapshot(
        elapsedRealtimeMs = now,
        availableMemoryBytes = availableMb.mb,
        totalMemoryBytes = totalMb.mb,
        currentPssBytes = currentPssMb.mb,
        thermalStatus = thermal
    )

    private fun localWorkload(certifiedPeakMb: Long) = VoiceWorkloadProfile(
        feature = VoicePipelineFeature.LOCAL_WHISPER_REALTIME,
        profileId = "base",
        certifiedPeakPssBytes = certifiedPeakMb.mb,
        localInference = true,
        allowBackground = false
    )

    private val Long.mb: Long
        get() = this * 1024L * 1024L
}
