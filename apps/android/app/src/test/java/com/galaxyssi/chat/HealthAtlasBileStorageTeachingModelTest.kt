package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasBileStorageTeachingModelTest {
    private val spec = HealthAtlasBileStorageTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-12

    @Test fun defaultsPlotConcentrationAgainstWaterRemoved() {
        assertEquals(setOf("gallbladder"), spec.entryIds)
        assertEquals("bile-storage-water-removed", controls[spec.axis].key)
        assertEquals(listOf("TU", "VU"), spec.inputs.map { it.unit })
        assertEquals("TU/VU", spec.unit)
        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(6.0, 6.0), defaults)
        assertEquals(1.0, spec.evaluate(defaults), epsilon)
        assertEquals(6.0, spec.companionValue(defaults), epsilon)
    }

    @Test fun allSliderValuesConserveMarkerAndFitInsidePlotBounds() {
        val (markerControl, waterControl) = controls
        val concentrations = markerControl.range.flatMap { markerStep ->
            val marker = markerStep / markerControl.scale
            waterControl.range.map { waterStep ->
                val waterRemoved = waterStep / waterControl.scale
                val remainingVolume = 12.0 - waterRemoved
                val values = listOf(marker, waterRemoved)
                val concentration = spec.evaluate(values)
                assertTrue(remainingVolume > 0.0)
                assertTrue(concentration.isFinite() && concentration in spec.minimum..spec.maximum)
                assertEquals(marker, spec.companionValue(values), epsilon)
                assertEquals(marker, concentration * remainingVolume, epsilon)
                concentration
            }
        }
        assertEquals(1.0 / 12.0, concentrations.min(), epsilon)
        assertEquals(3.0, concentrations.max(), epsilon)
        assertEquals(3.0, spec.maximum, epsilon)
    }

    @Test fun removingMoreWaterRaisesConcentrationForEveryMarkerAmount() {
        val (markerControl, waterControl) = controls
        for (markerStep in markerControl.range) {
            val marker = markerStep / markerControl.scale
            val concentrations = waterControl.range.map { spec.evaluate(listOf(marker, it / waterControl.scale)) }
            assertTrue(concentrations.zipWithNext().all { (before, after) -> after > before })
        }
        val before = listOf(6.0, 0.0)
        val halfVolume = listOf(6.0, 6.0)
        assertEquals(2.0 * spec.evaluate(before), spec.evaluate(halfVolume), epsilon)
        assertEquals(spec.companionValue(before), spec.companionValue(halfVolume), epsilon)
    }
}
