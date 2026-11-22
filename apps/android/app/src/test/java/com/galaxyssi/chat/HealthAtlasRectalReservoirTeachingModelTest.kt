package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasRectalReservoirTeachingModelTest {
    private val spec = HealthAtlasRectalReservoirTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-9

    @Test fun defaultsPlotReleasedVolumeAgainstReleaseShare() {
        assertEquals(setOf("rectum", "anal-canal"), spec.entryIds)
        assertEquals(listOf("rectal-reservoir-initial-volume", "rectal-reservoir-release-share"), controls.map { it.key })
        assertEquals(1, spec.axis)
        assertEquals(listOf("mL", "%"), spec.inputs.map { it.unit })
        assertEquals("mL", spec.unit)
        assertEquals(0.0, spec.minimum, epsilon)
        assertEquals(200.0, spec.maximum, epsilon)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(120.0, 40.0), defaults)
        assertEquals(48.0, spec.evaluate(defaults), epsilon)
        assertEquals(72.0, spec.companionValue(defaults), epsilon)
    }

    @Test fun zeroAndFullReleasePutAllExampleVolumeOnOppositeSidesOfTheBalance() {
        val (volume, share) = controls
        assertEquals(0.0, share.range.first / share.scale, epsilon)
        assertEquals(100.0, share.range.last / share.scale, epsilon)
        for (step in listOf(volume.range.first, volume.range.last)) {
            val initialMl = step / volume.scale
            val noRelease = listOf(initialMl, share.range.first / share.scale)
            val fullRelease = listOf(initialMl, share.range.last / share.scale)
            assertEquals(0.0, spec.evaluate(noRelease), epsilon)
            assertEquals(initialMl, spec.companionValue(noRelease), epsilon)
            assertEquals(initialMl, spec.evaluate(fullRelease), epsilon)
            assertEquals(0.0, spec.companionValue(fullRelease), epsilon)
        }
    }

    @Test fun largerStartingVolumeIncreasesBothVolumesAtFixedPartialRelease() {
        val smaller = listOf(60.0, 40.0)
        val larger = listOf(120.0, 40.0)
        assertEquals(2 * spec.evaluate(smaller), spec.evaluate(larger), epsilon)
        assertEquals(2 * spec.companionValue(smaller), spec.companionValue(larger), epsilon)
    }

    @Test fun increasingReleaseShareRaisesTheCurveAndConservesVolumeAcrossSliderRanges() {
        val (volume, share) = controls
        for (volumeStep in volume.range) {
            val initialMl = volumeStep / volume.scale
            var previousReleased = Double.NEGATIVE_INFINITY
            for (shareStep in share.range) {
                val values = listOf(initialMl, shareStep / share.scale)
                val released = spec.evaluate(values)
                val remaining = spec.companionValue(values)
                assertTrue(released in spec.minimum..spec.maximum)
                assertTrue(released in 0.0..initialMl)
                assertTrue(remaining in 0.0..initialMl)
                assertTrue(released > previousReleased)
                assertEquals(initialMl, released + remaining, epsilon)
                previousReleased = released
            }
        }
    }
}
