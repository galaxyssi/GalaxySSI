package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasExternalEarResonanceTeachingModelTest {
    private val spec = HealthAtlasExternalEarResonanceTeachingModel.spec
    private val length = spec.inputs[0].control
    private val speed = spec.inputs[1].control

    private fun at(lengthStep: Int, speedStep: Int) = listOf(lengthStep / length.scale, speedStep / speed.scale)

    @Test fun defaultClassroomTubeReturnsFundamentalHertzAndWavelengthCentimeters() {
        assertEquals(setOf("external-ear"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("cm", "m/s"), spec.inputs.map { it.unit })
        assertEquals("Hz", spec.unit)

        val defaults = at(length.initial, speed.initial)
        assertEquals(listOf(20.0, 343.0), defaults)
        assertEquals(428.75, spec.evaluate(defaults), 1e-9)
        assertEquals(80.0, spec.companionValue(defaults), 1e-9)
    }

    @Test fun extremeInputsGiveExpectedFundamentalsAndWavelengths() {
        assertEquals(10..50, length.range)
        assertEquals(330..360, speed.range)
        val longSlow = at(length.range.last, speed.range.first)
        val shortFast = at(length.range.first, speed.range.last)
        assertEquals(165.0, spec.evaluate(longSlow), 1e-9)
        assertEquals(900.0, spec.evaluate(shortFast), 1e-9)
        assertEquals(200.0, spec.companionValue(longSlow), 1e-9)
        assertEquals(40.0, spec.companionValue(shortFast), 1e-9)
    }

    @Test fun allSliderCombinationsFitTheChartAndFollowLengthAndSpeed() {
        for (speedStep in speed.range) {
            var previousFrequency = Double.POSITIVE_INFINITY
            for (lengthStep in length.range) {
                val values = at(lengthStep, speedStep)
                val frequency = spec.evaluate(values)
                val wavelengthCm = spec.companionValue(values)
                assertTrue(frequency in spec.minimum..spec.maximum && frequency < previousFrequency)
                assertEquals(4.0 * values[0], wavelengthCm, 1e-9)
                assertEquals(values[1], frequency * (wavelengthCm / 100.0), 1e-9)
                if (speedStep > speed.range.first) {
                    val slower = at(lengthStep, speedStep - 1)
                    assertTrue(frequency > spec.evaluate(slower))
                }
                previousFrequency = frequency
            }
        }
    }
}
