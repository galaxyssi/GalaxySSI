package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasEpendymalBeatPhaseTeachingModelTest {
    private val spec = HealthAtlasEpendymalBeatPhaseTeachingModel.spec
    private val frequency = spec.inputs[0].control
    private val offset = spec.inputs[1].control

    @Test fun bindsOnlyEpendymalCellAndPlotsCyclesAgainstTimingOffset() {
        assertEquals(setOf("cell-ependymal-cell"), spec.entryIds)
        assertEquals("ependymal-beat-phase-frequency", frequency.key)
        assertEquals("ependymal-beat-phase-offset", offset.key)
        assertEquals(1, spec.axis)
        assertEquals(listOf("cycles/interval", "intervals"), spec.inputs.map { it.unit })
        assertEquals("cycles", spec.unit)
    }

    @Test fun defaultsMultiplyFrequencyByOffsetAndKeepOnlyTheFractionalCycleWhenWrapped() {
        val defaults = spec.inputs.map { it.control.initial / it.control.scale }
        assertEquals(listOf(1.25, 1.25), defaults)
        assertEquals(1.5625, spec.evaluate(defaults), 1e-9)
        assertEquals(0.5625, spec.companionValue(defaults), 1e-9)
    }

    @Test fun wrappedPhaseResetsAtWholeCyclesWhileUnwrappedPhaseKeepsRising() {
        val before = listOf(2.0, 0.375)
        val at = listOf(2.0, 0.5)
        val after = listOf(2.0, 0.625)
        assertEquals(listOf(0.75, 1.0, 1.25), listOf(before, at, after).map(spec.evaluate))
        assertEquals(listOf(0.75, 0.0, 0.25), listOf(before, at, after).map(spec.companionValue))
        assertEquals(spec.companionValue(after), spec.companionValue(listOf(2.0, 0.125)), 1e-9)
    }

    @Test fun increasingFrequencyAtFixedOffsetIncreasesUnwrappedPhase() {
        assertEquals(0.75, spec.evaluate(listOf(0.5, 1.5)), 1e-9)
        assertEquals(3.0, spec.evaluate(listOf(2.0, 1.5)), 1e-9)
    }

    @Test fun allSliderPairsStayInBoundsAndUnwrappedPhaseIncreasesAlongTheChart() {
        assertEquals(0.0, spec.minimum, 1e-9)
        assertEquals(4.0, spec.maximum, 1e-9)
        for (rawFrequency in frequency.range) {
            val rate = rawFrequency / frequency.scale
            val phases = offset.range.map { rawOffset ->
                val values = listOf(rate, rawOffset / offset.scale)
                val phase = spec.evaluate(values)
                val wrappedPhase = spec.companionValue(values)
                assertTrue(phase in spec.minimum..spec.maximum)
                assertTrue(wrappedPhase >= 0.0 && wrappedPhase < 1.0)
                phase
            }
            assertEquals(0.0, phases.first(), 1e-9)
            assertEquals(0.0, spec.companionValue(listOf(rate, 0.0)), 1e-9)
            assertTrue(phases.zipWithNext().all { (left, right) -> left < right })
        }
        val upperCorner = listOf(frequency.range.last / frequency.scale, offset.range.last / offset.scale)
        assertEquals(spec.maximum, spec.evaluate(upperCorner), 1e-9)
        assertEquals(0.0, spec.companionValue(upperCorner), 1e-9)
    }
}
