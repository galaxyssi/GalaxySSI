package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasVertebralSeriesTeachingModelTest {
    private val spec = HealthAtlasVertebralSeriesTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val defaults = controls.map { it.initial / it.scale }
    private val tolerance = 1e-12

    @Test fun defaultsGiveTotalPadShorteningAndRemainingThicknessInMillimeters() {
        assertEquals(listOf("", "mm"), spec.inputs.map { it.unit })
        assertEquals("mm", spec.unit)
        assertEquals(1, spec.axis)
        assertEquals(listOf(4.0, 0.25), defaults)
        assertEquals(1.0, spec.evaluate(defaults), tolerance)
        assertEquals(19.0, spec.companionValue(defaults), tolerance)
    }

    @Test fun allSliderStepsFitTheChartAndAccountForStartingPadThickness() {
        val (countControl, shorteningControl) = controls
        assertEquals(1..8, countControl.range)
        assertEquals(1.0, countControl.scale, tolerance)
        assertEquals(0..100, shorteningControl.range)
        assertEquals(100.0, shorteningControl.scale, tolerance)
        assertEquals(0.0, spec.minimum, tolerance)
        assertEquals(8.0, spec.maximum, tolerance)

        for (countStep in countControl.range) {
            val count = countStep / countControl.scale
            assertEquals(0.0, spec.evaluate(listOf(count, 0.0)), tolerance)
            for (step in shorteningControl.range) {
                val inputs = listOf(count, step / shorteningControl.scale)
                val shortening = spec.evaluate(inputs)
                val remaining = spec.companionValue(inputs)
                assertTrue(shortening in spec.minimum..spec.maximum)
                assertTrue(remaining > 0.0)
                assertEquals(5.0 * count, shortening + remaining, tolerance)
            }
        }
        assertEquals(spec.maximum, spec.evaluate(listOf(8.0, 1.0)), tolerance)
    }

    @Test fun perPadShorteningRaisesTheCurveAndLowersRemainingThickness() {
        val (countControl, axisControl) = controls
        for (countStep in countControl.range) {
            val count = countStep / countControl.scale
            for (step in axisControl.range.first until axisControl.range.last) {
                val left = listOf(count, step / axisControl.scale)
                val right = listOf(count, (step + 1) / axisControl.scale)
                assertTrue(spec.evaluate(right) > spec.evaluate(left))
                assertTrue(spec.companionValue(right) < spec.companionValue(left))
            }
        }
    }

    @Test fun morePadsProportionallyIncreaseShorteningAtAFixedPositiveSetting() {
        assertEquals(0.37, spec.evaluate(listOf(1.0, 0.37)), tolerance)
        assertEquals(2.59, spec.evaluate(listOf(7.0, 0.37)), tolerance)
    }

    @Test fun targetsOnlyTheVertebraeEntry() {
        assertEquals(setOf("vertebrae"), spec.entryIds)
    }
}
