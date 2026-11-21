package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasGlomerularFiltrationTeachingModelTest {
    private val spec = HealthAtlasGlomerularFiltrationTeachingModel.spec
    private val defaults = spec.inputs.map { it.control.initial / it.control.scale }

    @Test fun defaultsUseDisplayedUnitsAndOnlyTargetTheFiltrationBarrier() {
        assertEquals(listOf(52.0, 12.0, 28.0, 2.5), defaults)
        assertEquals(listOf("mmHg", "mmHg", "mmHg", "nL/(min\u00b7mmHg)"), spec.inputs.map { it.unit })
        assertEquals("nL/min", spec.unit)
        assertEquals(0, spec.axis)
        assertEquals(setOf("glomerulus", "bowmans-capsule", "cell-podocyte"), spec.entryIds)
        assertEquals(12.0, spec.companionValue(defaults), 0.0)
        assertEquals(30.0, spec.evaluate(defaults), 0.0)
    }

    @Test fun onlyPositiveNetPressureProducesForwardFiltration() {
        for ((capillary, netPressure, flow) in listOf(
            Triple(40.0, -1.0, 0.0),
            Triple(41.0, 0.0, 0.0),
            Triple(41.5, 0.5, 1.25),
        )) {
            val inputs = listOf(capillary, 13.0, 28.0, 2.5)
            assertEquals(netPressure, spec.companionValue(inputs), 0.0)
            assertEquals(flow, spec.evaluate(inputs), 0.0)
        }
    }

    @Test fun changingEachControlIndependentlyHasTheExpectedEffect() {
        val expected = listOf(
            Triple(53.0, 13.0, 32.5),
            Triple(13.0, 11.0, 27.5),
            Triple(29.0, 11.0, 27.5),
            Triple(2.6, 12.0, 31.2),
        )
        expected.forEachIndexed { index, (changed, netPressure, flow) ->
            val inputs = defaults.toMutableList().apply { this[index] = changed }
            assertEquals(netPressure, spec.companionValue(inputs), 0.0)
            assertEquals(flow, spec.evaluate(inputs), 1e-12)
        }
    }

    @Test fun everySliderCombinationIsFiniteAndFitsTheChart() {
        val (capillary, capsule, oncotic, coefficient) = spec.inputs.map { it.control }
        val highest = listOf(capillary.range.last / capillary.scale, capsule.range.first / capsule.scale,
            oncotic.range.first / oncotic.scale, coefficient.range.last / coefficient.scale)
        val lowest = listOf(capillary.range.first / capillary.scale, capsule.range.last / capsule.scale,
            oncotic.range.last / oncotic.scale, coefficient.range.first / coefficient.scale)
        assertEquals(39.0, spec.companionValue(highest), 0.0)
        assertEquals(195.0, spec.evaluate(highest), 0.0)
        assertEquals(-15.0, spec.companionValue(lowest), 0.0)
        assertEquals(0.0, spec.evaluate(lowest), 0.0)

        for (pc in capillary.range) for (pb in capsule.range)
            for (pi in oncotic.range) for (kf in coefficient.range) {
                val inputs = listOf(pc / capillary.scale, pb / capsule.scale,
                    pi / oncotic.scale, kf / coefficient.scale)
                assertTrue(spec.evaluate(inputs) in spec.minimum..spec.maximum)
                assertTrue(spec.companionValue(inputs) in -15.0..39.0)
            }
    }
}
