package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasMuscleSatelliteFusionTallyTeachingModelTest {
    private val spec = HealthAtlasMuscleSatelliteFusionTallyTeachingModel.spec
    private val controls = spec.inputs.map { it.control }

    @Test fun defaultsKeepFiberNucleiSeparateFromTheReserve() {
        assertEquals(setOf("cell-muscle-satellite-cell"), spec.entryIds)
        assertEquals("muscle-satellite-fusion-tally-fused", controls[spec.axis].key)
        assertEquals(listOf(0..8, 1..12), controls.map { it.range })
        assertEquals(listOf(0, 0), spec.inputs.map { it.digits })
        assertEquals(0, spec.digits)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(3.0, 6.0), defaults)
        assertEquals(9.0, spec.evaluate(defaults), 0.0)
        assertEquals(5.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun addedNucleusIconsAndSeparateReserveAlwaysAccountForEightDescendants() {
        assertEquals(1.0, spec.minimum, 0.0)
        assertEquals(20.0, spec.maximum, 0.0)
        assertEquals(spec.minimum, spec.evaluate(listOf(0.0, 1.0)), 0.0)
        assertEquals(spec.maximum, spec.evaluate(listOf(8.0, 12.0)), 0.0)
        assertEquals(8.0, spec.companionValue(listOf(0.0, 1.0)), 0.0)
        assertEquals(0.0, spec.companionValue(listOf(8.0, 12.0)), 0.0)

        val (fusedControl, startingControl) = controls
        for (starting in startingControl.range) {
            for (fused in fusedControl.range) {
                val values = listOf(fused.toDouble(), starting.toDouble())
                val finalNuclei = spec.evaluate(values)
                val reserve = spec.companionValue(values)
                assertTrue(finalNuclei in spec.minimum..spec.maximum && reserve in 0.0..8.0)
                assertEquals(fused.toDouble(), finalNuclei - starting, 0.0)
                assertEquals(8.0, finalNuclei - starting + reserve, 0.0)
            }
        }
    }

    @Test fun chartRoundsToWholeIconsBeforeChangingEitherCompartment() {
        assertEquals(8.0, spec.evaluate(listOf(2.49, 6.0)), 0.0)
        assertEquals(9.0, spec.evaluate(listOf(2.5, 6.0)), 0.0)
        assertEquals(6.0, spec.companionValue(listOf(2.49, 6.0)), 0.0)
        assertEquals(5.0, spec.companionValue(listOf(2.5, 6.0)), 0.0)
    }
}
