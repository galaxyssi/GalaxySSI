package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasPancreaticAcinarApicalBandTeachingModelTest {
    private val spec = HealthAtlasPancreaticAcinarApicalBandTeachingModel.spec
    private val control = spec.inputs.single().control
    private val tolerance = 1e-12

    @Test fun defaultBandOccupiesOnlyTheLuminalSideOfTheAcinarCellProfile() {
        assertEquals(setOf("cell-pancreatic-acinar-cell"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals("pancreatic-acinar-apical-band-depth", control.key)
        assertEquals("u", spec.inputs.single().unit)
        assertEquals("%", spec.unit)
        assertEquals(0..30, control.range)
        assertEquals(10.0, control.scale, 0.0)

        val defaults = listOf(control.initial / control.scale)
        assertEquals(listOf(2.0), defaults)
        assertEquals(16.0 / 3.0, spec.companionValue(defaults), tolerance)
        assertEquals(200.0 / 9.0, spec.evaluate(defaults), tolerance)
    }

    @Test fun deeperBandsGainMoreAreaPerStepAsTheProfileWidens() {
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(40.0, spec.maximum, 0.0)
        assertEquals(0.0, spec.evaluate(listOf(0.0)), 0.0)
        assertEquals(0.0, spec.companionValue(listOf(0.0)), 0.0)
        assertEquals(37.5, spec.evaluate(listOf(3.0)), tolerance)
        assertEquals(9.0, spec.companionValue(listOf(3.0)), tolerance)

        var previousArea = 0.0
        var previousGain = 0.0
        for (step in control.range.drop(1)) {
            val depth = step / control.scale
            val values = listOf(depth)
            val area = spec.companionValue(values)
            val share = spec.evaluate(values)
            val gain = area - previousArea
            assertTrue(share in spec.minimum..spec.maximum && gain > previousGain)
            assertEquals(2.0 * depth + depth * depth / 3.0, area, tolerance)
            assertEquals(area, 24.0 * share / 100.0, tolerance)
            previousArea = area
            previousGain = gain
        }
    }
}
