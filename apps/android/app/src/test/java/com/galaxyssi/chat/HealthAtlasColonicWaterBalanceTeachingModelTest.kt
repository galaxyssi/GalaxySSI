package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasColonicWaterBalanceTeachingModelTest {
    private val spec = HealthAtlasColonicWaterBalanceTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-9

    @Test fun defaultsShowRemainingAndNetAbsorbedWaterInMilliliters() {
        assertEquals(setOf("large-intestine", "colon"), spec.entryIds)
        assertEquals(1, spec.axis)
        assertEquals(listOf("mL", "%"), spec.inputs.map { it.unit })
        assertEquals("mL", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(500.0, 80.0), defaults)
        assertEquals(100.0, spec.evaluate(defaults), epsilon)
        assertEquals(400.0, spec.companionValue(defaults), epsilon)
    }

    @Test fun noNetAbsorptionLeavesAllWaterAndCompleteNetAbsorptionLeavesNone() {
        val (volume, absorption) = controls
        for (volumeStep in listOf(volume.range.first, volume.range.last)) {
            val startingMl = volumeStep / volume.scale
            val none = listOf(startingMl, absorption.range.first / absorption.scale)
            val all = listOf(startingMl, absorption.range.last / absorption.scale)

            assertEquals(startingMl, spec.evaluate(none), epsilon)
            assertEquals(0.0, spec.companionValue(none), epsilon)
            assertEquals(0.0, spec.evaluate(all), epsilon)
            assertEquals(startingMl, spec.companionValue(all), epsilon)
        }
    }

    @Test fun largerStartingVolumeIncreasesBothOutputsAtFixedAbsorption() {
        val smaller = listOf(250.0, 80.0)
        val larger = listOf(500.0, 80.0)

        assertEquals(2.0 * spec.evaluate(smaller), spec.evaluate(larger), epsilon)
        assertEquals(2.0 * spec.companionValue(smaller), spec.companionValue(larger), epsilon)
    }

    @Test fun increasingAbsorptionLowersTheCurveAndConservesWaterAcrossSliderRanges() {
        val (volume, absorption) = controls
        for (volumeStep in volume.range) {
            val startingMl = volumeStep / volume.scale
            var previous = Double.POSITIVE_INFINITY
            for (absorptionStep in absorption.range) {
                val values = listOf(startingMl, absorptionStep / absorption.scale)
                val remaining = spec.evaluate(values)
                val absorbed = spec.companionValue(values)

                assertTrue(remaining in spec.minimum..spec.maximum)
                assertTrue(absorbed in 0.0..startingMl)
                assertTrue(remaining < previous)
                assertEquals(startingMl, remaining + absorbed, epsilon)
                previous = remaining
            }
        }
    }
}
