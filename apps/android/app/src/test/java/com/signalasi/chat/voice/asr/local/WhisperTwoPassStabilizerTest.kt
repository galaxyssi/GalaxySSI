package com.signalasi.chat.voice.asr.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WhisperTwoPassStabilizerTest {
    @Test
    fun matchingPrefixBecomesStableAfterTwoRounds() {
        val stabilizer = WhisperTwoPassStabilizer()

        val first = stabilizer.update("today we go")
        assertEquals("", first.stableText)
        assertEquals("today we go", first.unstableText)

        val second = stabilizer.update("today we go home")
        assertEquals("today we", second.stableText)
        assertEquals("go home", second.unstableText)

        val final = stabilizer.update("today we go home now", final = true)
        assertTrue(final.final)
        assertEquals("today we go home now", final.stableText)
        assertEquals("", final.unstableText)
    }

    @Test
    fun rollingWindowOverlapPreservesCommittedPrefix() {
        val stabilizer = WhisperTwoPassStabilizer()
        stabilizer.update("alpha beta gamma")
        val stable = stabilizer.update("alpha beta gamma delta")
        assertEquals("alpha beta", stable.stableText)

        val sliding = stabilizer.update("beta gamma delta epsilon")
        assertTrue(sliding.fullText.startsWith("alpha beta"))
        assertFalse(sliding.final)
    }

    @Test
    fun resetRemovesPriorSessionState() {
        val stabilizer = WhisperTwoPassStabilizer()
        stabilizer.update("first phrase")
        stabilizer.update("first phrase extended")
        stabilizer.reset()

        val next = stabilizer.update("new session")
        assertEquals("", next.stableText)
        assertEquals("new session", next.unstableText)
    }
}
