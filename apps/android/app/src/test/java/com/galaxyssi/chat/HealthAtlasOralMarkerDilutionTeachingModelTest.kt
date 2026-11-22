package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasOralMarkerDilutionTeachingModelTest {
    private val spec = HealthAtlasOralMarkerDilutionTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-12

    @Test fun defaultsPlotMarkerConcentrationAgainstAddedWater() {
        assertEquals(setOf("oral-cavity", "tongue", "taste-buds", "cell-taste-receptor-cell"), spec.entryIds)
        assertEquals("oral-marker-dilution-added-water", controls[spec.axis].key)
        assertEquals(listOf("VU", "VU"), spec.inputs.map { it.unit })
        assertEquals("TU/VU", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(4.0, 4.0), defaults)
        assertEquals(8.0, spec.companionValue(defaults), epsilon)
        assertEquals(1.0, spec.evaluate(defaults), epsilon)
    }

    @Test fun allSliderPairsConserveMarkerAndFitPlotBounds() {
        val (markerStream, water) = controls
        assertEquals(2..8, markerStream.range)
        assertEquals(0..12, water.range)
        assertEquals(0.0, spec.minimum, epsilon)
        assertEquals(4.0, spec.maximum, epsilon)

        for (markerStep in markerStream.range) {
            for (waterStep in water.range) {
                val markerVolume = markerStep / markerStream.scale
                val waterVolume = waterStep / water.scale
                val values = listOf(markerVolume, waterVolume)
                val mixedVolume = spec.companionValue(values)
                val concentration = spec.evaluate(values)
                assertTrue(concentration.isFinite() && concentration in spec.minimum..spec.maximum)
                assertEquals(markerVolume + waterVolume, mixedVolume, epsilon)
                assertEquals(8.0, concentration * mixedVolume, epsilon)
            }
        }

        assertEquals(spec.maximum, spec.evaluate(listOf(2.0, 0.0)), epsilon)
        assertEquals(0.4, spec.evaluate(listOf(8.0, 12.0)), epsilon)
    }

    @Test fun addingWaterLowersConcentrationAtEveryMarkerStreamVolume() {
        val (markerStream, water) = controls
        for (markerStep in markerStream.range) {
            val markerVolume = markerStep / markerStream.scale
            val concentrations = water.range.map { spec.evaluate(listOf(markerVolume, it / water.scale)) }
            assertTrue(concentrations.zipWithNext().all { (before, after) -> after < before })
        }
        assertEquals(spec.evaluate(listOf(4.0, 0.0)) / 2, spec.evaluate(listOf(4.0, 4.0)), epsilon)
    }
}
