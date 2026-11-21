package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasSalivaryDeliveryTeachingModelTest {
    private val spec = HealthAtlasSalivaryDeliveryTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val defaults = controls.map { it.initial }

    @Test fun defaultContributionsAndUnitsDescribeDemoFlow() {
        val values = scaled(defaults)

        assertEquals(listOf(3.0, 4.0, 1.0), values)
        assertEquals("DU/min", spec.unit)
        assertEquals(List(3) { "DU/min" }, spec.inputs.map { it.unit })
        assertEquals(0, spec.axis)
        assertEquals(8.0, spec.evaluate(values), 0.0)
        assertEquals(40.0, spec.companionValue(values), 0.0)
    }

    @Test fun allSliderCombinationsFitTheChartAndAccumulateVolume() {
        val minimum = scaled(controls.map { it.range.first })
        val maximum = scaled(controls.map { it.range.last })

        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(15.0, spec.maximum, 0.0)
        assertEquals(spec.minimum, spec.evaluate(minimum), 0.0)
        assertEquals(spec.maximum, spec.evaluate(maximum), 0.0)
        assertEquals(0.0, spec.companionValue(minimum), 0.0)
        assertEquals(75.0, spec.companionValue(maximum), 0.0)

        for (parotid in controls[0].range) {
            for (submandibular in controls[1].range) {
                for (sublingual in controls[2].range) {
                    val values = scaled(listOf(parotid, submandibular, sublingual))
                    val expected = (parotid + submandibular + sublingual) / 4.0
                    val flow = spec.evaluate(values)
                    assertTrue(flow.isFinite() && flow in spec.minimum..spec.maximum)
                    assertEquals(expected, flow, 0.0)
                    assertEquals(expected * 5.0, spec.companionValue(values), 0.0)
                }
            }
        }
    }

    @Test fun raisingAnyContributionRaisesFlowAndVolume() {
        val baseline = scaled(defaults)
        for (index in controls.indices) {
            val raised = scaled(defaults.toMutableList().apply { this[index] += 1 })
            assertEquals(0.25, spec.evaluate(raised) - spec.evaluate(baseline), 0.0)
            assertEquals(1.25, spec.companionValue(raised) - spec.companionValue(baseline), 0.0)
        }
    }

    @Test fun chartAcceptsAlreadyScaledValuesBetweenSliderTicks() {
        val values = listOf(3.125, 4.0, 1.0)
        assertEquals(8.125, spec.evaluate(values), 0.0)
        assertEquals(40.625, spec.companionValue(values), 0.0)
    }

    private fun scaled(raw: List<Int>): List<Double> =
        raw.zip(controls) { value, control -> value / control.scale }
}
