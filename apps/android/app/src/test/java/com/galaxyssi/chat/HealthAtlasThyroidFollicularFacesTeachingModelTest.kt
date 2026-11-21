package com.galaxyssi.chat

import kotlin.math.PI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasThyroidFollicularFacesTeachingModelTest {
    private val spec = HealthAtlasThyroidFollicularFacesTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val tolerance = 1e-12

    @Test fun defaultsCompareOneWedgeInArbitraryLengthUnits() {
        assertEquals(setOf("cell-thyroid-follicular-cell"), spec.entryIds)
        assertEquals("thyroid-follicular-faces-wedges", controls[spec.axis].key)
        assertEquals(listOf(8..16, 20..60), controls.map { it.range })
        assertEquals(listOf("", "u"), spec.inputs.map { it.unit })
        assertEquals("u", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(12.0, 4.0), defaults)
        assertEquals(2.0 * PI / 3.0, spec.evaluate(defaults), tolerance)
        assertEquals(PI, spec.companionValue(defaults), tolerance)
    }

    @Test fun wedgeArcsReassembleBothRingsAcrossTheSliderRanges() {
        assertEquals(0.0, spec.minimum, tolerance)
        assertEquals(1.5 * PI, spec.maximum, tolerance)
        assertEquals(spec.maximum, spec.evaluate(listOf(8.0, 6.0)), tolerance)
        assertEquals(PI / 4.0, spec.evaluate(listOf(16.0, 2.0)), tolerance)

        val (wedgeControl, radiusControl) = controls
        for (radiusStep in radiusControl.range) {
            val radius = radiusStep / radiusControl.scale
            var previousInner = Double.POSITIVE_INFINITY
            for (wedges in wedgeControl.range) {
                val values = listOf(wedges.toDouble(), radius)
                val inner = spec.evaluate(values)
                val outer = spec.companionValue(values)
                assertTrue(inner in spec.minimum..spec.maximum && inner < previousInner)
                assertTrue(outer > inner)
                assertEquals(2.0 * PI * radius, inner * wedges, tolerance)
                assertEquals(2.0 * PI * (radius + 2.0), outer * wedges, tolerance)
                previousInner = inner
            }
        }
    }

    @Test fun chartRoundsTheWedgeCountButUsesTheScaledRadius() {
        assertEquals(spec.evaluate(listOf(11.0, 4.2)), spec.evaluate(listOf(11.49, 4.2)), tolerance)
        assertEquals(spec.evaluate(listOf(12.0, 4.2)), spec.evaluate(listOf(11.5, 4.2)), tolerance)
        assertTrue(spec.evaluate(listOf(12.0, 4.2)) > spec.evaluate(listOf(12.0, 4.1)))
    }
}
