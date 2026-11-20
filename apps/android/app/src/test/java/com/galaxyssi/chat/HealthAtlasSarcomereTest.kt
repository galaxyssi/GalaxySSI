package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasSarcomereTest {
    @Test fun shrinkingZDiscDistanceKeepsFilamentsConstantAndIncreasesOverlap() {
        val stages = (0..3).map(::HealthAtlasSarcomere)
        assertEquals(listOf(100, 100, 72, 100), stages.map { it.relativeLengthPercent })
        assertEquals(setOf(86), stages.map { it.thinLength }.toSet())
        assertEquals(setOf(136), stages.map { it.thickLength }.toSet())
        assertTrue(stages[2].overlap > stages[0].overlap)
        assertEquals(stages[0].overlap, stages[3].overlap)
        stages.forEach {
            assertEquals(it.zDistance, it.rightZ - it.leftZ)
            assertEquals(it.thickLength, it.rightThick - it.leftThick)
            assertEquals(360, it.rightZ + it.leftZ)
        }
        assertTrue(runCatching { HealthAtlasSarcomere(4) }.isFailure)
    }
}
