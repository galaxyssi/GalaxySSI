package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasGastricLiquidEmptyingTeachingModelTest {
    private val spec = HealthAtlasGastricLiquidEmptyingTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-10

    @Test fun defaultsRemoveTwentyPercentOfWhatRemainsForFourIntervals() {
        assertEquals(setOf("stomach"), spec.entryIds)
        assertEquals(listOf("gastric-liquid-removal", "gastric-liquid-intervals"), controls.map { it.key })
        assertEquals(listOf(5..40, 0..10), controls.map { it.range })
        assertEquals(1, spec.axis)
        assertEquals(listOf("%", ""), spec.inputs.map { it.unit })
        assertEquals("%", spec.unit)
        assertEquals(0.0, spec.minimum, epsilon)
        assertEquals(100.0, spec.maximum, epsilon)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(20.0, 4.0), defaults)
        assertEquals(40.96, spec.evaluate(defaults), epsilon)
        assertEquals(59.04, spec.companionValue(defaults), epsilon)
    }

    @Test fun endpointsHaveNoOutflowAtZeroAndPositiveRetentionAtMaximumRemoval() {
        val (removal, intervals) = controls
        for (removalStep in listOf(removal.range.first, removal.range.last)) {
            val initial = listOf(removalStep / removal.scale, intervals.range.first / intervals.scale)
            assertEquals(100.0, spec.evaluate(initial), epsilon)
            assertEquals(0.0, spec.companionValue(initial), epsilon)
        }

        val last = listOf(removal.range.last / removal.scale, intervals.range.last / intervals.scale)
        assertEquals(0.60466176, spec.evaluate(last), epsilon)
        assertEquals(99.39533824, spec.companionValue(last), epsilon)
    }

    @Test fun chartDecreasesBetweenStepsAndMatchesFractionalRemovalAtWholeIntervals() {
        assertEquals(80.0, spec.evaluate(listOf(36.0, 0.5)), epsilon)

        val (removal, intervals) = controls
        for (removalStep in removal.range) {
            val percent = removalStep / removal.scale
            var previous = Double.POSITIVE_INFINITY
            var expected = 100.0
            for (step in 0..120) {
                val count = (intervals.range.first + (intervals.range.last - intervals.range.first) * step / 120.0) /
                    intervals.scale
                val values = listOf(percent, count)
                val remaining = spec.evaluate(values)
                val emptied = spec.companionValue(values)
                assertTrue(remaining in spec.minimum..spec.maximum && remaining > 0.0)
                assertTrue(emptied in 0.0..100.0)
                assertTrue(remaining < previous)
                assertEquals(100.0, remaining + emptied, epsilon)
                if (count % 1.0 == 0.0) {
                    assertEquals(expected, remaining, epsilon)
                    expected -= expected * percent / 100.0
                }
                previous = remaining
            }
        }
    }

    @Test fun higherRemovalLeavesLessMarkerAtEveryPositiveSliderInterval() {
        val (removal, intervals) = controls
        for (intervalStep in (intervals.range.first + 1)..intervals.range.last) {
            val count = intervalStep / intervals.scale
            var previous = Double.POSITIVE_INFINITY
            for (removalStep in removal.range) {
                val remaining = spec.evaluate(listOf(removalStep / removal.scale, count))
                assertTrue(remaining < previous)
                previous = remaining
            }
        }
    }
}
