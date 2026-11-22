package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasSweatDuctBalanceTeachingModelTest {
    private val spec = HealthAtlasSweatDuctBalanceTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-9

    @Test fun defaultsShowOutletAndReabsorbedSodiumInNanomoles() {
        assertEquals(setOf("cell-sweat-gland-secretory-cell", "dermis"), spec.entryIds)
        assertEquals(1, spec.axis)
        assertEquals(listOf("sweat-duct-coil-sodium", "sweat-duct-net-reabsorbed"), controls.map { it.key })
        assertEquals(listOf("nmol", "%"), spec.inputs.map { it.unit })
        assertEquals("nmol", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(140.0, 75.0), defaults)
        assertEquals(35.0, spec.evaluate(defaults), epsilon)
        assertEquals(105.0, spec.companionValue(defaults), epsilon)
    }

    @Test fun boundedExtremesLeaveAllOrOneTenthOfTheCoilSodium() {
        val (coil, reabsorption) = controls
        assertEquals(120..160, coil.range)
        assertEquals(0..90, reabsorption.range)
        for (coilStep in listOf(coil.range.first, coil.range.last)) {
            val coilNmol = coilStep / coil.scale
            val none = listOf(coilNmol, reabsorption.range.first / reabsorption.scale)
            val most = listOf(coilNmol, reabsorption.range.last / reabsorption.scale)

            assertEquals(coilNmol, spec.evaluate(none), epsilon)
            assertEquals(0.0, spec.companionValue(none), epsilon)
            assertEquals(coilNmol * 0.1, spec.evaluate(most), epsilon)
            assertEquals(coilNmol * 0.9, spec.companionValue(most), epsilon)
        }
    }

    @Test fun increasingNetReabsorptionLowersOutletSodiumAndConservesTheCoilAmount() {
        val (coil, reabsorption) = controls
        for (coilStep in coil.range) {
            val coilNmol = coilStep / coil.scale
            var previousOutlet = Double.POSITIVE_INFINITY
            var previousReabsorbed = Double.NEGATIVE_INFINITY
            for (reabsorptionStep in reabsorption.range) {
                val values = listOf(coilNmol, reabsorptionStep / reabsorption.scale)
                val outlet = spec.evaluate(values)
                val reabsorbed = spec.companionValue(values)

                assertTrue(outlet in spec.minimum..spec.maximum)
                assertTrue(reabsorbed in 0.0..coilNmol)
                assertTrue(outlet < previousOutlet)
                assertTrue(reabsorbed > previousReabsorbed)
                assertEquals(coilNmol, outlet + reabsorbed, epsilon)
                previousOutlet = outlet
                previousReabsorbed = reabsorbed
            }
        }
    }

    @Test fun increasingCoilSodiumRaisesBothAmountsAtFixedPositiveReabsorption() {
        val (coil, reabsorption) = controls
        val percent = reabsorption.initial / reabsorption.scale
        for (coilStep in coil.range.first until coil.range.last) {
            val lower = listOf(coilStep / coil.scale, percent)
            val higher = listOf((coilStep + 1) / coil.scale, percent)

            assertTrue(spec.evaluate(higher) > spec.evaluate(lower))
            assertTrue(spec.companionValue(higher) > spec.companionValue(lower))
        }
    }
}
