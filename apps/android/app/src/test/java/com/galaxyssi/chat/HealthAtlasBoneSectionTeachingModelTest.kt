package com.galaxyssi.chat

import kotlin.math.PI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasBoneSectionTeachingModelTest {
    private val spec = HealthAtlasBoneSectionTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val tolerance = 1e-12

    @Test fun defaultsUseForceAxisAndMetricUnits() {
        val defaults = controls.map { it.initial / it.scale }

        assertEquals(setOf("tissue-compact-bone", "clavicle", "hand-bones", "foot-bones"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("N", "mm"), spec.inputs.map { it.unit })
        assertEquals("MPa", spec.unit)
        assertEquals(listOf(60.0, 2.0), defaults)
        assertEquals(16.0 * PI, spec.companionValue(defaults), tolerance)
        assertEquals(60.0 / (16.0 * PI), spec.evaluate(defaults), tolerance)
    }

    @Test fun thickerWallIncreasesAreaAndLowersStressAtFixedForce() {
        val thin = listOf(60.0, 1.5)
        val thick = listOf(60.0, 2.5)

        assertTrue(spec.companionValue(thick) > spec.companionValue(thin))
        assertTrue(spec.evaluate(thick) < spec.evaluate(thin))
        assertEquals(60.0, spec.evaluate(thick) * spec.companionValue(thick), tolerance)
    }

    @Test fun allSliderCombinationsFitChartAndForceIncreasesStressAtEachThickness() {
        val (force, thickness) = controls
        assertEquals(0.0..120.0, force.range.first / force.scale..force.range.last / force.scale)
        assertEquals(1.0..3.0, thickness.range.first / thickness.scale..thickness.range.last / thickness.scale)
        assertEquals(0.0, spec.minimum, tolerance)
        assertEquals(9.0 * PI, spec.companionValue(listOf(0.0, 1.0)), tolerance)
        assertEquals(21.0 * PI, spec.companionValue(listOf(0.0, 3.0)), tolerance)
        assertEquals(120.0 / (9.0 * PI), spec.evaluate(listOf(120.0, 1.0)), tolerance)

        for (thicknessStep in thickness.range) {
            val wallMm = thicknessStep / thickness.scale
            val area = spec.companionValue(listOf(0.0, wallMm))
            assertTrue(area.isFinite() && area > 0.0)
            var previous = 0.0
            for (forceStep in force.range) {
                val load = forceStep / force.scale
                val stress = spec.evaluate(listOf(load, wallMm))
                assertTrue(stress in spec.minimum..spec.maximum)
                if (load == 0.0) assertEquals(0.0, stress, tolerance) else assertTrue(stress > previous)
                assertEquals(load, stress * area, tolerance)
                previous = stress
            }
        }
    }
}
