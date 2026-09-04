package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalModelInferenceRuntimeTest {
    @Test
    fun qairtIsReservedForInteractiveRequests() {
        assertFalse(LocalModelInferenceRuntime.backgroundSafe(LocalModelRuntimeProfiles.QWEN_3_1_7B_QAIRT))
        assertTrue(LocalModelInferenceRuntime.backgroundSafe(LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN))
        assertTrue(LocalModelInferenceRuntime.backgroundSafe(LocalModelRuntimeProfiles.GEMMA_4_E4B_QNN))
    }

    @Test
    fun qnnProfilesUseGenieXNpuAndCpuProfilesKeepLegacyRuntime() {
        assertEquals(
            LocalModelInferenceEngine.GENIEX_NPU,
            LocalModelInferenceRuntime.engineFor(LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN)
        )
        assertEquals(
            LocalModelInferenceEngine.GENIEX_NPU,
            LocalModelInferenceRuntime.engineFor(LocalModelRuntimeProfiles.GEMMA_4_E4B_QNN)
        )
        assertEquals(
            LocalModelInferenceEngine.LEGACY_LLAMA,
            LocalModelInferenceRuntime.engineFor(LocalModelRuntimeProfiles.GEMMA_3_1B_Q4)
        )
    }

    @Test
    fun everyNativeModelEngineRunsOutsideTheUiProcess() {
        assertTrue(
            LocalModelInferenceRuntime.requiresIsolatedProcess(
                LocalModelRuntimeProfiles.GEMMA_3_1B_Q4
            )
        )
        assertTrue(
            LocalModelInferenceRuntime.requiresIsolatedProcess(
                LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN
            )
        )
    }

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

    @Test
    fun complexQwenRequestReplacesNoThinkWithThink() {
        val prompt = LocalModelInferenceRuntime.prepareUserPrompt(
            LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN,
            "Plan this task.\n/no_think",
            LocalModelThinkingMode.THINK
        )

        assertTrue(prompt.endsWith("\n/think"))
        assertFalse(prompt.contains("/no_think"))
    }

    @Test
    fun fastQwenRequestReplacesThinkWithNoThink() {
        val prompt = LocalModelInferenceRuntime.prepareUserPrompt(
            LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN,
            "Answer briefly.\n/think",
            LocalModelThinkingMode.NO_THINK
        )

        assertTrue(prompt.endsWith("\n/no_think"))
        assertFalse(Regex("(?m)^/think$").containsMatchIn(prompt))
    }
}
