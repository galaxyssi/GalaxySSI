package com.galaxyssi.chat

import kotlin.math.PI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasCapillarySupportSurfaceTeachingModelTest {
    private val spec = HealthAtlasCapillarySupportSurfaceTeachingModel.spec
    private val radius = spec.inputs[0].control
    private val length = spec.inputs[1].control
    private val tolerance = 1e-9

    @Test fun plotsLateralAreaAgainstRadiusForTheTwoSupportCellEntries() {
        assertEquals(setOf("cell-pericyte", "cell-mesangial-cell"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("\u00b5m", "\u00b5m"), spec.inputs.map { it.unit })
        assertEquals("\u00b5m\u00b2", spec.unit)
    }

    @Test fun defaultsUseTheSideOfTheCylinderAndReportItsCircumference() {
        val defaults = spec.inputs.map { it.control.initial / it.control.scale }
        assertEquals(listOf(4.0, 30.0), defaults)
        assertEquals(240.0 * PI, spec.evaluate(defaults), tolerance)
        assertEquals(8.0 * PI, spec.companionValue(defaults), tolerance)
    }

    @Test fun allSliderPairsStayWithinThePlotBounds() {
        assertEquals(2..8, radius.range)
        assertEquals(10..60, length.range)
        assertEquals(1.0, radius.scale, 0.0)
        assertEquals(1.0, length.scale, 0.0)
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(960.0 * PI, spec.maximum, tolerance)
        assertEquals(40.0 * PI, spec.evaluate(listOf(2.0, 10.0)), tolerance)
        assertEquals(spec.maximum, spec.evaluate(listOf(8.0, 60.0)), tolerance)
        for (r in radius.range) {
            for (l in length.range) {
                val point = listOf(r / radius.scale, l / length.scale)
                assertTrue(spec.evaluate(point) in spec.minimum..spec.maximum)
                assertTrue(spec.companionValue(point) in (4.0 * PI)..(16.0 * PI))
            }
        }
    }

    @Test fun areaIncreasesAlongTheRadiusPlotAndWithIndependentLength() {
        val chartRadii = (0..40).map { radius.range.first + (radius.range.last - radius.range.first) * it / 40.0 }
        for (l in length.range) {
            val points = chartRadii.map { r -> listOf(r, l / length.scale) }
            for ((before, after) in points.zipWithNext()) {
                assertTrue(spec.evaluate(after) > spec.evaluate(before))
                assertTrue(spec.companionValue(after) > spec.companionValue(before))
            }
        }
        for (r in radius.range) {
            val points = length.range.map { l -> listOf(r / radius.scale, l / length.scale) }
            for ((before, after) in points.zipWithNext()) {
                assertTrue(spec.evaluate(after) > spec.evaluate(before))
                assertEquals(spec.companionValue(before), spec.companionValue(after), 0.0)
            }
        }
    }
}
