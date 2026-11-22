package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasCutaneousSebumTeachingModelTest {
    private val spec = HealthAtlasCutaneousSebumTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val masses = controls[0].let { control -> control.range.map { it / control.scale } }
    private val areas = controls[1].let { control -> control.range.map { it / control.scale } }

    @Test fun defaultsPlotAgainstAreaAndApplyOnlyToSebumProducingEntries() {
        assertEquals(setOf("sebaceous-glands", "cell-sebocyte"), spec.entryIds)
        assertEquals(1, spec.axis)
        assertEquals(listOf("\u00b5g", "cm\u00b2"), spec.inputs.map { it.unit })
        assertEquals("\u00b5g/cm\u00b2", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(40.0, 8.0), defaults)
        assertEquals(5.0, spec.evaluate(defaults), 0.0)
        assertEquals(40.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun allSliderCombinationsFitChartAndConserveCoatingMass() {
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(20.0, spec.maximum, 0.0)
        assertEquals(1.25, spec.evaluate(listOf(masses.first(), areas.last())), 0.0)
        assertEquals(spec.maximum, spec.evaluate(listOf(masses.last(), areas.first())), 0.0)

        for (mass in masses) for (area in areas) {
            val values = listOf(mass, area)
            val density = spec.evaluate(values)
            assertTrue("Density at $values: $density", density in spec.minimum..spec.maximum)
            assertEquals(mass, density * area, 1e-12)
            assertEquals(mass, spec.companionValue(values), 0.0)
        }
    }

    @Test fun densityFallsWithAreaAndRisesWithMassAcrossSliderRanges() {
        for (mass in masses) {
            assertTrue(areas.zipWithNext().all { (smaller, larger) ->
                spec.evaluate(listOf(mass, smaller)) > spec.evaluate(listOf(mass, larger))
            })
        }
        for (area in areas) {
            assertTrue(masses.zipWithNext().all { (less, more) ->
                spec.evaluate(listOf(less, area)) < spec.evaluate(listOf(more, area))
            })
        }
    }

    @Test fun doublingAreaHalvesDensityAndDoublingMassDoublesIt() {
        val initial = listOf(40.0, 8.0)
        val baseline = spec.evaluate(initial)
        val largerArea = listOf(40.0, 16.0)
        val greaterMass = listOf(80.0, 8.0)
        assertEquals(baseline / 2, spec.evaluate(largerArea), 0.0)
        assertEquals(spec.companionValue(initial), spec.companionValue(largerArea), 0.0)
        assertEquals(baseline * 2, spec.evaluate(greaterMass), 0.0)
    }
}
