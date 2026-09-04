package com.galaxyssi.chat.voice.asr.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WhisperTextStabilizerTest {
    @Test
    fun repeatedWindowsPromoteStablePrefixWithoutDuplicatingOverlap() {
        val stabilizer = WhisperTextStabilizer(stabilityLagMs = 300L)

        val first = stabilizer.accept(window("hello world", 0L, 2_000L, endMs = 1_400L))
        val second = stabilizer.accept(window("hello world again", 0L, 3_000L, endMs = 2_100L))
        val third = stabilizer.accept(window("world again today", 1_000L, 4_000L, endMs = 3_100L))

        assertEquals("", first.stableText)
        assertTrue(second.stableText.startsWith("hello world"))
        assertEquals(1, Regex("world").findAll(third.displayText).count())
        assertTrue(third.stableText.startsWith(second.stableText))
    }

    @Test
    fun finalUsesAuthoritativeFullDecodeAndClearsUnstableSuffix() {
        val stabilizer = WhisperTextStabilizer()
        stabilizer.accept(window("\u4f60\u597d\u4e16", 0L, 1_500L, endMs = 700L))
        stabilizer.accept(window("\u4f60\u597d\u4e16\u754c", 0L, 2_000L, endMs = 1_200L))

        val final = stabilizer.accept(
            window("\u4f60\u597d\u4e16\u754c\u3002", 0L, 2_500L, endMs = 2_500L, final = true)
        )

        assertTrue(final.final)
        assertEquals("\u4f60\u597d\u4e16\u754c\u3002", final.stableText)
        assertEquals("", final.unstableText)
    }

    @Test
    fun lowConfidenceOrNoSpeechSegmentsRemainUnstable() {
        val stabilizer = WhisperTextStabilizer()
        val weak = DecodedWhisperWindow(
            requestId = "weak",
            windowStartMs = 0L,
            windowEndMs = 2_000L,
            text = "maybe",
            segments = listOf(TimedTranscriptSegment(0L, 1_000L, "maybe", -3.0f, 0.9f)),
            realTimeFactor = 0.2,
            final = false
        )

        stabilizer.accept(weak)
        val repeated = stabilizer.accept(weak.copy(requestId = "weak-2"))

        assertEquals("", repeated.stableText)
        assertFalse(repeated.unstableText.isBlank())
    }

    private fun window(
        text: String,
        startMs: Long,
        windowEndMs: Long,
        endMs: Long,
        final: Boolean = false
    ) = DecodedWhisperWindow(
        requestId = text,
        windowStartMs = startMs,
        windowEndMs = windowEndMs,
        text = text,
        segments = listOf(TimedTranscriptSegment(startMs, endMs, text, -0.2f, 0.05f)),
        realTimeFactor = 0.4,
        final = final
    )
}
