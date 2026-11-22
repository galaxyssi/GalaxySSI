package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasAiiAmacrineRelayTeachingModelTest {
    private val spec = HealthAtlasAiiAmacrineRelayTeachingModel.spec
    private val control = spec.inputs.single().control

    @Test fun defaultRodBipolarChangeHasOppositeSignsInTheTwoBranches() {
        val defaults = listOf(control.initial / control.scale)
        assertEquals(setOf("cell-retinal-aii-amacrine-cell"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals("u", spec.inputs.single().unit)
        assertEquals("u", spec.unit)
        assertEquals(listOf(4.0), defaults)
        assertEquals(4.0, spec.evaluate(defaults), 0.0)
        assertEquals(-4.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun boundsMirrorAndZeroHasNoSignedChange() {
        val low = listOf(control.range.first / control.scale)
        val high = listOf(control.range.last / control.scale)
        assertEquals(-10.0, spec.minimum, 0.0)
        assertEquals(10.0, spec.maximum, 0.0)
        assertEquals(spec.minimum, spec.evaluate(low), 0.0)
        assertEquals(spec.maximum, spec.companionValue(low), 0.0)
        assertEquals(spec.maximum, spec.evaluate(high), 0.0)
        assertEquals(spec.minimum, spec.companionValue(high), 0.0)
        assertEquals(0.0.toBits(), spec.evaluate(listOf(0.0)).toBits())
        assertEquals(0.0.toBits(), spec.companionValue(listOf(0.0)).toBits())
    }

    @Test fun onPreservesAndOffReversesTheSignAcrossTheSlider() {
        for (step in control.range) {
            val input = step / control.scale
            val values = listOf(input)
            val on = spec.evaluate(values)
            val off = spec.companionValue(values)
            assertTrue(on in spec.minimum..spec.maximum && off in spec.minimum..spec.maximum)
            assertEquals(input, on, 0.0)
            assertEquals(0.0, on + off, 0.0)
            if (step > control.range.first) {
                val previous = listOf((step - 1) / control.scale)
                assertTrue(on > spec.evaluate(previous))
                assertTrue(off < spec.companionValue(previous))
            }
        }
    }
}
