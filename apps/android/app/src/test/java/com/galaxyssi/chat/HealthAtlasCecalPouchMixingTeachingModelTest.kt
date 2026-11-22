package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasCecalPouchMixingTeachingModelTest {
    private val spec = HealthAtlasCecalPouchMixingTeachingModel.spec
    private val controls = spec.inputs.map { it.control }

    @Test fun defaultsShowLocalMixingAtFixedTotalMarkerAmount() {
        assertEquals(setOf("cecum"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf(0..6, 0..16), controls.map { it.range })
        assertEquals(listOf("", "u"), spec.inputs.map { it.unit })
        assertEquals("u", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(3.0, 12.0), defaults)
        assertEquals(5.25, spec.evaluate(defaults), 0.0)
        assertEquals(6.75, spec.companionValue(defaults), 0.0)
    }

    @Test fun zeroAndUpperBoundStayWithinTheHalfBatchPlotScale() {
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(8.0, spec.maximum, 0.0)
        assertEquals(0.0, spec.evaluate(listOf(0.0, 16.0)), 0.0)
        assertEquals(16.0, spec.companionValue(listOf(0.0, 16.0)), 0.0)
        assertEquals(0.0, spec.evaluate(listOf(6.0, 0.0)), 0.0)
        assertEquals(0.0, spec.companionValue(listOf(6.0, 0.0)), 0.0)
        assertEquals(7.875, spec.evaluate(listOf(6.0, 16.0)), 0.0)
        assertEquals(8.125, spec.companionValue(listOf(6.0, 16.0)), 0.0)
    }

    @Test fun eachWholeRoundConservesMarkersAndHalvesTheZoneDifference() {
        for (amountStep in controls[1].range) {
            val amount = amountStep / controls[1].scale
            var previousDifference = amount
            var previousFar = 0.0
            for (round in controls[0].range.drop(1)) {
                val values = listOf(round / controls[0].scale, amount)
                val far = spec.evaluate(values)
                val near = spec.companionValue(values)
                assertEquals(amount, near + far, 0.0)
                assertEquals(previousDifference / 2.0, near - far, 0.0)
                assertTrue(far in previousFar..(amount / 2.0))
                assertTrue(far in spec.minimum..spec.maximum)
                previousDifference = near - far
                previousFar = far
            }
        }
    }

    @Test fun fractionalChartSamplesUseTheNearestWholeRound() {
        assertEquals(0.0, spec.evaluate(listOf(0.49, 12.0)), 0.0)
        assertEquals(3.0, spec.evaluate(listOf(0.5, 12.0)), 0.0)
        assertEquals(9.0, spec.companionValue(listOf(1.49, 12.0)), 0.0)
        assertEquals(7.5, spec.companionValue(listOf(1.5, 12.0)), 0.0)
    }
}
