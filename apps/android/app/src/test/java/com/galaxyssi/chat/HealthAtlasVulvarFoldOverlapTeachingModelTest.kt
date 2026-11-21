package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasVulvarFoldOverlapTeachingModelTest {
    private val spec = HealthAtlasVulvarFoldOverlapTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-9

    @Test fun defaultsPlotAngleAgainstInnerFlapCoverage() {
        assertEquals(setOf("vulva", "labia-majora", "labia-minora"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("vulvar-fold-overlap-angle", "vulvar-fold-overlap-length"), controls.map { it.key })
        assertEquals(listOf("\u00b0", ""), spec.inputs.map { it.unit })
        assertEquals("%", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(60.0, 0.75), defaults)
        assertEquals(25.0, spec.evaluate(defaults), epsilon)
        assertEquals(37.5, spec.companionValue(defaults), epsilon)
    }

    @Test fun reachAtEitherEndOfTheInnerFlapMarksZeroOrFullOverlap() {
        assertEquals(listOf(0..90, 25..100), controls.map { it.range })
        assertEquals(0.0, spec.minimum, epsilon)
        assertEquals(100.0, spec.maximum, epsilon)

        assertEquals(0.0, spec.evaluate(listOf(0.0, 0.25)), epsilon)
        assertEquals(50.0, spec.evaluate(listOf(0.0, 0.50)), epsilon)
        assertEquals(100.0, spec.evaluate(listOf(0.0, 0.75)), epsilon)
        assertEquals(100.0, spec.evaluate(listOf(0.0, 1.0)), epsilon)
        assertEquals(100.0, spec.companionValue(listOf(0.0, 1.0)), epsilon)
        assertEquals(0.0, spec.evaluate(listOf(90.0, 1.0)), epsilon)
        assertEquals(0.0, spec.companionValue(listOf(90.0, 1.0)), epsilon)
    }

    @Test fun everySliderPairStaysInBoundsAndPreservesMonotonicDirection() {
        val (angle, length) = controls
        for (lengthStep in length.range) {
            val flapLength = lengthStep / length.scale
            var previousCoverage = spec.maximum
            for (angleStep in angle.range) {
                val degrees = angleStep / angle.scale
                val values = listOf(degrees, flapLength)
                val coverage = spec.evaluate(values)
                assertTrue(coverage in spec.minimum..spec.maximum)
                assertTrue(spec.companionValue(values) in 0.0..100.0)
                assertTrue("Coverage rose with angle at $values", coverage <= previousCoverage)
                if (lengthStep < length.range.last) {
                    val longerFlap = listOf(degrees, (lengthStep + 1) / length.scale)
                    assertTrue("Coverage fell with length at $values", spec.evaluate(longerFlap) >= coverage)
                }
                previousCoverage = coverage
            }
        }
    }
}
