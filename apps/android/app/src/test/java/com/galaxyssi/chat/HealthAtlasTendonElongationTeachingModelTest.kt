package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasTendonElongationTeachingModelTest {
    private val spec = HealthAtlasTendonElongationTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val defaults = controls.map { it.initial / it.scale }
    private val tolerance = 1e-12

    @Test fun defaultsUseScaledMetricUnitsAndForceAxis() {
        assertEquals(listOf("N", "mm", "mm\u00b2", "N/mm\u00b2"), spec.inputs.map { it.unit })
        assertEquals("mm", spec.unit)
        assertEquals(0, spec.axis)
        assertEquals(listOf(6.0, 50.0, 4.0, 750.0), defaults)
        assertEquals(0.1, spec.evaluate(defaults), tolerance)
        assertEquals(0.2, spec.companionValue(defaults), tolerance)
        assertEquals(
            setOf("tendons", "ligaments", "tissue-dense-regular-connective", "cell-tenocyte"),
            spec.entryIds,
        )
    }

    @Test fun fractionalAreaProducesElongationInMillimetersAndStrainInPercent() {
        val values = listOf(9.0, 70.0, 4.5, 800.0)
        assertEquals(0.175, spec.evaluate(values), tolerance)
        assertEquals(0.25, spec.companionValue(values), tolerance)
        assertEquals(100.0 * spec.evaluate(values) / values[1], spec.companionValue(values), tolerance)
    }

    @Test fun elongationIsProportionalToForceAndLengthAndInverseToAreaAndModulus() {
        val elongation = spec.evaluate(defaults)
        val strain = spec.companionValue(defaults)
        for ((index, factor) in listOf(2.0, 1.5, 1.5, 4.0 / 3.0).withIndex()) {
            val values = defaults.toMutableList().apply { this[index] *= factor }
            val elongationFactor = if (index < 2) factor else 1.0 / factor
            val strainFactor = if (index == 1) 1.0 else elongationFactor
            assertEquals(elongation * elongationFactor, spec.evaluate(values), tolerance)
            assertEquals(strain * strainFactor, spec.companionValue(values), tolerance)
        }
    }

    @Test fun sliderCornersFitChartAndStayAtLowSyntheticStrain() {
        val edges = controls.map { control ->
            assertTrue(control.scale.isFinite() && control.scale > 0.0)
            assertTrue(control.initial in control.range)
            listOf(control.range.first / control.scale, control.range.last / control.scale)
        }
        assertEquals(
            listOf(listOf(0.0, 12.0), listOf(20.0, 80.0), listOf(3.0, 6.0), listOf(500.0, 1000.0)),
            edges,
        )
        assertEquals(0.0, spec.minimum, tolerance)
        assertTrue(spec.maximum.isFinite())
        for (force in edges[0]) for (length in edges[1]) {
            for (area in edges[2]) for (modulus in edges[3]) {
                val values = listOf(force, length, area, modulus)
                val elongation = spec.evaluate(values)
                val strain = spec.companionValue(values)
                assertTrue(elongation in spec.minimum..spec.maximum)
                assertTrue(strain in 0.0..0.8)
                if (force == 0.0) {
                    assertEquals(0.0, elongation, tolerance)
                    assertEquals(0.0, strain, tolerance)
                }
            }
        }
        val peak = listOf(edges[0].last(), edges[1].last(), edges[2].first(), edges[3].first())
        assertEquals(0.64, spec.evaluate(peak), tolerance)
        assertEquals(0.8, spec.companionValue(peak), tolerance)
    }
}
