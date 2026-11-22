package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasScrotalHeatTallyTeachingModelTest {
    private val spec = HealthAtlasScrotalHeatTallyTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val tolerance = 1e-12

    @Test fun defaultsUseTransferShareAxisAndFictionalHeatUnits() {
        val defaults = controls.map { it.initial / it.scale }
        assertEquals(setOf("scrotum"), spec.entryIds)
        assertEquals(1, spec.axis)
        assertEquals(listOf("hu", "%"), spec.inputs.map { it.unit })
        assertEquals("hu", spec.unit)
        assertEquals(listOf(12.0, 40.0), defaults)
        assertEquals(4.8, spec.evaluate(defaults), tolerance)
        assertEquals(7.2, spec.companionValue(defaults), tolerance)
    }

    @Test fun transferIsBoundedAndConservesTheExampleSurplus() {
        val (surplusControl, shareControl) = controls
        assertEquals(0..20, surplusControl.range)
        assertEquals(0..100, shareControl.range)
        assertEquals(0.0, spec.minimum, tolerance)
        assertEquals(20.0, spec.maximum, tolerance)
        assertEquals(0.0, spec.evaluate(listOf(20.0, 0.0)), tolerance)
        assertEquals(20.0, spec.companionValue(listOf(20.0, 0.0)), tolerance)
        assertEquals(20.0, spec.evaluate(listOf(20.0, 100.0)), tolerance)
        assertEquals(0.0, spec.companionValue(listOf(20.0, 100.0)), tolerance)

        for (surplusStep in surplusControl.range) {
            val surplus = surplusStep / surplusControl.scale
            var previousTransfer = 0.0
            for (shareStep in shareControl.range) {
                val values = listOf(surplus, shareStep / shareControl.scale)
                val transfer = spec.evaluate(values)
                val left = spec.companionValue(values)
                assertTrue(transfer in spec.minimum..surplus)
                assertTrue(left in 0.0..surplus)
                assertEquals(surplus, transfer + left, tolerance)
                if (surplus > 0.0 && shareStep > shareControl.range.first) {
                    assertTrue(transfer > previousTransfer)
                }
                previousTransfer = transfer
            }
        }
    }
}
