package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasVaginalRugaSpanTeachingModelTest {
    private val spec = HealthAtlasVaginalRugaSpanTeachingModel.spec
    private val input = spec.inputs.single()
    private val control = input.control
    private val tolerance = 1e-12

    @Test fun defaultFoldHasEightUnitsOfSpanAndTwoMoreWhenFlat() {
        val height = control.initial / control.scale
        assertEquals(setOf("vagina"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals("u", input.unit)
        assertEquals("u", spec.unit)
        assertEquals(3.0, height, tolerance)
        assertEquals(8.0, spec.evaluate(listOf(height)), tolerance)
        assertEquals(2.0, spec.companionValue(listOf(height)), tolerance)
    }

    @Test fun spanShrinksAsThePeakRisesWithoutChangingTheSlopingSides() {
        assertEquals(0.0, control.range.first / control.scale, tolerance)
        assertEquals(4.0, control.range.last / control.scale, tolerance)
        assertEquals(6.0, spec.minimum, tolerance)
        assertEquals(10.0, spec.maximum, tolerance)
        assertEquals(spec.maximum, spec.evaluate(listOf(0.0)), tolerance)
        assertEquals(0.0, spec.companionValue(listOf(0.0)), tolerance)
        assertEquals(spec.minimum, spec.evaluate(listOf(4.0)), tolerance)
        assertEquals(4.0, spec.companionValue(listOf(4.0)), tolerance)

        var previousSpan = Double.POSITIVE_INFINITY
        for (step in control.range) {
            val height = step / control.scale
            val span = spec.evaluate(listOf(height))
            val halfSpan = span / 2.0
            val extra = spec.companionValue(listOf(height))
            assertTrue(span in spec.minimum..spec.maximum && span < previousSpan)
            assertTrue(extra in 0.0..4.0)
            assertEquals(25.0, halfSpan * halfSpan + height * height, tolerance)
            assertEquals(10.0, span + extra, tolerance)
            previousSpan = span
        }
    }
}
