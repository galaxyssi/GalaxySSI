package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasSplenicSlitSortingTeachingModelTest {
    private val spec = HealthAtlasSplenicSlitSortingTeachingModel.spec
    private val input = spec.inputs.single()
    private val control = input.control

    @Test fun defaultSketchSlitPassesSixOfTwelveTokens() {
        assertEquals(setOf("spleen"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(0..16, control.range)
        assertEquals(2.0, control.scale, 0.0)
        assertEquals("u", input.unit)
        assertEquals(1, input.digits)
        assertEquals(0, spec.digits)

        val defaults = listOf(control.initial / control.scale)
        assertEquals(listOf(3.0), defaults)
        assertEquals(6.0, spec.evaluate(defaults), 0.0)
        assertEquals(6.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun exactFitsPassWithoutRoundingTheSketchWidth() {
        assertEquals(0.0, spec.evaluate(listOf(0.999)), 0.0)
        assertEquals(1.0, spec.evaluate(listOf(1.0)), 0.0)
        assertEquals(3.0, spec.evaluate(listOf(2.999)), 0.0)
        assertEquals(6.0, spec.evaluate(listOf(3.0)), 0.0)
        assertEquals(11.0, spec.evaluate(listOf(7.999)), 0.0)
        assertEquals(12.0, spec.evaluate(listOf(8.0)), 0.0)
    }

    @Test fun allSliderStepsAreBoundedAndConserveTheFixedTokenPool() {
        val expectedPasses = listOf(0, 0, 1, 1, 3, 3, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12)
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(12.0, spec.maximum, 0.0)

        var previous = spec.minimum
        for ((step, expected) in control.range.zip(expectedPasses)) {
            val values = listOf(step / control.scale)
            val passed = spec.evaluate(values)
            val left = spec.companionValue(values)
            assertEquals(expected.toDouble(), passed, 0.0)
            assertTrue(passed in previous..spec.maximum)
            assertTrue(left in spec.minimum..spec.maximum)
            assertEquals(12.0, passed + left, 0.0)
            previous = passed
        }
    }
}
