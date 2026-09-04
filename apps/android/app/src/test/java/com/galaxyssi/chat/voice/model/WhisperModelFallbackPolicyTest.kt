package com.galaxyssi.chat.voice.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WhisperModelFallbackPolicyTest {
    @Test
    fun `large v3 prefers its installed quantized variant`() {
        val requested = WhisperModelCatalog.require("large")
        val selected = WhisperModelFallbackPolicy.select(
            requested = requested,
            installedProfiles = listOf(
                WhisperModelCatalog.require("tiny"),
                WhisperModelCatalog.require("medium"),
                WhisperModelCatalog.require("large_v3_q5_0")
            ),
            canRun = { true }
        )

        assertEquals("large_v3_q5_0", selected?.id)
    }

    @Test
    fun `fallback skips candidates rejected by current resources`() {
        val requested = WhisperModelCatalog.require("large")
        val selected = WhisperModelFallbackPolicy.select(
            requested = requested,
            installedProfiles = listOf(
                WhisperModelCatalog.require("tiny"),
                WhisperModelCatalog.require("large_v3_q5_0")
            ),
            canRun = { it.id != "large_v3_q5_0" }
        )

        assertEquals("tiny", selected?.id)
    }

    @Test
    fun `fallback never chooses a model larger than the failed request`() {
        val requested = WhisperModelCatalog.require("tiny_q5_1")
        val selected = WhisperModelFallbackPolicy.select(
            requested = requested,
            installedProfiles = WhisperModelCatalog.profiles,
            canRun = { true }
        )

        assertNull(selected)
    }

    @Test
    fun `realtime rescue rejects heavyweight final only models`() {
        val selected = WhisperModelFallbackPolicy.selectRealtimeRescue(
            installedProfiles = listOf(
                WhisperModelCatalog.require("large_v3_turbo_q5_0"),
                WhisperModelCatalog.require("small_q5_1"),
                WhisperModelCatalog.require("tiny")
            ),
            canRun = { true }
        )

        assertEquals("tiny", selected?.id)
    }

    @Test
    fun `realtime rescue prefers the smallest runnable installed model`() {
        val selected = WhisperModelFallbackPolicy.selectRealtimeRescue(
            installedProfiles = listOf(
                WhisperModelCatalog.require("base"),
                WhisperModelCatalog.require("tiny"),
                WhisperModelCatalog.require("tiny_q5_1")
            ),
            canRun = { it.id != "tiny_q5_1" }
        )

        assertEquals("tiny", selected?.id)
    }
}
