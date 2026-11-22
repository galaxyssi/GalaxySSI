package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasPeristalticTravelTeachingModelTest {
    private val spec = HealthAtlasPeristalticTravelTeachingModel.spec
    private val speed = spec.inputs[0].control
    private val time = spec.inputs[1].control

    @Test fun usesScaledSpeedAndTimeToReportDistanceAndSegmentProgress() {
        assertEquals(listOf("cm/s", "s"), spec.inputs.map { it.unit })
        assertEquals("cm", spec.unit)
        assertEquals(1, spec.axis)
        val values = listOf(1.2, 2.3)
        assertEquals(2.76, spec.evaluate(values), 1e-9)
        assertEquals(27.6, spec.companionValue(values), 1e-9)
    }

    @Test fun defaultsReachHalfTheDemoSegment() {
        val defaults = spec.inputs.map { it.control.initial / it.control.scale }
        assertEquals(listOf(2.5, 2.0), defaults)
        assertEquals(5.0, spec.evaluate(defaults), 1e-9)
        assertEquals(50.0, spec.companionValue(defaults), 1e-9)
    }

    @Test fun sliderLimitsFitTheChartAndTheDemoSegment() {
        assertEquals(10..40, speed.range)
        assertEquals(0..25, time.range)
        val start = scaled(speed.range.first, time.range.first)
        val end = scaled(speed.range.last, time.range.last)
        assertEquals(0.0, spec.minimum, 1e-9)
        assertEquals(10.0, spec.maximum, 1e-9)
        assertEquals(spec.minimum, spec.evaluate(start), 1e-9)
        assertEquals(spec.maximum, spec.evaluate(end), 1e-9)
        assertEquals(0.0, spec.companionValue(start), 1e-9)
        assertEquals(100.0, spec.companionValue(end), 1e-9)
    }

    @Test fun allSliderPairsStayInBoundsAndIncreaseWithSpeedAndTime() {
        for (rawSpeed in speed.range) {
            for (rawTime in time.range) {
                val values = scaled(rawSpeed, rawTime)
                val distance = spec.evaluate(values)
                val progress = spec.companionValue(values)
                assertTrue(distance in spec.minimum..spec.maximum)
                assertTrue(progress in 0.0..100.0)
                if (rawTime > time.range.first) {
                    val earlier = scaled(rawSpeed, rawTime - 1)
                    assertTrue(distance > spec.evaluate(earlier))
                    assertTrue(progress > spec.companionValue(earlier))
                    if (rawSpeed > speed.range.first) {
                        val slower = scaled(rawSpeed - 1, rawTime)
                        assertTrue(distance > spec.evaluate(slower))
                        assertTrue(progress > spec.companionValue(slower))
                    }
                } else {
                    assertEquals(0.0, distance, 1e-9)
                    assertEquals(0.0, progress, 1e-9)
                }
            }
        }
    }

    private fun scaled(rawSpeed: Int, rawTime: Int) = listOf(rawSpeed / speed.scale, rawTime / time.scale)
}
