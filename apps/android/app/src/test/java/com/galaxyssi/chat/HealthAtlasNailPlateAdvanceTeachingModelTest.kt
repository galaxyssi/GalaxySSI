package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasNailPlateAdvanceTeachingModelTest {
    private val spec = HealthAtlasNailPlateAdvanceTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val tolerance = 1e-12

    @Test fun defaultsShowAdvanceAndMarkPositionForNailsOnly() {
        val defaults = controls.map { it.initial / it.scale }

        assertEquals(setOf("nails"), spec.entryIds)
        assertEquals("nail-plate-advance-steps", controls[spec.axis].key)
        assertEquals(listOf(0..12, 0..15), controls.map { it.range })
        assertEquals(listOf("", "u"), spec.inputs.map { it.unit })
        assertEquals("u", spec.unit)
        assertEquals(listOf(4.0, 0.8), defaults)
        assertEquals(3.2, spec.evaluate(defaults), tolerance)
        assertEquals(7.2, spec.companionValue(defaults), tolerance)
    }

    @Test fun zeroAdvanceAndAllAxisExtremesStayOnTheDrawingScale() {
        assertEquals(0.0, spec.minimum, tolerance)
        assertEquals(18.0, spec.maximum, tolerance)
        for (inputs in listOf(listOf(0.0, 0.0), listOf(0.0, 1.5), listOf(12.0, 0.0))) {
            assertEquals(spec.minimum, spec.evaluate(inputs), tolerance)
            assertEquals(4.0, spec.companionValue(inputs), tolerance)
        }
        val maximumInputs = listOf(12.0, 1.5)
        assertEquals(spec.maximum, spec.evaluate(maximumInputs), tolerance)
        assertEquals(22.0, spec.companionValue(maximumInputs), tolerance)
    }

    @Test fun chartSamplesMoveTheMarkWithThePlateAcrossTheBedEnd() {
        val (stepControl, additionControl) = controls
        for (additionStep in additionControl.range) {
            val addition = additionStep / additionControl.scale
            var previousAdvance = 0.0
            for (halfStep in 0..(2 * stepControl.range.last)) {
                val inputs = listOf(halfStep / 2.0, addition)
                val advance = spec.evaluate(inputs)
                assertTrue(advance in spec.minimum..spec.maximum)
                assertTrue(advance >= previousAdvance)
                if (halfStep > 0) {
                    assertEquals(addition / 2.0, advance - previousAdvance, tolerance)
                }
                assertEquals(4.0 + advance, spec.companionValue(inputs), tolerance)
                previousAdvance = advance
            }
        }

        assertEquals(9.5, spec.companionValue(listOf(5.5, 1.0)), tolerance)
        assertEquals(10.0, spec.companionValue(listOf(6.0, 1.0)), tolerance)
        assertEquals(10.5, spec.companionValue(listOf(6.5, 1.0)), tolerance)
    }
}
