package com.galaxyssi.chat

import kotlin.math.PI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasSatelliteGlialSheathGapTeachingModelTest {
    private val spec = HealthAtlasSatelliteGlialSheathGapTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val tolerance = 1e-12

    @Test fun defaultsUseScaledDrawingUnitsAndPlotGapWidth() {
        val defaults = controls.map { it.initial / it.scale }
        assertEquals(setOf("cell-satellite-glial-cell"), spec.entryIds)
        assertEquals(1, spec.axis)
        assertEquals(listOf("u", "u"), spec.inputs.map { it.unit })
        assertEquals("u\u00B2", spec.unit)
        assertEquals(listOf(6.0, 0.3), defaults)
        assertEquals(3.69 * PI, spec.evaluate(defaults), tolerance)
        assertEquals(6.3, spec.companionValue(defaults), tolerance)
    }

    @Test fun coincidentOutlinesAndLargestGapStayWithinPlotBounds() {
        val noGap = listOf(4.0, 0.0)
        val largestGap = listOf(8.0, 0.5)
        assertEquals(0.0, spec.minimum, tolerance)
        assertEquals(26.0, spec.maximum, tolerance)
        assertEquals(0.0, spec.evaluate(noGap), tolerance)
        assertEquals(4.0, spec.companionValue(noGap), tolerance)
        assertEquals(8.25 * PI, spec.evaluate(largestGap), tolerance)
        assertEquals(8.5, spec.companionValue(largestGap), tolerance)
    }

    @Test fun gapAreaEqualsDifferenceOfTheTwoCirclesAndGrowsWithGapWidth() {
        val (radiusControl, widthControl) = controls
        for (radiusStep in radiusControl.range) {
            val radius = radiusStep / radiusControl.scale
            var previousArea = -1.0
            for (widthStep in widthControl.range) {
                val values = listOf(radius, widthStep / widthControl.scale)
                val innerSheathRadius = spec.companionValue(values)
                val gapArea = spec.evaluate(values)
                assertEquals(radius + values[1], innerSheathRadius, tolerance)
                assertEquals(PI * innerSheathRadius * innerSheathRadius, PI * radius * radius + gapArea, tolerance)
                assertTrue(gapArea in spec.minimum..spec.maximum && gapArea > previousArea)
                if (radiusStep > radiusControl.range.first && widthStep > 0) {
                    val smallerSoma = listOf((radiusStep - 1) / radiusControl.scale, values[1])
                    assertTrue(gapArea > spec.evaluate(smallerSoma))
                }
                previousArea = gapArea
            }
        }
    }
}
