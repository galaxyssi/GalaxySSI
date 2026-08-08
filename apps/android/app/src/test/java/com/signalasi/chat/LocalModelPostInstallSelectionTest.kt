package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class LocalModelPostInstallSelectionTest {
    @Test
    fun qwenQnnIsEnabledAfterItsVerifiedInstall() {
        assertEquals(
            setOf(LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN.id),
            LocalModelPostInstallSelection.enabledQnnProfiles(
                emptySet(),
                LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN.id
            )
        )
    }

    @Test
    fun installingGemmaKeepsQwenEnabledForCooperation() {
        assertEquals(
            setOf(
                LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN.id,
                LocalModelRuntimeProfiles.GEMMA_4_E4B_QNN.id
            ),
            LocalModelPostInstallSelection.enabledQnnProfiles(
                setOf(LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN.id),
                LocalModelRuntimeProfiles.GEMMA_4_E4B_QNN.id
            )
        )
    }
}
