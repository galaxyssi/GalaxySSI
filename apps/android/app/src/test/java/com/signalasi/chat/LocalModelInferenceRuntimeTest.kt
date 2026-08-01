package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalModelInferenceRuntimeTest {
    @Test
    fun qwenPromptDefaultsToNoThinkExactlyOnce() {
        val prompt = LocalModelInferenceRuntime.prepareUserPrompt(
            LocalModelRuntimeProfiles.QWEN_3_8B_Q4_K_M,
            "Summarize this document."
        )

        assertTrue(prompt.endsWith("\n/no_think"))
        assertEquals(1, Regex("/no_think").findAll(prompt).count())
    }

    @Test
    fun existingNoThinkCommandIsNotDuplicated() {
        val original = "/no_think\nAnswer briefly."

        assertEquals(
            original,
            LocalModelInferenceRuntime.prepareUserPrompt(
                LocalModelRuntimeProfiles.QWEN_3_8B_Q4_K_M,
                original
            )
        )
    }

    @Test
    fun nonThinkingModelIsUnchanged() {
        val prompt = LocalModelInferenceRuntime.prepareUserPrompt(
            LocalModelRuntimeProfiles.GEMMA_3_1B_Q4,
            "Hello"
        )

        assertEquals("Hello", prompt)
        assertFalse(prompt.contains("/no_think"))
    }
}
