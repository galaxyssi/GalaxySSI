package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasIntestinalStemRenewalTeachingModelTest {
    private val spec = HealthAtlasIntestinalStemRenewalTeachingModel.spec
    private val controls = spec.inputs.map { it.control }

    @Test fun defaultsFillSixSlotsWithDescendantsOverTwoDiagramSteps() {
        assertEquals(setOf("cell-intestinal-stem-cell"), spec.entryIds)
        assertEquals("intestinal-stem-renewal-steps", controls[spec.axis].key)
        assertEquals(listOf(0..6, 1..4), controls.map { it.range })
        assertEquals(listOf(0, 0), spec.inputs.map { it.digits })
        assertEquals(0, spec.digits)
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(12.0, spec.maximum, 0.0)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(2.0, 3.0), defaults)
        assertEquals(6.0, spec.evaluate(defaults), 0.0)
        assertEquals(6.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun descendantsFillTheFixedTrackWithoutCountingStemIconsInItsSlots() {
        val (steps, baseIcons) = controls
        for (base in baseIcons.range) {
            var previousFilled = 0.0
            for (step in steps.range) {
                val values = listOf(step / steps.scale, base / baseIcons.scale)
                val filled = spec.evaluate(values)
                val empty = spec.companionValue(values)
                assertEquals(minOf(12, step * base).toDouble(), filled, 0.0)
                assertTrue(filled in spec.minimum..spec.maximum && filled >= previousFilled)
                assertTrue(empty in 0.0..12.0)
                assertEquals(12.0, filled + empty, 0.0)
                previousFilled = filled
            }
        }

        assertEquals(spec.minimum, spec.evaluate(listOf(0.0, 4.0)), 0.0)
        assertEquals(spec.maximum, spec.evaluate(listOf(3.0, 4.0)), 0.0)
        assertEquals(spec.maximum, spec.evaluate(listOf(6.0, 4.0)), 0.0)
    }

    @Test fun chartSamplesAdvanceByWholeDiagramSteps() {
        assertEquals(3.0, spec.evaluate(listOf(1.49, 3.0)), 0.0)
        assertEquals(6.0, spec.evaluate(listOf(1.5, 3.0)), 0.0)
        assertEquals(9.0, spec.evaluate(listOf(3.49, 3.0)), 0.0)
        assertEquals(12.0, spec.evaluate(listOf(3.5, 3.0)), 0.0)
    }
}
