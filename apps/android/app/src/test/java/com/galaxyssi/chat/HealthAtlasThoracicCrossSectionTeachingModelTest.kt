package com.galaxyssi.chat

import kotlin.math.PI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasThoracicCrossSectionTeachingModelTest {
    private val spec = HealthAtlasThoracicCrossSectionTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val tolerance = 1e-10

    @Test fun defaultsUseFrontToBackAxisAndMetricUnits() {
        val defaults = controls.map { it.initial / it.scale }

        assertEquals(setOf("ribs", "sternum"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("cm", "cm"), spec.inputs.map { it.unit })
        assertEquals("cm\u00b2", spec.unit)
        assertEquals(listOf(18.0, 30.0), defaults)
        assertEquals(135.0 * PI, spec.evaluate(defaults), tolerance)
        assertEquals(0.6, spec.companionValue(defaults), tolerance)
    }

    @Test fun extremaAndEverySliderCombinationFitChart() {
        val (depth, width) = controls
        assertEquals(12.0..24.0, depth.range.first / depth.scale..depth.range.last / depth.scale)
        assertEquals(24.0..36.0, width.range.first / width.scale..width.range.last / width.scale)
        assertEquals(72.0 * PI, spec.evaluate(listOf(12.0, 24.0)), tolerance)
        assertEquals(216.0 * PI, spec.evaluate(listOf(24.0, 36.0)), tolerance)
        assertEquals(1.0 / 3.0, spec.companionValue(listOf(12.0, 36.0)), tolerance)
        assertEquals(1.0, spec.companionValue(listOf(24.0, 24.0)), tolerance)

        for (depthStep in depth.range) {
            for (widthStep in width.range) {
                val inputs = listOf(depthStep / depth.scale, widthStep / width.scale)
                assertTrue(spec.evaluate(inputs) in spec.minimum..spec.maximum)
                assertTrue(spec.companionValue(inputs) in (1.0 / 3.0)..1.0)
            }
        }
    }

    @Test fun increasingEitherDiameterIncreasesAreaButChangesShapeInOppositeDirections() {
        val baseline = listOf(12.0, 24.0)
        val deeper = listOf(18.0, 24.0)
        val wider = listOf(12.0, 36.0)

        assertTrue(spec.evaluate(deeper) > spec.evaluate(baseline))
        assertTrue(spec.evaluate(wider) > spec.evaluate(baseline))
        assertEquals(spec.evaluate(deeper), spec.evaluate(wider), tolerance)
        assertTrue(spec.companionValue(deeper) > spec.companionValue(baseline))
        assertTrue(spec.companionValue(wider) < spec.companionValue(baseline))
    }
}
