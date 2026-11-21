package com.galaxyssi.chat

import kotlin.math.PI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasMerkelContactTeachingModelTest {
    private val spec = HealthAtlasMerkelContactTeachingModel.spec
    private val controls = spec.inputs.map { it.control }

    @Test fun targetsOnlyMerkelCellsAndUsesTouchForceAsTheHorizontalAxis() {
        assertEquals(setOf("cell-merkel-cell"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("merkel-contact-force", "merkel-contact-radius"), controls.map { it.key })
        assertEquals(listOf("mN", "mm"), spec.inputs.map { it.unit })
        assertEquals("kPa", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(40.0, 2.0), defaults)
        assertEquals(10.0 / PI, spec.evaluate(defaults), 1e-12)
        assertEquals(4.0 * PI, spec.companionValue(defaults), 1e-12)
    }

    @Test fun doublingTheRadiusQuadruplesAreaAndQuartersPressure() {
        val small = listOf(40.0, 2.0)
        val large = listOf(40.0, 4.0)
        assertEquals(4.0 * spec.companionValue(small), spec.companionValue(large), 1e-12)
        assertEquals(spec.evaluate(small) / 4.0, spec.evaluate(large), 1e-12)
    }

    @Test fun everySliderStepChangesPressureInTheExpectedDirectionWithinPlotBounds() {
        val (force, radius) = controls
        val lowestPressureInputs = listOf(force.range.first / force.scale, radius.range.last / radius.scale)
        val highestPressureInputs = listOf(force.range.last / force.scale, radius.range.first / radius.scale)
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(80.0 / PI, spec.maximum, 1e-12)
        assertEquals(10.0 / (16.0 * PI), spec.evaluate(lowestPressureInputs), 1e-12)
        assertEquals(spec.maximum, spec.evaluate(highestPressureInputs), 0.0)

        for (forceStep in force.range) {
            for (radiusStep in radius.range) {
                val forceMn = forceStep / force.scale
                val radiusMm = radiusStep / radius.scale
                val pressure = spec.evaluate(listOf(forceMn, radiusMm))
                assertTrue(pressure in spec.minimum..spec.maximum)
                if (forceStep < force.range.last) {
                    assertTrue(spec.evaluate(listOf((forceStep + 1) / force.scale, radiusMm)) > pressure)
                }
                if (radiusStep < radius.range.last) {
                    assertTrue(spec.evaluate(listOf(forceMn, (radiusStep + 1) / radius.scale)) < pressure)
                }
            }
        }
    }

    @Test fun chartCanSweepFractionalForceWithoutRounding() {
        val area = spec.companionValue(listOf(40.0, 2.3))
        val pressureChange = spec.evaluate(listOf(41.0, 2.3)) - spec.evaluate(listOf(40.0, 2.3))
        assertEquals(PI * 2.3 * 2.3, area, 1e-12)
        assertEquals(1.0 / area, pressureChange, 1e-12)
        assertEquals(40.5 / area, spec.evaluate(listOf(40.5, 2.3)), 1e-12)
    }
}
