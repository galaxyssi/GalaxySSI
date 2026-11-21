package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasVisualAngleTeachingModelTest {
    private val spec = HealthAtlasVisualAngleTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-9

    @Test fun defaultsUseCentimetersAndReturnFullAndHalfAnglesInDegrees() {
        assertEquals(setOf("sensory", "retina"), spec.entryIds)
        assertEquals(listOf("visual-angle-width", "visual-angle-distance"), controls.map { it.key })
        assertEquals(1, spec.axis)
        assertEquals(listOf("cm", "cm"), spec.inputs.map { it.unit })
        assertEquals("\u00b0", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(10.0, 100.0), defaults)
        assertEquals(5.724810452, spec.evaluate(defaults), epsilon)
        assertEquals(2.862405226, spec.companionValue(defaults), epsilon)
    }

    @Test fun proportionalWidthAndDistanceGiveTheSameAngle() {
        val near = listOf(10.0, 50.0)
        val far = listOf(20.0, 100.0)
        assertEquals(11.421186275, spec.evaluate(near), epsilon)
        assertEquals(spec.evaluate(near), spec.evaluate(far), epsilon)
        assertEquals(spec.companionValue(near), spec.companionValue(far), epsilon)
    }

    @Test fun allSliderCombinationsFitTheChartAndFollowWidthAndDistance() {
        val (width, distance) = controls
        for (widthStep in width.range) {
            var previousAngle = Double.POSITIVE_INFINITY
            for (distanceStep in distance.range) {
                val values = listOf(widthStep / width.scale, distanceStep / distance.scale)
                val angle = spec.evaluate(values)
                assertTrue(angle in spec.minimum..spec.maximum)
                assertTrue(angle > 0.0 && angle < previousAngle)
                assertEquals(angle / 2.0, spec.companionValue(values), epsilon)
                if (widthStep > width.range.first) {
                    val narrower = listOf((widthStep - 1) / width.scale, values[1])
                    assertTrue(spec.evaluate(narrower) < angle)
                }
                previousAngle = angle
            }
        }
        val narrowFar = listOf(width.range.first / width.scale, distance.range.last / distance.scale)
        val wideNear = listOf(width.range.last / width.scale, distance.range.first / distance.scale)
        assertEquals(0.381970449, spec.evaluate(narrowFar), epsilon)
        assertEquals(22.619864948, spec.evaluate(wideNear), epsilon)
    }
}
