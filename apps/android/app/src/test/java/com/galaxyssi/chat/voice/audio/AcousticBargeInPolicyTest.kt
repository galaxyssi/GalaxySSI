package com.galaxyssi.chat.voice.audio

import org.junit.Assert.*
import org.junit.Test

class AcousticBargeInPolicyTest {
    private val voice = VadDecision(0.95f, true, false, false, 0.1f, 5_000, -58f)
    private val silence = VadDecision(0.05f, false, false, false, 0.0001f, 3, -58f)

    @Test fun requiresActualEchoProtectionNotJustBuiltinMic() {
        assertFalse(AcousticBargeInPolicy.hasEchoProtection(PcmRecorderState(inputRoute = "built_in_mic")))
        assertTrue(AcousticBargeInPolicy.hasEchoProtection(PcmRecorderState(acousticEchoCancelerEnabled = true)))
        assertTrue(AcousticBargeInPolicy.hasEchoProtection(PcmRecorderState(inputRoute = "wired_headset")))
        assertFalse(AcousticBargeInPolicy.hasEchoProtection(PcmRecorderState(inputRoute = "default")))
        assertTrue(AcousticBargeInPolicy.hasEchoProtection(PcmRecorderState(inputRoute = "usb_headset")))
        assertFalse(AcousticBargeInPolicy.hasEchoProtection(PcmRecorderState(inputRoute = "usb")))
    }

    @Test fun statisticsMeasureOnlyAggregateGateEvidenceWithoutChangingDetection() {
        val policy = AcousticBargeInPolicy()
        repeat(50) { policy.accept(silence, 320) }
        repeat(5) { policy.accept(voice, 320) }
        var statistics = policy.statistics()
        assertEquals(1100L, statistics.monitoredMs)
        assertEquals(100L, statistics.maxCandidateMs)
        assertEquals(0.1f, statistics.maxRms, 0.00001f)
        assertEquals(0.95f, statistics.maxProbability, 0.00001f)
        assertNull(policy.utteranceStartSample)
        repeat(4) { policy.accept(voice, 320) }
        statistics = policy.statistics()
        assertEquals(180L, statistics.maxCandidateMs)
        assertEquals(16_000L, policy.utteranceStartSample)
    }

    @Test fun settlingAndShortNoiseDoNotInterrupt() {
        val policy = AcousticBargeInPolicy()
        repeat(7) { assertFalse(policy.accept(voice, 320).started) }
        repeat(20) { policy.accept(silence, 320) }
        repeat(4) { assertFalse(policy.accept(voice, 320).started) }
        policy.accept(silence, 320)
        assertNull(policy.utteranceStartSample)
    }

    @Test fun isolatedLoudFramesCannotAccumulateIntoACommand() {
        val policy = AcousticBargeInPolicy()
        repeat(100) {
            assertFalse(policy.accept(voice, 320).started)
            assertFalse(policy.accept(silence, 320).started)
        }
        assertNull(policy.utteranceStartSample)
    }

    @Test fun lowEnergySpeechProbabilityIsNotEnough() {
        val policy = AcousticBargeInPolicy()
        repeat(100) { assertFalse(policy.accept(voice.copy(rms = 0.0002f), 320).started) }
        assertNull(policy.utteranceStartSample)
    }

    @Test fun continuousVoiceStartsExactlyOnceAndRetainsItsBeginning() {
        val policy = AcousticBargeInPolicy()
        repeat(60) { policy.accept(silence, 320) }
        var starts = 0
        repeat(50) { if (policy.accept(voice, 320).started) starts++ }
        assertEquals(1, starts)
        assertEquals(19_200L, policy.utteranceStartSample)
    }

    @Test fun aPauseWithinSpeechDoesNotCutTheUtterance() {
        val policy = AcousticBargeInPolicy()
        repeat(50) { policy.accept(voice, 320) }
        repeat(10) { assertFalse(policy.accept(silence, 320).endpoint) }
        repeat(30) { assertFalse(policy.accept(voice, 320).endpoint) }
        var ends = 0
        repeat(100) { if (policy.accept(silence, 320).endpoint) ends++ }
        assertEquals(1, ends)
    }

    @Test fun longCommandsAndIdleMonitoringAreBounded() {
        val voicePolicy = AcousticBargeInPolicy()
        var ended = false
        repeat(3_200) { ended = voicePolicy.accept(voice, 320).endpoint || ended }
        assertTrue(ended)
        val idlePolicy = AcousticBargeInPolicy()
        var renewals = 0
        repeat(3_000) { if (idlePolicy.accept(silence, 320).renewMonitor) renewals++ }
        assertEquals(1, renewals)
    }

    @Test fun outputContainsPrerollButExcludesEarlierPlayback() {
        val policy = AcousticBargeInPolicy()
        repeat(60) { policy.accept(silence, 320) }
        repeat(30) { policy.accept(voice, 320) }
        repeat(50) { policy.accept(silence, 320) }
        val input = ShortArray(44_800) { (it % 32_000).toShort() }
        val snapshot = PcmSnapshot(input, 16_000, true, 0, 44_800, 0, 44_800)
        val result = requireNotNull(policy.utterance(snapshot))
        assertEquals(14_080L, result.captureStartSample)
        assertEquals(19_200L, result.speechStartSample)
        assertEquals(44_800 - 14_080, result.samples.size)
        assertEquals(input[14_080], result.samples.first())
        assertNotSame(input, result.samples)
    }

    @Test fun speechAtTheMonitorRenewalBoundaryIsNotDiscarded() {
        val policy = AcousticBargeInPolicy()
        repeat(2_497) { policy.accept(silence, 320) }
        var started = false
        repeat(10) {
            val update = policy.accept(voice, 320)
            assertFalse(update.renewMonitor)
            started = update.started || started
        }
        assertTrue(started)
        assertEquals(2_497L * 320L, policy.utteranceStartSample)
    }

    @Test fun noConfirmedSpeechProducesNoUtterance() {
        val policy = AcousticBargeInPolicy()
        assertNull(policy.utterance(PcmSnapshot(ShortArray(320), 16_000, false, null, null, 0, 320)))
    }

    @Test fun rawSnapshotOptionPreservesCaptureOutsideEarlierVadBoundaries() {
        val store = InMemorySpeechSegmentStore(1_000, 5_000)
        repeat(10) { index ->
            store.append(AudioFrame(index.toLong(), index * 20_000_000L, ShortArray(20) { index.toShort() }, 20, {}))
            if (index == 1) store.markSpeechStart(1)
            if (index == 2) store.markSpeechEnd(2)
        }
        val trimmed = store.snapshot(SegmentRange(preRollMs = 0, postRollMs = 0))
        val raw = store.snapshot(SegmentRange(trimToSpeech = false))
        assertEquals(20, trimmed.samples.size)
        assertEquals(200, raw.samples.size)
        assertEquals(0L, raw.captureStartSample)
        assertEquals(200L, raw.captureEndSampleExclusive)
        assertEquals(9.toShort(), raw.samples.last())
    }
}
