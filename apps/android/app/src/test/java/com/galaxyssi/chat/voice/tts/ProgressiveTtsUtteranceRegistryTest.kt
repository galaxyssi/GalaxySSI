package com.galaxyssi.chat.voice.tts

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ProgressiveTtsUtteranceRegistryTest {
    @Test
    fun staleAndroidTtsCallbackCannotClaimReplacementUtterance() {
        val registry = ProgressiveTtsUtteranceRegistry()
        registry.begin(ProgressiveTtsUtteranceRequest("old", "session-old", {}, {}))
        registry.begin(ProgressiveTtsUtteranceRequest("new", "session-new", {}, {}))

        assertNull(registry.started("old"))
        assertNull(registry.finish("old"))
        assertEquals("session-new", registry.finish("new")?.sessionId)
    }

    @Test
    fun clearReturnsCurrentRequestOnce() {
        val registry = ProgressiveTtsUtteranceRegistry()
        registry.begin(ProgressiveTtsUtteranceRequest("utterance", "session", {}, {}))

        assertEquals("utterance", registry.clear()?.utteranceId)
        assertNull(registry.clear())
    }
}
