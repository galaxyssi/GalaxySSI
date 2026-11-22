package com.galaxyssi.chat

import kotlin.math.ln
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasGlialCapacitanceTeachingModelTest {
    private val spec = HealthAtlasGlialCapacitanceTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val sliderValues = controls.map { control -> control.range.map { it / control.scale } }

    @Test fun defaultsAreTheSyntheticReference() {
        assertEquals(setOf("cell-schwann-cell", "cell-oligodendrocyte"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals("\u00d7", spec.unit)
        assertEquals(List(2) { spec.unit }, spec.inputs.map { it.unit })

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(1.0, 1.0), defaults)
        assertEquals(1.0, spec.evaluate(defaults), 0.0)
        assertEquals(1.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun chartContainsBothExtremesAndEverySliderPair() {
        val (thicknesses, areas) = sliderValues
        assertEquals(listOf(0.5, 0.5), sliderValues.map { it.first() })
        assertEquals(listOf(2.0, 2.0), sliderValues.map { it.last() })
        assertEquals(
            0.5 * ln(1.5) / ln(2.0),
            spec.evaluate(listOf(thicknesses.last(), areas.first())),
            1e-9,
        )
        assertEquals(
            2.0 * ln(1.5) / ln(1.25),
            spec.evaluate(listOf(thicknesses.first(), areas.last())),
            1e-9,
        )
        for (thickness in thicknesses) for (area in areas) {
            val inputs = listOf(thickness, area)
            val capacitance = spec.evaluate(inputs)
            assertTrue("Capacitance at $inputs: $capacitance", capacitance in spec.minimum..spec.maximum)
            assertEquals(capacitance / area, spec.companionValue(inputs), 1e-9)
        }
    }

    @Test fun graphFallsWithThicknessAtEveryArea() {
        val (thicknesses, areas) = sliderValues
        for (area in areas) {
            val curve = thicknesses.map { spec.evaluate(listOf(it, area)) }
            assertTrue(curve.zipWithNext().all { (left, right) -> left > right })
        }
    }

    @Test fun increasingAreaRaisesTotalButNotPerAreaCapacitance() {
        val (thicknesses, areas) = sliderValues
        for (thickness in thicknesses) {
            val smaller = listOf(thickness, areas.first())
            val larger = listOf(thickness, areas.last())
            assertEquals(4.0 * spec.evaluate(smaller), spec.evaluate(larger), 1e-9)
            assertEquals(spec.companionValue(smaller), spec.companionValue(larger), 0.0)
        }
    }
}
