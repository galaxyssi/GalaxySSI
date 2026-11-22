package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasVestibularGlandVolumeTeachingModelTest {
    private val spec = HealthAtlasVestibularGlandVolumeTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val tolerance = 1e-12

    @Test fun defaultAddsTheTwoSeparateVolumes() {
        val defaults = controls.map { it.initial / it.scale }
        assertEquals(setOf("greater-vestibular-glands"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("vu", "vu"), spec.inputs.map { it.unit })
        assertEquals("vu", spec.unit)
        assertEquals(listOf(2.0, 3.0), defaults)
        assertEquals(5.0, spec.evaluate(defaults), tolerance)
        assertEquals(1.0, spec.companionValue(defaults), tolerance)
    }

    @Test fun totalsAreBoundedAndDoNotDependOnWhichOutletIsCalledA() {
        for (control in controls) {
            assertEquals(0.0, control.range.first / control.scale, tolerance)
            assertEquals(6.0, control.range.last / control.scale, tolerance)
        }
        assertEquals(0.0, spec.minimum, tolerance)
        assertEquals(12.0, spec.maximum, tolerance)
        assertEquals(spec.minimum, spec.evaluate(listOf(0.0, 0.0)), tolerance)
        assertEquals(spec.maximum, spec.evaluate(listOf(6.0, 6.0)), tolerance)
        assertEquals(0.0, spec.companionValue(listOf(6.0, 6.0)), tolerance)
        assertEquals(6.0, spec.companionValue(listOf(0.0, 6.0)), tolerance)

        val (aControl, bControl) = controls
        for (bStep in bControl.range) {
            val b = bStep / bControl.scale
            var previousTotal = -1.0
            for (aStep in aControl.range) {
                val a = aStep / aControl.scale
                val values = listOf(a, b)
                val total = spec.evaluate(values)
                val difference = spec.companionValue(values)
                assertTrue(total in spec.minimum..spec.maximum && total > previousTotal)
                assertTrue(difference in 0.0..6.0)
                assertEquals(total, spec.evaluate(listOf(b, a)), tolerance)
                assertEquals(difference, spec.companionValue(listOf(b, a)), tolerance)
                assertEquals(maxOf(a, b), (total + difference) / 2.0, tolerance)
                assertEquals(minOf(a, b), (total - difference) / 2.0, tolerance)
                previousTotal = total
            }
        }
    }
}
