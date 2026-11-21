package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasOviductCiliaryCyclesTeachingModelTest {
    private val spec = HealthAtlasOviductCiliaryCyclesTeachingModel.spec
    private val rate = spec.inputs[0].control
    private val time = spec.inputs[1].control

    @Test fun hasExactEntryIdsAndPlotsCyclesAgainstTime() {
        assertEquals(setOf("female", "uterine-tubes", "cell-ciliated-oviduct-cell"), spec.entryIds)
        assertEquals(listOf("Hz", "s"), spec.inputs.map { it.unit })
        assertEquals("cycles", spec.unit)
        assertEquals(1, spec.axis)
    }

    @Test fun defaultsIncludePartialCyclesAndReportMillisecondsPerCycle() {
        val defaults = spec.inputs.map { it.control.initial / it.control.scale }
        assertEquals(listOf(5.0, 1.5), defaults)
        assertEquals(7.5, spec.evaluate(defaults), 1e-9)
        assertEquals(200.0, spec.companionValue(defaults), 1e-9)
    }

    @Test fun changingTheFirstControlChangesTheCurveAndShortensThePeriod() {
        val slower = listOf(4.0, 0.3)
        val faster = listOf(8.0, 0.3)
        assertEquals(1.2, spec.evaluate(slower), 1e-9)
        assertEquals(2.4, spec.evaluate(faster), 1e-9)
        assertEquals(250.0, spec.companionValue(slower), 1e-9)
        assertEquals(125.0, spec.companionValue(faster), 1e-9)
    }

    @Test fun chartContainsAllSliderPairsAndPeriodIsIndependentOfTime() {
        assertEquals(0.0, spec.minimum, 1e-9)
        assertEquals(20.0, spec.maximum, 1e-9)
        for (rawRate in rate.range) {
            val rateHz = rawRate / rate.scale
            assertTrue(rateHz > 0.0)
            val start = listOf(rateHz, time.range.first / time.scale)
            assertEquals(0.0, spec.evaluate(start), 1e-9)
            val period = spec.companionValue(start)
            assertTrue(period in 100.0..250.0)
            for (rawTime in time.range) {
                val values = listOf(rateHz, rawTime / time.scale)
                assertTrue(spec.evaluate(values) in spec.minimum..spec.maximum)
                assertEquals(period, spec.companionValue(values), 1e-9)
            }
        }
        val upperCorner = listOf(rate.range.last / rate.scale, time.range.last / time.scale)
        assertEquals(spec.maximum, spec.evaluate(upperCorner), 1e-9)
        assertEquals(100.0, spec.companionValue(upperCorner), 1e-9)
    }

    @Test fun periodRequiresAFinitePositiveRate() {
        for (rateHz in listOf(0.0, -1.0, Double.NaN, Double.POSITIVE_INFINITY)) {
            assertThrows(IllegalArgumentException::class.java) {
                spec.companionValue(listOf(rateHz, 1.0))
            }
        }
    }
}
