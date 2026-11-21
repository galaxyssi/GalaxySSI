package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasMucusFilmThicknessTeachingModelTest {
    private val spec = HealthAtlasMucusFilmThicknessTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val volumes = controls[0].let { control -> control.range.map { it / control.scale } }
    private val areas = controls[1].let { control -> control.range.map { it / control.scale } }

    @Test fun defaultsUseFictionalUnitsAndPlotAgainstCoatedArea() {
        assertEquals(setOf("cell-goblet-cell", "pharynx", "tissue-intestinal-epithelium"), spec.entryIds)
        assertEquals(listOf("mucus-film-volume", "mucus-film-area"), controls.map { it.key })
        assertEquals(1, spec.axis)
        assertEquals(listOf("u\u00b3", "u\u00b2"), spec.inputs.map { it.unit })
        assertEquals("u", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(12.0, 6.0), defaults)
        assertEquals(2.0, spec.evaluate(defaults), 0.0)
        assertEquals(12.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun everySliderPairFitsTheChartAndPreservesFluidVolume() {
        assertEquals(listOf(4..24, 2..12), controls.map { it.range })
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(12.0, spec.maximum, 0.0)
        assertEquals(1.0 / 3.0, spec.evaluate(listOf(volumes.first(), areas.last())), 0.0)
        assertEquals(spec.maximum, spec.evaluate(listOf(volumes.last(), areas.first())), 0.0)

        for (volume in volumes) for (area in areas) {
            val values = listOf(volume, area)
            val thickness = spec.evaluate(values)
            assertTrue("Thickness at $values: $thickness", thickness in spec.minimum..spec.maximum)
            assertEquals(volume, thickness * area, 1e-12)
            assertEquals(volume, spec.companionValue(values), 0.0)
        }
    }

    @Test fun thicknessFallsWithAreaAndRisesWithVolumeAcrossSliderRanges() {
        for (volume in volumes) {
            assertTrue(areas.zipWithNext().all { (smaller, larger) ->
                spec.evaluate(listOf(volume, smaller)) > spec.evaluate(listOf(volume, larger))
            })
        }
        for (area in areas) {
            assertTrue(volumes.zipWithNext().all { (less, more) ->
                spec.evaluate(listOf(less, area)) < spec.evaluate(listOf(more, area))
            })
        }
    }

    @Test fun doublingAreaHalvesThicknessAndDoublingVolumeDoublesIt() {
        val baseline = spec.evaluate(listOf(12.0, 6.0))
        assertEquals(baseline / 2, spec.evaluate(listOf(12.0, 12.0)), 0.0)
        assertEquals(baseline * 2, spec.evaluate(listOf(24.0, 6.0)), 0.0)
    }
}
