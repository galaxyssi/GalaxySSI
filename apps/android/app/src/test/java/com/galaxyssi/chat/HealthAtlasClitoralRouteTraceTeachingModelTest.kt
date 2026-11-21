package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasClitoralRouteTraceTeachingModelTest {
    private val spec = HealthAtlasClitoralRouteTraceTeachingModel.spec
    private val input = spec.inputs.single()
    private val control = input.control
    private val tolerance = 1e-12

    @Test fun defaultMarksOneOfFourDiagramLinks() {
        val defaults = listOf(control.initial / control.scale)
        assertEquals(setOf("clitoris"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(0, input.digits)
        assertEquals("%", spec.unit)
        assertEquals(listOf(1.0), defaults)
        assertEquals(25.0, spec.evaluate(defaults), tolerance)
        assertEquals(3.0, spec.companionValue(defaults), tolerance)
    }

    @Test fun linkStepsCoverTheWholeRouteWithoutChangingItsLinkCount() {
        assertEquals(0..4, control.range)
        assertEquals(0.0, spec.minimum, tolerance)
        assertEquals(100.0, spec.maximum, tolerance)
        assertEquals(spec.minimum, spec.evaluate(listOf(0.0)), tolerance)
        assertEquals(spec.maximum, spec.evaluate(listOf(4.0)), tolerance)

        for (step in control.range) {
            val traced = step / control.scale
            val values = listOf(traced)
            val percent = spec.evaluate(values)
            val remaining = spec.companionValue(values)
            assertTrue(percent in spec.minimum..spec.maximum && remaining in 0.0..4.0)
            assertEquals(traced, percent * 4.0 / 100.0, tolerance)
            assertEquals(4.0, traced + remaining, tolerance)
        }
    }

    @Test fun fractionalPlotSamplesRoundToWholeLinks() {
        for ((sample, rounded) in listOf(0.49 to 0.0, 0.5 to 1.0, 1.5 to 2.0, 2.5 to 3.0, 3.5 to 4.0)) {
            assertEquals(spec.evaluate(listOf(rounded)), spec.evaluate(listOf(sample)), tolerance)
            assertEquals(spec.companionValue(listOf(rounded)), spec.companionValue(listOf(sample)), tolerance)
        }
    }
}
