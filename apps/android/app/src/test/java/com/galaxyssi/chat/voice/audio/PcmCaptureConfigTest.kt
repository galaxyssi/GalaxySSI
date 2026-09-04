package com.galaxyssi.chat.voice.audio

import org.junit.Assert.assertEquals
import org.junit.Test

class PcmCaptureConfigTest {
    @Test
    fun whisperCapturePrefers16KhzAndFallsBackTo48Khz() {
        val config = PcmCaptureConfig(frameDurationMs = 10)

        assertEquals(listOf(16_000, 48_000), config.captureSampleRateCandidates())
        assertEquals(160, config.samplesPerFrame)
        assertEquals(160, config.captureSamplesPerFrame(16_000))
        assertEquals(480, config.captureSamplesPerFrame(48_000))
    }

    @Test
    fun nonWhisperCaptureDoesNotInventFallbackRates() {
        val config = PcmCaptureConfig(sampleRateHz = 8_000, frameDurationMs = 20)

        assertEquals(listOf(8_000), config.captureSampleRateCandidates())
        assertEquals(160, config.captureSamplesPerFrame(8_000))
    }
}
