package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasMastCellGranuleTallyTeachingModelTest {
    private val spec = HealthAtlasMastCellGranuleTallyTeachingModel.spec
    private val control = spec.inputs.single().control

    @Test fun sixDefaultDotsAreThirtyPercentReleasedWithFourteenStored() {
        assertEquals(setOf("cell-mast-cell"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals("mast-cell-granule-tally-released", control.key)
        assertEquals(0..20, control.range)
        assertEquals("%", spec.unit)
        assertEquals(0, spec.inputs.single().digits)
        assertEquals(0, spec.digits)

        val defaults = listOf(control.initial / control.scale)
        assertEquals(listOf(6.0), defaults)
        assertEquals(30.0, spec.evaluate(defaults), 0.0)
        assertEquals(14.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun noneAndAllReachThePercentScaleLimits() {
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(100.0, spec.maximum, 0.0)
        assertEquals(spec.minimum, spec.evaluate(listOf(0.0)), 0.0)
        assertEquals(20.0, spec.companionValue(listOf(0.0)), 0.0)
        assertEquals(spec.maximum, spec.evaluate(listOf(20.0)), 0.0)
        assertEquals(0.0, spec.companionValue(listOf(20.0)), 0.0)
    }

    @Test fun eachDotAddsFivePercentagePointsAndTheTotalStaysFixed() {
        var previous = spec.minimum
        for (step in 0..120) {
            val x = control.range.last * step / 120.0
            val released = (x + 0.5).toInt()
            val values = listOf(x)
            val percent = spec.evaluate(values)
            val stored = spec.companionValue(values)
            assertTrue(percent in spec.minimum..spec.maximum && percent >= previous)
            assertEquals(5.0 * released, percent, 0.0)
            assertTrue(stored in 0.0..20.0)
            assertEquals(20.0, released + stored, 0.0)
            previous = percent
        }
        assertEquals(25.0, spec.evaluate(listOf(5.49)), 0.0)
        assertEquals(30.0, spec.evaluate(listOf(5.5)), 0.0)
    }
}
