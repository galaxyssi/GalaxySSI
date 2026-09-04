package com.galaxyssi.chat.voice.audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin

class AdaptiveVoiceDetectionTest {
    @Test
    fun vadAdaptsToSilenceAndDetectsSpeechBoundaries() {
        val vad = AdaptiveSpeechVad()
        repeat(12) { index ->
            val decision = vad.accept(frame(index.toLong(), ShortArray(320)))
            assertFalse(decision.isSpeech)
        }

        var started = false
        repeat(8) { index ->
            val samples = ShortArray(320) { sample ->
                (sin(2.0 * PI * sample / 37.0) * 7_000).toInt().toShort()
            }
            started = vad.accept(frame((12 + index).toLong(), samples)).speechStarted || started
        }
        assertTrue(started)

        var ended = false
        repeat(8) { index ->
            ended = vad.accept(frame((20 + index).toLong(), ShortArray(320))).speechEndedCandidate || ended
        }
        assertTrue(ended)
    }

    @Test
    fun adaptiveEndpointEndsWithinTargetTailWindow() {
        val endpoint = AdaptiveEndpointDetector(
            sampleRateHz = 16_000,
            config = AdaptiveEndpointConfig(normalUtteranceSilenceMs = 650L),
            autoEndpoint = true
        )
        var terminal: EndpointReason? = null
        repeat(100) { index ->
            terminal = endpoint.accept(frame(index.toLong(), ShortArray(320)), speechDecision()).endpointReason
        }
        assertEquals(null, terminal)
        repeat(60) { index ->
            terminal = endpoint.accept(frame((100 + index).toLong(), ShortArray(320)), silenceDecision()).endpointReason
            if (terminal != null) return@repeat
        }

        assertEquals(EndpointReason.TRAILING_SILENCE, terminal)
    }

    @Test
    fun noSpeechTimeoutIsBounded() {
        val endpoint = AdaptiveEndpointDetector(16_000)
        var update = EndpointUpdate(0)
        repeat(125) { index ->
            update = endpoint.accept(frame(index.toLong(), ShortArray(320)), silenceDecision())
        }
        assertEquals(EndpointReason.NO_SPEECH_TIMEOUT, update.endpointReason)
        assertEquals(2_500L, update.elapsedMs)
    }

    private fun speechDecision() = VadDecision(0.95f, true, false, false, 0.2f, 7_000, -58f)
    private fun silenceDecision() = VadDecision(0.02f, false, false, false, 0f, 0, -58f)

    private fun frame(sequence: Long, samples: ShortArray) = AudioFrame(
        sequence,
        sequence * 20_000_000L,
        samples,
        samples.size,
        {}
    )
}
