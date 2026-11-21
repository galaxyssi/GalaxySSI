package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasCircadianLightWindowTeachingModelTest {
    private val spec = HealthAtlasCircadianLightWindowTeachingModel.spec
    private val period = spec.inputs[0].control
    private val elapsed = spec.inputs[1].control

    @Test fun usesExactAtlasIdsAndPlotsDegreesAgainstElapsedHours() {
        assertEquals(setOf("hypothalamus", "pineal-gland", "cell-pinealocyte"), spec.entryIds)
        assertEquals(listOf("h", "h"), spec.inputs.map { it.unit })
        assertEquals("\u00b0", spec.unit)
        assertEquals(1, spec.axis)
    }

    @Test fun defaultsShowOneFullTurnPlusPartOfTheNext() {
        val defaults = spec.inputs.map { it.control.initial / it.control.scale }
        assertEquals(listOf(24.0, 30.0), defaults)
        assertEquals(450.0, spec.evaluate(defaults), 1e-9)
        assertEquals(90.0, spec.companionValue(defaults), 1e-9)
    }

    @Test fun chartRemainsInRangeAndIncreasesAtEveryElapsedStep() {
        assertEquals(12..30, period.range)
        assertEquals(0..48, elapsed.range)
        assertEquals(0.0, spec.minimum, 1e-9)
        assertEquals(1440.0, spec.maximum, 1e-9)
        for (rawPeriod in period.range) {
            val periodHours = rawPeriod / period.scale
            var previous = spec.evaluate(listOf(periodHours, elapsed.range.first / elapsed.scale))
            assertEquals(spec.minimum, previous, 1e-9)
            for (rawElapsed in elapsed.range) {
                val inputs = listOf(periodHours, rawElapsed / elapsed.scale)
                val phase = spec.evaluate(inputs)
                val wrapped = spec.companionValue(inputs)
                assertTrue(phase in spec.minimum..spec.maximum)
                if (rawElapsed > elapsed.range.first) assertTrue(phase > previous)
                assertTrue(wrapped >= 0.0 && wrapped < 360.0)
                previous = phase
            }
        }
        val upperCorner = listOf(period.range.first / period.scale, elapsed.range.last / elapsed.scale)
        assertEquals(spec.maximum, spec.evaluate(upperCorner), 1e-9)
    }

    @Test fun aLongerCycleAdvancesLessPhaseInTheSameElapsedTime() {
        val shortCycle = spec.evaluate(listOf(12.0, 6.0))
        val longCycle = spec.evaluate(listOf(30.0, 6.0))
        assertEquals(180.0, shortCycle, 1e-9)
        assertEquals(72.0, longCycle, 1e-9)
        assertTrue(shortCycle > longCycle)
    }

    @Test fun wrappedCompanionRepeatsAtEachLightCueWithoutResettingTheChart() {
        for (cycle in 0..2) {
            val start = 24.0 * cycle
            assertEquals(360.0 * cycle, spec.evaluate(listOf(24.0, start)), 1e-9)
            assertEquals(0.0, spec.companionValue(listOf(24.0, start)), 1e-9)
        }
        assertEquals(180.0, spec.companionValue(listOf(24.0, 12.0)), 1e-9)
        assertEquals(180.0, spec.companionValue(listOf(24.0, 36.0)), 1e-9)
        assertEquals(352.5, spec.companionValue(listOf(24.0, 23.5)), 1e-9)
        assertEquals(367.5, spec.evaluate(listOf(24.0, 24.5)), 1e-9)
        assertEquals(7.5, spec.companionValue(listOf(24.0, 24.5)), 1e-9)
    }
}
