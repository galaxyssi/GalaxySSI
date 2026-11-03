package com.galaxyssi.chat.voice.asr.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AsrTranscriptCompletenessPolicyTest {
    @Test fun knownInputLossRequiresFullPcmEvenWithinTheDurationTolerance() {
        for (capturedMs in listOf(null, 2_100L)) {
            val decision = AsrTranscriptCompletenessPolicy.evaluate(
                text = "missing a word", decoderComplete = true,
                decodedAudioMs = 2_000, capturedSpeechMs = capturedMs, audioInputComplete = false)
            assertFalse(decision.accepted)
            assertEquals("incomplete_audio_input", decision.reasonCode)
        }
    }

    @Test
    fun `complete transcript with full speech coverage is accepted`() {
        val decision = AsrTranscriptCompletenessPolicy.evaluate(
            text = "complete sentence",
            decoderComplete = true,
            decodedAudioMs = 2_400L,
            capturedSpeechMs = 2_600L
        )

        assertTrue(decision.accepted)
        assertEquals("complete", decision.reasonCode)
    }

    @Test
    fun `decoder token or context limit always rejects fast result`() {
        val decision = AsrTranscriptCompletenessPolicy.evaluate(
            text = "truncated",
            decoderComplete = false,
            decodedAudioMs = 2_000L,
            capturedSpeechMs = 2_000L
        )

        assertFalse(decision.accepted)
        assertEquals("decoder_output_limit", decision.reasonCode)
    }

    @Test
    fun `missing a material part of captured speech falls back to full pcm`() {
        val decision = AsrTranscriptCompletenessPolicy.evaluate(
            text = "partial",
            decoderComplete = true,
            decodedAudioMs = 2_000L,
            capturedSpeechMs = 4_000L
        )

        assertFalse(decision.accepted)
        assertEquals("incomplete_audio_coverage", decision.reasonCode)
        assertEquals(2_000L, decision.missingCoverageMs)
    }

    @Test
    fun `unknown speech boundaries do not reject an otherwise complete result`() {
        assertTrue(
            AsrTranscriptCompletenessPolicy.evaluate(
                text = "complete",
                decoderComplete = true,
                decodedAudioMs = 1_000L,
                capturedSpeechMs = null
            ).accepted
        )
    }
}
