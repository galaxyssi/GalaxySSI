package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasRetinalConvergenceTeachingModelTest {
    private val spec = HealthAtlasRetinalConvergenceTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-12

    @Test fun defaultsPoolEightSamplesAtTwentyFivePercent() {
        assertEquals(setOf("cell-retinal-ganglion-cell", "cell-retinal-bipolar-cell"), spec.entryIds)
        assertEquals(1, spec.axis)
        assertEquals(listOf("", "%"), spec.inputs.map { it.unit })
        assertEquals("", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(8.0, 25.0), defaults)
        assertEquals(2.0, spec.evaluate(defaults), epsilon)
        assertEquals(6.0, spec.companionValue(defaults), epsilon)
    }

    @Test fun zeroAndFullIlluminationGiveExactCountsAtBothPoolExtremes() {
        val (pool, lit) = controls
        for (samples in listOf(pool.range.first / pool.scale, pool.range.last / pool.scale)) {
            val dark = listOf(samples, lit.range.first / lit.scale)
            val fullyLit = listOf(samples, lit.range.last / lit.scale)
            assertEquals(0.0, spec.evaluate(dark), 0.0)
            assertEquals(samples, spec.companionValue(dark), 0.0)
            assertEquals(samples, spec.evaluate(fullyLit), 0.0)
            assertEquals(0.0, spec.companionValue(fullyLit), 0.0)
        }
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(16.0, spec.maximum, 0.0)
    }

    @Test fun litChanceIncreasesPlottedCountAndTheTwoCountsSumToPoolSize() {
        val (pool, lit) = controls
        for (poolStep in pool.range) {
            val samples = poolStep / pool.scale
            var previous = -1.0
            for (litStep in lit.range) {
                val values = listOf(samples, litStep / lit.scale)
                val count = spec.evaluate(values)
                assertTrue(count > previous)
                assertTrue(count in spec.minimum..samples)
                assertEquals(samples, count + spec.companionValue(values), epsilon)
                previous = count
            }
        }
        // The chart also evaluates between slider steps.
        assertEquals(2.04, spec.evaluate(listOf(8.0, 25.5)), epsilon)
    }

    @Test fun poolingMoreSamplesIncreasesBothCountsAtFixedPartialIllumination() {
        val smaller = listOf(1.0, 25.0)
        val larger = listOf(16.0, 25.0)
        assertEquals(0.25, spec.evaluate(smaller), epsilon)
        assertEquals(16 * spec.evaluate(smaller), spec.evaluate(larger), epsilon)
        assertEquals(16 * spec.companionValue(smaller), spec.companionValue(larger), epsilon)
    }
}
