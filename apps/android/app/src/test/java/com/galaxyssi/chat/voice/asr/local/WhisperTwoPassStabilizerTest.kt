package com.galaxyssi.chat.voice.asr.local

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

    @Test
    fun finalCollapsesLongRepeatedPrefixBackedByPartialEvidence() {
        val stabilizer = WhisperTwoPassStabilizer()
        val prefix = "\u8bf7\u67e5\u4e00\u4e0b GitHub \u7684"
        stabilizer.update(prefix)
        stabilizer.update("$prefix GalaxySSI")

        val final = stabilizer.update(
            "$prefix $prefix GalaxySSI \u9879\u76ee\u662f\u4ec0\u4e48",
            final = true
        )

        assertEquals("$prefix GalaxySSI \u9879\u76ee\u662f\u4ec0\u4e48", final.fullText)
    }

    @Test
    fun finalPreservesShortIntentionalRepetition() {
        val stabilizer = WhisperTwoPassStabilizer()
        stabilizer.update("very")
        stabilizer.update("very important")

        val final = stabilizer.update("very very important", final = true)

        assertEquals("very very important", final.fullText)
    }

    @Test
    fun finalPreservesLongRepetitionWithoutPartialEvidence() {
        val stabilizer = WhisperTwoPassStabilizer()
        val phrase = "please verify this"

        val final = stabilizer.update("$phrase $phrase", final = true)

        assertEquals("$phrase $phrase", final.fullText)
    }
}
