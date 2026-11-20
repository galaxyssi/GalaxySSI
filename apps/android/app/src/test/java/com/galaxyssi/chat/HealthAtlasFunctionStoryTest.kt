package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasFunctionStoryTest {
    @Test fun onlySupportedTargetsShareTheGlucoseUptakeStory() {
        assertTrue(HealthAtlasFunctionStory.supports("tissue-skeletal-muscle"))
        assertTrue(HealthAtlasFunctionStory.supports("cell-adipocyte"))
        assertFalse(HealthAtlasFunctionStory.supports("cell-pancreatic-beta-cell"))
        assertFalse(HealthAtlasFunctionStory.supports("liver"))
        assertFalse(HealthAtlasFunctionStory.supports(null))
    }

    @Test fun allFiveChaptersScrubToTheirOwnBoundariesAndRejectInvalidState() {
        val story = HealthAtlasFunctionStory
        assertEquals(5, story.chapters.size)
        assertEquals(5, story.chapters.map { it.second }.toSet().size)
        for (i in story.chapters.indices) {
            val start = story.startOf(i)
            assertEquals(i, story.chapter(start))
            assertEquals(0f, story.fraction(start), .00001f)
            assertEquals(.5f, story.fraction(start + .1f), .00001f)
        }
        assertEquals(4, story.chapter(1f))
        assertEquals(1f, story.fraction(1f), 0f)
        assertEquals(0f, story.safePhase(Float.NaN), 0f)
        assertEquals(0f, story.safePhase(Float.POSITIVE_INFINITY), 0f)
        assertEquals(0f, story.startOf(-1), 0f)
        assertEquals(.8f, story.startOf(5), 0f)
    }
}
