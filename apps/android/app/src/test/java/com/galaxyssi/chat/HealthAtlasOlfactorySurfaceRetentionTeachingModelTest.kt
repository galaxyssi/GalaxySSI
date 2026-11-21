package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasOlfactorySurfaceRetentionTeachingModelTest {
    private val spec = HealthAtlasOlfactorySurfaceRetentionTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-9

    @Test fun defaultsSplitFictionalMarkerAcrossTheTwoSides() {
        assertEquals(setOf("olfactory-mucosa"), spec.entryIds)
        assertEquals(1, spec.axis)
        assertEquals(listOf("olfactory-marker-total", "olfactory-mucus-side-share"), controls.map { it.key })
        assertEquals(listOf("a.u.", "%"), spec.inputs.map { it.unit })
        assertEquals("a.u.", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(80.0, 35.0), defaults)
        assertEquals(28.0, spec.evaluate(defaults), epsilon)
        assertEquals(52.0, spec.companionValue(defaults), epsilon)
    }

    @Test fun percentageEndpointsPutAllMarkerOnOneSide() {
        val (total, share) = controls
        assertEquals(20..100, total.range)
        assertEquals(0..100, share.range)
        assertEquals(0.0, spec.minimum, epsilon)
        assertEquals(100.0, spec.maximum, epsilon)

        for (totalStep in listOf(total.range.first, total.range.last)) {
            val amount = totalStep / total.scale
            val allAir = listOf(amount, share.range.first / share.scale)
            val allMucus = listOf(amount, share.range.last / share.scale)

            assertEquals(0.0, spec.evaluate(allAir), epsilon)
            assertEquals(amount, spec.companionValue(allAir), epsilon)
            assertEquals(amount, spec.evaluate(allMucus), epsilon)
            assertEquals(0.0, spec.companionValue(allMucus), epsilon)
        }
    }

    @Test fun increasingMucusShareShiftsMarkerFromAirWithoutChangingTheTotal() {
        val (total, share) = controls
        for (totalStep in total.range) {
            val amount = totalStep / total.scale
            var previousMucus = Double.NEGATIVE_INFINITY
            var previousAir = Double.POSITIVE_INFINITY
            for (shareStep in share.range) {
                val values = listOf(amount, shareStep / share.scale)
                val mucus = spec.evaluate(values)
                val air = spec.companionValue(values)

                assertTrue(mucus in spec.minimum..spec.maximum)
                assertTrue(air in 0.0..amount)
                assertTrue(mucus > previousMucus)
                assertTrue(air < previousAir)
                assertEquals(amount, mucus + air, epsilon)
                previousMucus = mucus
                previousAir = air
            }
        }
    }

    @Test fun increasingTheTotalScalesBothAmountsAtAFixedShare() {
        val lowTotal = listOf(20.0, 35.0)
        val highTotal = listOf(100.0, 35.0)

        assertEquals(5 * spec.evaluate(lowTotal), spec.evaluate(highTotal), epsilon)
        assertEquals(5 * spec.companionValue(lowTotal), spec.companionValue(highTotal), epsilon)
    }
}
