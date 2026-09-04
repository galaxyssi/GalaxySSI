package com.galaxyssi.chat.voice.asr.local

import com.galaxyssi.chat.voice.model.WhisperModelCatalog
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AdaptiveWhisperPartialPolicyTest {
    @Test
    fun tinyStartsFastAndSlowsWhenRealTimeFactorRises() {
        val policy = AdaptiveWhisperPartialPolicy(WhisperModelCatalog.require("tiny"))
        assertTrue(policy.shouldSubmit(1_000L, 1_000L, DecodeQueueSnapshot()))

        policy.onDecodeCompleted(1.1, DecodeQueueSnapshot())
        val degraded = policy.snapshot()

        assertTrue(degraded.enabled)
        assertTrue(degraded.intervalMs > WhisperModelCatalog.require("tiny").defaultPartialIntervalMs)
        assertTrue(degraded.windowMs < WhisperModelCatalog.require("tiny").maxWindowMs)
    }

    @Test
    fun repeatedBacklogSkipsWorkAndIncreasesInterval() {
        val policy = AdaptiveWhisperPartialPolicy(WhisperModelCatalog.require("base"))
        val congested = DecodeQueueSnapshot(queuedPartials = 2)

        assertFalse(policy.shouldSubmit(2_000L, 2_000L, congested))
        val once = policy.snapshot()
        assertFalse(policy.shouldSubmit(4_000L, 4_000L, congested))
        val twice = policy.snapshot()

        assertTrue(twice.intervalMs >= once.intervalMs)
        assertTrue(twice.backlogStreak >= 2)
    }

    @Test
    fun slowProfileNeverOffersRealtimePartial() {
        val policy = AdaptiveWhisperPartialPolicy(WhisperModelCatalog.require("medium"))
        assertFalse(policy.shouldSubmit(10_000L, 10_000L, DecodeQueueSnapshot()))
        assertFalse(policy.snapshot().enabled)
    }

    @Test
    fun certificationCanEnableOrDisablePartialIndependentOfModelName() {
        val measuredFastMedium = AdaptiveWhisperPartialPolicy(
            WhisperModelCatalog.require("medium_q5_0"),
            certifiedPartialIntervalMs = 2_500L,
            realtimeCertified = true
        )
        val untestedTiny = AdaptiveWhisperPartialPolicy(
            WhisperModelCatalog.require("tiny"),
            realtimeCertified = false
        )

        assertTrue(measuredFastMedium.shouldSubmit(3_000L, 3_000L, DecodeQueueSnapshot()))
        assertFalse(untestedTiny.shouldSubmit(3_000L, 3_000L, DecodeQueueSnapshot()))
    }
}
