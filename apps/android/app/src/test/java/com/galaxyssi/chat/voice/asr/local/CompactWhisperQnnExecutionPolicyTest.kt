package com.galaxyssi.chat.voice.asr.local

import com.galaxyssi.chat.VoiceAssistantSettings
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CompactWhisperQnnExecutionPolicyTest {
    @Test
    fun `explicit compact QNN selection cannot silently fall back to CPU`() {
        assertTrue(requiresCompactQnnExecution(
            VoiceAssistantSettings.ASR_ACCELERATION_QNN,
            "whisper-small-qnn-w8a16-s26u"
        ))
    }

    @Test
    fun `large turbo independent selection does not use compact package policy`() {
        assertFalse(requiresCompactQnnExecution(
            VoiceAssistantSettings.ASR_ACCELERATION_QNN,
            ""
        ))
    }

    @Test
    fun `GGML selection remains outside strict QNN policy`() {
        assertFalse(requiresCompactQnnExecution(
            VoiceAssistantSettings.ASR_ACCELERATION_GGML,
            "whisper-tiny-qnn-float-s26u"
        ))
    }
}
