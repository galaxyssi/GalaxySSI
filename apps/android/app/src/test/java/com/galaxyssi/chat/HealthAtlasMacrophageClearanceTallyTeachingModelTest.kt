package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasMacrophageClearanceTallyTeachingModelTest {
    private val spec = HealthAtlasMacrophageClearanceTallyTeachingModel.spec
    private val controls = spec.inputs.map { it.control }

    @Test fun defaultsLeaveThreeOfEightIconsOutside() {
        assertEquals(setOf("cell-macrophage"), spec.entryIds)
        assertEquals("macrophage-clearance-tally-outside", controls[spec.axis].key)
        assertEquals(listOf(0..12, 0..8), controls.map { it.range })
        assertEquals(listOf(0, 0), spec.inputs.map { it.digits })
        assertEquals(0, spec.digits)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(8.0, 5.0), defaults)
        assertEquals(5.0, spec.evaluate(defaults), 0.0)
        assertEquals(3.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun eitherCountCanLimitTheTally() {
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(8.0, spec.maximum, 0.0)
        assertEquals(spec.minimum, spec.evaluate(listOf(0.0, 8.0)), 0.0)
        assertEquals(spec.minimum, spec.evaluate(listOf(12.0, 0.0)), 0.0)
        assertEquals(12.0, spec.companionValue(listOf(12.0, 0.0)), 0.0)
        assertEquals(spec.maximum, spec.evaluate(listOf(12.0, 8.0)), 0.0)
        assertEquals(4.0, spec.companionValue(listOf(12.0, 8.0)), 0.0)
        assertEquals(3.0, spec.evaluate(listOf(3.0, 8.0)), 0.0)
        assertEquals(0.0, spec.companionValue(listOf(3.0, 8.0)), 0.0)
        assertEquals(4.0, spec.evaluate(listOf(4.49, 8.0)), 0.0)
        assertEquals(5.0, spec.evaluate(listOf(4.5, 8.0)), 0.0)
    }

    @Test fun chartIsMonotonicAndInsidePlusOutsideConservesEveryIcon() {
        val (outsideControl, spacesControl) = controls
        for (spaces in spacesControl.range) {
            var previous = spec.minimum
            for (step in 0..120) {
                val x = outsideControl.range.last * step / 120.0
                val outside = (x + 0.5).toInt()
                val inputs = listOf(x, spaces.toDouble())
                val inside = spec.evaluate(inputs)
                val leftOutside = spec.companionValue(inputs)
                assertEquals(minOf(outside, spaces).toDouble(), inside, 0.0)
                assertTrue(inside in spec.minimum..spec.maximum && inside >= previous)
                assertTrue(leftOutside in 0.0..outside.toDouble())
                assertEquals(outside.toDouble(), inside + leftOutside, 0.0)
                previous = inside
            }
        }
    }
}
