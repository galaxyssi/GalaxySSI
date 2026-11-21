package com.galaxyssi.chat

import kotlin.math.PI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasUrethralOpeningAreaTeachingModelTest {
    private val spec = HealthAtlasUrethralOpeningAreaTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val tolerance = 1e-12

    @Test fun defaultsUseFullDimensionsAndTheHeightPercentageAxis() {
        assertEquals(setOf("urethra"), spec.entryIds)
        assertEquals(1, spec.axis)
        assertEquals(listOf(20..80, 0..100), controls.map { it.range })
        assertEquals(listOf(10.0, 1.0), controls.map { it.scale })
        assertEquals(listOf("u", "%"), spec.inputs.map { it.unit })
        assertEquals("u\u00b2", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(6.0, 50.0), defaults)
        assertEquals(4.5 * PI, spec.evaluate(defaults), tolerance)
        assertEquals(3.0, spec.companionValue(defaults), tolerance)
    }

    @Test fun zeroHeightAndMaximumCircleReachPlotBounds() {
        val closed = listOf(2.0, 0.0)
        val largestCircle = listOf(8.0, 100.0)

        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(16.0 * PI, spec.maximum, tolerance)
        assertEquals(spec.minimum, spec.evaluate(closed), 0.0)
        assertEquals(0.0, spec.companionValue(closed), 0.0)
        assertEquals(spec.maximum, spec.evaluate(largestCircle), tolerance)
        assertEquals(8.0, spec.companionValue(largestCircle), tolerance)
    }

    @Test fun areaIncreasesWithHeightAndRemainsWithinReferenceCircle() {
        val (widthControl, heightControl) = controls
        for (widthStep in widthControl.range) {
            val width = widthStep / widthControl.scale
            val circleArea = PI * width * width / 4.0
            var previous = -1.0
            for (heightStep in heightControl.range) {
                val percent = heightStep / heightControl.scale
                val values = listOf(width, percent)
                val area = spec.evaluate(values)
                assertTrue(area > previous && area in spec.minimum..spec.maximum)
                assertEquals(percent / 100.0, area / circleArea, tolerance)
                assertEquals(width * percent / 100.0, spec.companionValue(values), tolerance)
                previous = area
            }
        }
    }

    @Test fun doublingWidthAtTheSameHeightPercentageQuadruplesArea() {
        val small = listOf(3.0, 37.5)
        val large = listOf(6.0, 37.5)
        assertEquals(4.0 * spec.evaluate(small), spec.evaluate(large), tolerance)
        assertEquals(2.0 * spec.companionValue(small), spec.companionValue(large), tolerance)
    }
}
