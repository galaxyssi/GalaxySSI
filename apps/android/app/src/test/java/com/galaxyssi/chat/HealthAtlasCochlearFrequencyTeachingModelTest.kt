package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasCochlearFrequencyTeachingModelTest {
    private val spec = HealthAtlasCochlearFrequencyTeachingModel.spec
    private val input = spec.inputs.single()
    private val control = input.control

    private fun at(step: Int) = listOf(step / control.scale)

    @Test fun defaultUsesNormalizedPositionAndReturnsHertz() {
        assertEquals(0, spec.axis)
        assertEquals("", input.unit)
        assertEquals(2, input.digits)
        assertEquals("Hz", spec.unit)
        assertEquals(listOf(0.5), at(control.initial))
        assertEquals(1_710.2665234, spec.evaluate(at(control.initial)), 1e-6)
        assertEquals(50.0, spec.companionValue(at(control.initial)), 1e-9)
        assertEquals(setOf("cochlea", "inner-ear", "cell-inner-ear-hair-cell"), spec.entryIds)
    }

    @Test fun apexQuarterPositionAndBaseMatchGreenwoodInHertz() {
        assertEquals(0..100, control.range)
        assertEquals(100.0, control.scale, 0.0)
        assertEquals(19.848, spec.evaluate(at(control.range.first)), 1e-6)
        assertEquals(408.4808364, spec.evaluate(at(25)), 1e-6)
        assertEquals(20_677.0743111, spec.evaluate(at(control.range.last)), 1e-6)
        assertEquals(100.0, spec.companionValue(at(control.range.first)), 1e-9)
        assertEquals(75.0, spec.companionValue(at(25)), 1e-9)
        assertEquals(0.0, spec.companionValue(at(control.range.last)), 1e-9)
    }

    @Test fun everySliderStopFitsTheChartAndFrequencyRisesTowardTheBase() {
        assertTrue(spec.minimum.isFinite() && spec.maximum.isFinite() && spec.minimum < spec.maximum)
        var previousHz = Double.NEGATIVE_INFINITY
        var previousFromBase = Double.POSITIVE_INFINITY
        for (step in control.range) {
            val hz = spec.evaluate(at(step))
            val fromBase = spec.companionValue(at(step))
            assertTrue(hz in spec.minimum..spec.maximum && hz > previousHz)
            assertTrue(fromBase in 0.0..100.0 && fromBase < previousFromBase)
            previousHz = hz
            previousFromBase = fromBase
        }
    }
}
