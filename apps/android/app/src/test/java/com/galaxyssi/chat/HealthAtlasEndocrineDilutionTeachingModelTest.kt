package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasEndocrineDilutionTeachingModelTest {
    private val spec = HealthAtlasEndocrineDilutionTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-12

    @Test fun defaultsUseSyntheticUnitsAndPlotAgainstVolume() {
        assertEquals(1, spec.axis)
        assertEquals(listOf("TU", "VU"), spec.inputs.map { it.unit })
        assertEquals("TU/VU", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(6.0, 4.0), defaults)
        assertEquals(1.5, spec.evaluate(defaults), epsilon)
        assertEquals(6.0, spec.companionValue(defaults), epsilon)
    }

    @Test fun sliderExtremesAreFiniteAndFitThePlot() {
        val (amountControl, volumeControl) = controls
        val amounts = listOf(amountControl.range.first, amountControl.range.last).map { it / amountControl.scale }
        val volumes = listOf(volumeControl.range.first, volumeControl.range.last).map { it / volumeControl.scale }

        val corners = amounts.flatMap { amount ->
            volumes.map { volume ->
                val values = listOf(amount, volume)
                assertEquals(amount, spec.companionValue(values), epsilon)
                spec.evaluate(values).also { assertTrue(it in spec.minimum..spec.maximum) }
            }
        }
        assertEquals(1.0 / 12.0, corners.min(), epsilon)
        assertEquals(6.0, corners.max(), epsilon)
    }

    @Test fun concentrationFallsWithVolumeAndRisesWithAmountAcrossSliderRanges() {
        val (amountControl, volumeControl) = controls
        val amounts = amountControl.range.map { it / amountControl.scale }
        val volumes = volumeControl.range.map { it / volumeControl.scale }

        for (amount in amounts) {
            val concentrations = volumes.map { spec.evaluate(listOf(amount, it)) }
            assertTrue(concentrations.zipWithNext().all { (before, after) -> before > after })
        }
        for (volume in volumes) {
            val concentrations = amounts.map { spec.evaluate(listOf(it, volume)) }
            assertTrue(concentrations.zipWithNext().all { (before, after) -> before < after })
        }
    }

    @Test fun doublingVolumeHalvesConcentrationWithoutLosingTracer() {
        val initial = listOf(6.0, 4.0)
        val largerVolume = listOf(6.0, 8.0)
        val greaterAmount = listOf(12.0, 4.0)

        assertEquals(spec.evaluate(initial) / 2, spec.evaluate(largerVolume), epsilon)
        assertEquals(spec.companionValue(initial), spec.companionValue(largerVolume), epsilon)
        assertEquals(spec.evaluate(initial) * 2, spec.evaluate(greaterAmount), epsilon)
    }
}
