package com.signalasi.chat.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ConnectingStartupViewTest {
    @Test
    fun stableAndGlitchFramesKeepTheSameWidth() {
        val frames = (0 until 72).map(ConnectingFrameSequence::frameAt)

        assertTrue(frames.any { it.characters != "CONNECTING" })
        assertTrue(frames.any { it.cursorVisible })
        assertTrue(frames.all { it.characters.length == "CONNECTING".length })
    }

    @Test
    fun reducedMotionUsesAStaticLabel() {
        val frame = ConnectingFrameSequence.frameAt(19, reduceMotion = true)

        assertEquals("CONNECTING", frame.characters)
        assertFalse(frame.cursorVisible)
    }
}
