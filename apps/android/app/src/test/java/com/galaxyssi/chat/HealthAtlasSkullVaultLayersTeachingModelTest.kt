package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasSkullVaultLayersTeachingModelTest {
    private val spec = HealthAtlasSkullVaultLayersTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val tolerance = 1e-12

    @Test fun defaultsSeparateTheBoneWallFromTheFullDrawingSpanForSkullOnly() {
        val defaults = controls.map { it.initial / it.scale }

        assertEquals(setOf("skull"), spec.entryIds)
        assertEquals("skull-vault-layers-diploe", controls[spec.axis].key)
        assertEquals(listOf(10..50, 5..25), controls.map { it.range })
        assertEquals(listOf("u", "u"), spec.inputs.map { it.unit })
        assertEquals("u", spec.unit)
        assertEquals(listOf(2.5, 1.5), defaults)
        assertEquals(6.0, spec.evaluate(defaults), tolerance)
        assertEquals(4.5, spec.companionValue(defaults), tolerance)
    }

    @Test fun smallestAndLargestBandStacksReachThePlotBounds() {
        assertEquals(3.5, spec.minimum, tolerance)
        assertEquals(9.5, spec.maximum, tolerance)
        assertEquals(spec.minimum, spec.evaluate(listOf(1.0, 0.5)), tolerance)
        assertEquals(spec.maximum, spec.evaluate(listOf(5.0, 2.5)), tolerance)
        assertEquals(3.0, spec.companionValue(listOf(1.0, 0.5)), tolerance)
        assertEquals(7.0, spec.companionValue(listOf(5.0, 2.5)), tolerance)
    }

    @Test fun boneAndFluidBandsStaySeparateAsWidthsIncrease() {
        val (diploeControl, fluidControl) = controls
        for (fluidStep in fluidControl.range) {
            val fluid = fluidStep / fluidControl.scale
            var previousSpan = 0.0
            for (diploeStep in diploeControl.range) {
                val diploe = diploeStep / diploeControl.scale
                val inputs = listOf(diploe, fluid)
                val span = spec.evaluate(inputs)
                val bone = spec.companionValue(inputs)
                assertTrue(span in spec.minimum..spec.maximum && span > previousSpan)
                assertEquals(diploe + 2.0, bone, tolerance)
                assertEquals(fluid, span - bone, tolerance)
                previousSpan = span
            }
        }

        val narrowFluid = listOf(2.55, 0.5)
        val wideFluid = listOf(2.55, 2.5)
        assertEquals(4.55, spec.companionValue(narrowFluid), tolerance)
        assertEquals(spec.companionValue(narrowFluid), spec.companionValue(wideFluid), tolerance)
        assertEquals(2.0, spec.evaluate(wideFluid) - spec.evaluate(narrowFluid), tolerance)
    }
}
