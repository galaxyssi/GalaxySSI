package com.galaxyssi.chat.voice.tts

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BargeInControllerTest {
    private class FakeClock(var nowNs: Long = 0L) : BargeInElapsedClock {
        override fun elapsedRealtimeNanos(): Long = nowNs
    }

    @Test
    fun ordinaryModelIsCancelledWithinBargeInBudget() {
        val clock = FakeClock()
        var modelCancelled = false
        var focusReleased = false
        val result = BargeInController(clock).interrupt(
            BargeInTaskKind.ORDINARY_MODEL,
            BargeInActions(
                stopSpeech = {
                    clock.nowNs += 120_000_000L
                    true
                },
                cancelOrdinaryModel = { modelCancelled = true },
                releaseAudioFocus = { focusReleased = true }
            )
        )

        assertTrue(result.speechInterrupted)
        assertTrue(result.ordinaryModelCancelled)
        assertTrue(modelCancelled)
        assertTrue(focusReleased)
        assertTrue(result.elapsedMs <= 300L)
    }

    @Test
    fun persistentAgentIsRetainedWhileSpeechStops() {
        var modelCancelled = false
        val result = BargeInController().interrupt(
            BargeInTaskKind.PERSISTENT_AGENT,
            BargeInActions(
                stopSpeech = { true },
                cancelOrdinaryModel = { modelCancelled = true },
                releaseAudioFocus = {}
            )
        )

        assertTrue(result.speechInterrupted)
        assertTrue(result.persistentAgentRetained)
        assertFalse(result.ordinaryModelCancelled)
        assertFalse(modelCancelled)
    }

    @Test
    fun noActiveSpeechStillReleasesAudioFocus() {
        var focusReleases = 0
        val result = BargeInController().interrupt(
            BargeInTaskKind.NONE,
            BargeInActions(
                stopSpeech = { false },
                cancelOrdinaryModel = {},
                releaseAudioFocus = { focusReleases += 1 }
            )
        )

        assertFalse(result.speechInterrupted)
        assertEquals(1, focusReleases)
    }
}
