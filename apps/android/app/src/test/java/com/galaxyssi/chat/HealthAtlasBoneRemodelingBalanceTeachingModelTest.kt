package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasBoneRemodelingBalanceTeachingModelTest {
    private val spec = HealthAtlasBoneRemodelingBalanceTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-9

    @Test fun defaultsBalanceFormationAndResorptionInArbitraryUnits() {
        assertEquals(setOf("cell-osteoblast", "cell-osteoclast", "cell-osteocyte"), spec.entryIds)
        assertEquals("bone-remodeling-resorbed", controls[spec.axis].key)
        assertEquals(listOf("a.u.", "a.u."), spec.inputs.map { it.unit })
        assertEquals("a.u.", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(10.0, 10.0), defaults)
        assertEquals(0.0, spec.evaluate(defaults), epsilon)
        assertEquals(100.0, spec.companionValue(defaults), epsilon)
    }

    @Test fun resorptionOnlyAndFormationOnlyReachOppositeSignedBounds() {
        val (resorbed, formed) = controls
        val resorptionOnly = listOf(resorbed.range.last / resorbed.scale, formed.range.first / formed.scale)
        val formationOnly = listOf(resorbed.range.first / resorbed.scale, formed.range.last / formed.scale)

        assertEquals(-20.0, spec.minimum, epsilon)
        assertEquals(20.0, spec.maximum, epsilon)
        assertEquals(spec.minimum, spec.evaluate(resorptionOnly), epsilon)
        assertEquals(spec.maximum, spec.evaluate(formationOnly), epsilon)
        assertEquals(80.0, spec.companionValue(resorptionOnly), epsilon)
        assertEquals(120.0, spec.companionValue(formationOnly), epsilon)
    }

    @Test fun resorptionLowersTheCurveAndFormationRaisesItAcrossTheSliderRanges() {
        val (resorbed, formed) = controls
        for (resorptionStep in resorbed.range) {
            for (formationStep in formed.range) {
                val removed = resorptionStep / resorbed.scale
                val added = formationStep / formed.scale
                val values = listOf(removed, added)
                val net = spec.evaluate(values)
                val finalAmount = spec.companionValue(values)

                assertTrue(net in spec.minimum..spec.maximum)
                assertTrue(finalAmount in 80.0..120.0)
                assertEquals(added, net + removed, epsilon)
                assertEquals(net, finalAmount - 100.0, epsilon)
                if (resorptionStep < resorbed.range.last) {
                    assertTrue(spec.evaluate(listOf(removed + 1.0 / resorbed.scale, added)) < net)
                }
                if (formationStep < formed.range.last) {
                    assertTrue(spec.evaluate(listOf(removed, added + 1.0 / formed.scale)) > net)
                }
            }
        }
    }

    @Test fun chartSamplesBetweenSliderStepsInterpolateTheSignedChange() {
        assertEquals(0.5, spec.evaluate(listOf(9.5, 10.0)), epsilon)
        assertEquals(-0.5, spec.evaluate(listOf(10.5, 10.0)), epsilon)
    }
}
