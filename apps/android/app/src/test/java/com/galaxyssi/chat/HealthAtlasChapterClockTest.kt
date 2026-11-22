package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasChapterClockTest {
    @Test fun everyChapterGetsFiveSecondsRegardlessOfLessonLength() {
        for (count in 1..10) {
            val clock = HealthAtlasChapterClock(count, 0f)
            clock.resume(500)
            for (chapter in 1 until count) {
                val boundary = 500L + chapter * 5_000L
                assertEquals(chapter - 1, (clock.sample(boundary - 1) * count).toInt())
                assertEquals(chapter, (clock.sample(boundary) * count).toInt())
                assertEquals(5_000L, clock.nextStepIn(boundary))
            }
            assertEquals(1f, clock.sample(500L + count * 5_000L), 0f)
            assertFalse(clock.playing)
        }
    }

    @Test fun pauseResumesAtPreciselyTheRemainingTime() {
        val clock = HealthAtlasChapterClock(4, 0f)
        clock.resume(100)
        clock.pause(2_100)
        assertEquals(.1f, clock.sample(10_000), 0f)
        clock.resume(10_000)
        assertEquals(3_000L, clock.nextStepIn(10_000))
        assertTrue(clock.sample(12_999) < .25f)
        assertEquals(.25f, clock.sample(13_000), 0f)
    }

    @Test fun seekPausesAndReplayRestartsOnlyAfterTheEnd() {
        val clock = HealthAtlasChapterClock(5, .4f)
        clock.resume(1_000)
        assertEquals(.5f, clock.sample(3_500), 0f)
        clock.seek(.8f)
        assertFalse(clock.playing)
        assertEquals(.8f, clock.sample(123_456), 0f)
        clock.resume(124_000)
        assertEquals(1f, clock.sample(129_000), 0f)
        clock.resume(132_000)
        assertEquals(0f, clock.sample(132_000), 0f)
    }
}
