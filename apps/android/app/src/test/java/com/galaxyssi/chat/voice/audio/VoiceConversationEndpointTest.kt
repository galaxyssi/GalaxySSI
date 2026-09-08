package com.galaxyssi.chat.voice.audio

import org.junit.Assert.*
import org.junit.Test

class VoiceConversationEndpointTest {
    private val silence = VadDecision(0f, false, false, false, 0f, 0, -58f)
    private val speech = silence.copy(probability = 1f, isSpeech = true, peak = 5_000)

    @Test fun continuousConversationWaitsWithoutReopeningTheMicrophoneEveryThreeSeconds() {
        val detector = AdaptiveEndpointDetector(1_000, AdaptiveEndpointConfig.forVoiceConversation())
        repeat(1_499) { assertNull(detector.accept(frame(it), silence).endpointReason) }
        assertEquals(EndpointReason.NO_SPEECH_TIMEOUT, detector.accept(frame(1_499), silence).endpointReason)
    }

    @Test fun aSpokenUtteranceStillEndpointsQuicklyAfterTheUserStops() {
        val detector = AdaptiveEndpointDetector(1_000, AdaptiveEndpointConfig.forVoiceConversation())
        repeat(200) { assertNull(detector.accept(frame(it), silence).endpointReason) }
        repeat(30) { assertNull(detector.accept(frame(200 + it), speech).endpointReason) }
        var result: EndpointReason? = null
        repeat(50) { result = detector.accept(frame(230 + it), silence).endpointReason }
        assertEquals(EndpointReason.TRAILING_SILENCE, result)
    }

    @Test fun continuousSpeechStillHasABoundedCaptureDuration() {
        val config = AdaptiveEndpointConfig.forVoiceConversation()
        assertEquals(60_000L, config.maxDurationMs)
        val detector = AdaptiveEndpointDetector(1_000, config)
        repeat(2_999) { assertNull(detector.accept(frame(it), speech).endpointReason) }
        assertEquals(EndpointReason.MAX_DURATION, detector.accept(frame(2_999), speech).endpointReason)
    }

    @Test fun ordinaryCommandDefaultRemainsShort() {
        assertEquals(2_500L, AdaptiveEndpointConfig().noSpeechTimeoutMs)
    }

    @Test(expected = IllegalArgumentException::class)
    fun unboundedIdleCaptureIsRejected() {
        AdaptiveEndpointConfig(noSpeechTimeoutMs = 30_001L)
    }

    private fun frame(sequence: Int) = AudioFrame(sequence.toLong(), sequence * 20_000_000L, ShortArray(20), 20, {})
}
