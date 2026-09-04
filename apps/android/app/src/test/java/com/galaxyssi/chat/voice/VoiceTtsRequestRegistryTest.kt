package com.galaxyssi.chat.voice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceTtsRequestRegistryTest {
    @Test
    fun staleCompletionCannotFinishReplacementRequest() {
        val registry = VoiceTtsRequestRegistry()
        var completedTrace = ""
        registry.begin(VoiceTtsRequest("utterance-old", "trace-old") { completedTrace = "trace-old" })
        registry.begin(VoiceTtsRequest("utterance-new", "trace-new") { completedTrace = "trace-new" })

        assertNull(registry.finish("utterance-old"))
        assertEquals("", completedTrace)

        val current = registry.finish("utterance-new")
        current?.onFinished?.invoke()
        assertEquals("trace-new", current?.traceId)
        assertEquals("trace-new", completedTrace)
    }

    @Test
    fun blankOrUnknownCompletionCannotClaimActiveRequest() {
        val registry = VoiceTtsRequestRegistry()
        registry.begin(VoiceTtsRequest("utterance-1", "trace-1") {})

        assertNull(registry.finish(null))
        assertNull(registry.finish(""))
        assertNull(registry.finish("utterance-other"))
        assertEquals("trace-1", registry.finish("utterance-1")?.traceId)
    }

    @Test
    fun discardOnlyRemovesMatchingRequest() {
        val registry = VoiceTtsRequestRegistry()
        registry.begin(VoiceTtsRequest("utterance-1", "trace-1") {})

        assertFalse(registry.discard("utterance-other"))
        assertTrue(registry.discard("utterance-1"))
        assertNull(registry.finish("utterance-1"))
    }
}
