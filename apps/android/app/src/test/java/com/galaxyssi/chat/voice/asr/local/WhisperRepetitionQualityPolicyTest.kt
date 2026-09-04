package com.galaxyssi.chat.voice.asr.local

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WhisperRepetitionQualityPolicyTest {
    @Test
    fun repeatedTokenLoopIsSuspicious() {
        val quality = WhisperRepetitionQualityPolicy.evaluate(
            text = "hello weather hello weather hello weather hello weather",
            tokenIds = listOf(1, 2, 1, 2, 1, 2, 1, 2)
        )

        assertTrue(quality.suspicious)
        assertTrue(quality.repeatedNgramRatio > 0.35)
    }

    @Test
    fun ordinaryTranscriptIsAccepted() {
        val quality = WhisperRepetitionQualityPolicy.evaluate(
            text = "Please check today's weather in Shanghai and summarize the result.",
            tokenIds = (1..14).toList()
        )

        assertFalse(quality.suspicious)
    }
}
