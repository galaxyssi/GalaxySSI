package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasStromalMatrixTeachingModelTest {
    private val spec = HealthAtlasStromalMatrixTeachingModel.spec
    private val controls = spec.inputs.map { it.control }

    @Test fun defaultsShowTotalAndInitialMassPerArea() {
        assertEquals(setOf("cell-fibroblast", "cell-endometrial-stromal-cell", "endometrium"), spec.entryIds)
        assertEquals(listOf("stromal-matrix-added-mass", "stromal-matrix-initial-mass"), controls.map { it.key })
        assertEquals(0, spec.axis)
        assertEquals(listOf("MU", "MU"), spec.inputs.map { it.unit })
        assertEquals("MU/AU", spec.unit)
        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(6.0, 12.0), defaults)
        assertEquals(9.0, spec.evaluate(defaults), 0.0)
        assertEquals(6.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun sliderEndpointsMatchChartBounds() {
        val (added, initial) = controls
        assertEquals(0..20, added.range)
        assertEquals(0..40, initial.range)
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(30.0, spec.maximum, 0.0)
        val low = controls.map { it.range.first / it.scale }
        val high = controls.map { it.range.last / it.scale }
        assertEquals(spec.minimum, spec.evaluate(low), 0.0)
        assertEquals(0.0, spec.companionValue(low), 0.0)
        assertEquals(spec.maximum, spec.evaluate(high), 0.0)
        assertEquals(20.0, spec.companionValue(high), 0.0)
    }

    @Test fun chartRisesWithAddedMassWhileInitialDensityStaysFixed() {
        val (added, initial) = controls
        for (initialStep in initial.range) {
            val initialMass = initialStep / initial.scale
            val baseline = spec.companionValue(listOf(0.0, initialMass))
            assertEquals(baseline, spec.evaluate(listOf(0.0, initialMass)), 0.0)
            var previous = Double.NEGATIVE_INFINITY
            for (halfStep in (2 * added.range.first)..(2 * added.range.last)) {
                val addedMass = halfStep / (2 * added.scale)
                val values = listOf(addedMass, initialMass)
                val total = spec.evaluate(values)
                assertTrue(total in spec.minimum..spec.maximum)
                assertTrue(total > previous)
                assertEquals(addedMass / 2.0, total - baseline, 0.0)
                assertEquals(baseline, spec.companionValue(values), 0.0)
                previous = total
            }
        }
    }

    @Test fun moreInitialMassRaisesBothDensitiesEquallyAtFixedAddition() {
        val (added, initial) = controls
        val fixedAddition = added.initial / added.scale
        for (step in initial.range.first until initial.range.last) {
            val low = listOf(fixedAddition, step / initial.scale)
            val high = listOf(fixedAddition, (step + 1) / initial.scale)
            assertEquals(0.5, spec.evaluate(high) - spec.evaluate(low), 0.0)
            assertEquals(0.5, spec.companionValue(high) - spec.companionValue(low), 0.0)
        }
    }
}
