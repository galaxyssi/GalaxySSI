package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasKneeMomentTeachingModelTest {
    private val spec = HealthAtlasKneeMomentTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val tolerance = 1e-12

    @Test fun defaultsUseForceAxisAndMetricUnitsForBothEntries() {
        val defaults = controls.map { it.initial / it.scale }

        assertEquals(setOf("patella", "quadriceps-femoris"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("N", "cm"), spec.inputs.map { it.unit })
        assertEquals("N\u00b7m", spec.unit)
        assertEquals(listOf(10.0, 4.0), defaults)
        assertEquals(0.4, spec.evaluate(defaults), tolerance)
        assertEquals(0.04, spec.companionValue(defaults), tolerance)
    }

    @Test fun momentIsLinearInEachInputWhenTheOtherIsFixed() {
        val baseline = listOf(8.0, 3.0)
        val doubleForce = listOf(16.0, 3.0)
        val doubleArm = listOf(8.0, 6.0)

        assertEquals(0.24, spec.evaluate(baseline), tolerance)
        assertEquals(2.0 * spec.evaluate(baseline), spec.evaluate(doubleForce), tolerance)
        assertEquals(2.0 * spec.evaluate(baseline), spec.evaluate(doubleArm), tolerance)
        assertEquals(spec.companionValue(baseline), spec.companionValue(doubleForce), tolerance)
        assertEquals(0.06, spec.companionValue(doubleArm), tolerance)
    }

    @Test fun everySliderCombinationFitsChartIncludingBothZeroCases() {
        val (force, arm) = controls
        val bounds = spec.minimum..spec.maximum
        assertEquals(0.0, spec.minimum, tolerance)

        for (forceStep in force.range) for (armStep in arm.range) {
            val values = listOf(forceStep / force.scale, armStep / arm.scale)
            val moment = spec.evaluate(values)
            assertTrue("Moment for ${values} falls outside ${bounds}", moment in bounds)
            if (forceStep == 0 || armStep == 0) assertEquals(0.0, moment, tolerance)
        }
        val peak = listOf(force.range.last / force.scale, arm.range.last / arm.scale)
        assertEquals(1.2, spec.evaluate(peak), tolerance)
    }
}
