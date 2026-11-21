package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasHormoneSignalTeachingModelTest {
    private val spec = HealthAtlasHormoneSignalTeachingModel.spec
    private val halfLife = spec.inputs[0].control
    private val elapsed = spec.inputs[1].control

    @Test fun targetsOnlyTheRequestedEntriesAndPlotsElapsedTime() {
        assertEquals(setOf("endocrine", "pituitary-gland", "cell-thyrotroph"), spec.entryIds)
        assertEquals(1, spec.axis)
        assertEquals("%", spec.unit)
    }

    @Test fun eachHalfLifeHalvesTheRemainingSignal() {
        assertPercentages(100.0, 0.0, listOf(2.0, 0.0))
        assertPercentages(50.0, 50.0, listOf(2.0, 2.0))
        assertPercentages(25.0, 75.0, listOf(2.0, 4.0))
        assertPercentages(12.5, 87.5, listOf(2.0, 6.0))
        assertPercentages(6.25, 93.75, listOf(2.0, 8.0))
        assertPercentages(70.71067811865476, 29.28932188134524, listOf(2.0, 1.0))
    }

    @Test fun defaultIsTwoHalfLivesAndTheFirstSliderChangesTheResult() {
        assertPercentages(25.0, 75.0, scaled(halfLife.initial, elapsed.initial))
        assertPercentages(6.25, 93.75, scaled(halfLife.range.first, elapsed.initial))
        assertPercentages(50.0, 50.0, scaled(halfLife.range.last, elapsed.initial))
    }

    @Test fun allSliderPairsFitTheChartAndRemovedComplementsRemaining() {
        for (rawHalfLife in halfLife.range) {
            for (rawElapsed in elapsed.range) {
                val values = scaled(rawHalfLife, rawElapsed)
                val remaining = spec.evaluate(values)
                val removed = spec.companionValue(values)
                assertTrue(remaining in spec.minimum..spec.maximum)
                assertTrue(removed in 0.0..100.0)
                assertEquals(100.0, remaining + removed, 1e-9)
                if (rawElapsed == elapsed.range.first) {
                    assertEquals(100.0, remaining, 1e-9)
                } else {
                    assertTrue(remaining < spec.evaluate(scaled(rawHalfLife, rawElapsed - 1)))
                    if (rawHalfLife > halfLife.range.first) {
                        assertTrue(remaining > spec.evaluate(scaled(rawHalfLife - 1, rawElapsed)))
                    }
                }
            }
        }
    }

    private fun scaled(rawHalfLife: Int, rawElapsed: Int) =
        listOf(rawHalfLife / halfLife.scale, rawElapsed / elapsed.scale)

    private fun assertPercentages(remaining: Double, removed: Double, values: List<Double>) {
        assertEquals(remaining, spec.evaluate(values), 1e-9)
        assertEquals(removed, spec.companionValue(values), 1e-9)
    }
}
