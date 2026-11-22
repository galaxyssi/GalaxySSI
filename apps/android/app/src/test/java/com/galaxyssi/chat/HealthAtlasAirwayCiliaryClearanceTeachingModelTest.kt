package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasAirwayCiliaryClearanceTeachingModelTest {
    private val spec = HealthAtlasAirwayCiliaryClearanceTeachingModel.spec
    private val cycles = spec.inputs[0].control
    private val advance = spec.inputs[1].control

    @Test fun bindsOnlyTheRequestedEntriesAndPlotsTravelAgainstCycles() {
        assertEquals(
            setOf(
                "nose", "nasal-cavity", "paranasal-sinuses",
                "tissue-respiratory-epithelium", "cell-ciliated-airway-cell",
            ),
            spec.entryIds,
        )
        assertEquals(0, spec.axis)
        assertEquals(listOf("cycles", "u/cycle"), spec.inputs.map { it.unit })
        assertEquals("u", spec.unit)
    }

    @Test fun defaultsReportMarkerTravelAndTrackProgress() {
        val defaults = spec.inputs.map { it.control.initial / it.control.scale }

        assertEquals(listOf(12.0, 1.5), defaults)
        assertEquals(18.0, spec.evaluate(defaults), 1e-9)
        assertEquals(30.0, spec.companionValue(defaults), 1e-9)
    }

    @Test fun noCyclesOrNoAdvanceLeavesTheMarkerAtTheStart() {
        for (values in listOf(listOf(0.0, 2.5), listOf(24.0, 0.0))) {
            assertEquals(0.0, spec.evaluate(values), 1e-9)
            assertEquals(0.0, spec.companionValue(values), 1e-9)
        }
    }

    @Test fun additionalCyclesAndLargerStepsMoveTheMarkerForward() {
        val baseline = listOf(6.0, 1.0)
        for (values in listOf(listOf(12.0, 1.0), listOf(6.0, 2.0))) {
            assertEquals(2.0 * spec.evaluate(baseline), spec.evaluate(values), 1e-9)
            assertEquals(2.0 * spec.companionValue(baseline), spec.companionValue(values), 1e-9)
        }
        assertEquals(9.3, spec.evaluate(listOf(6.2, 1.5)), 1e-9)
    }

    @Test fun chartFitsEverySliderPairAndTheUpperCornerFillsTheTrack() {
        assertEquals(0.0, spec.minimum, 1e-9)
        assertEquals(60.0, spec.maximum, 1e-9)
        for (rawCycles in cycles.range) {
            for (rawAdvance in advance.range) {
                val values = listOf(rawCycles / cycles.scale, rawAdvance / advance.scale)
                assertTrue(spec.evaluate(values) in spec.minimum..spec.maximum)
                assertTrue(spec.companionValue(values) in 0.0..100.0)
            }
        }
        val upperCorner = listOf(cycles.range.last / cycles.scale, advance.range.last / advance.scale)
        assertEquals(60.0, spec.evaluate(upperCorner), 1e-9)
        assertEquals(100.0, spec.companionValue(upperCorner), 1e-9)
    }
}
