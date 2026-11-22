package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasLymphParticleTransportTeachingModelTest {
    private val spec = HealthAtlasLymphParticleTransportTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-12

    @Test fun defaultStreamCarriesSixMicrogramsPerMinute() {
        assertEquals(setOf("lymph-nodes", "thoracic-duct", "cell-lymphatic-endothelial-cell"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("mL/min", "\u00b5g/mL"), spec.inputs.map { it.unit })
        assertEquals("\u00b5g/min", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(2.0, 3.0), defaults)
        assertEquals(6.0, spec.evaluate(defaults), epsilon)
        assertEquals(30.0, spec.companionValue(defaults), epsilon)
    }

    @Test fun zeroFlowOrDyeGivesZeroAndMaximumInputsReachChartCeiling() {
        val (maxFlow, maxConcentration) = controls.map { it.range.last / it.scale }
        for (values in listOf(listOf(0.0, 0.0), listOf(maxFlow, 0.0), listOf(0.0, maxConcentration))) {
            assertEquals(0.0, spec.evaluate(values), epsilon)
            assertEquals(0.0, spec.companionValue(values), epsilon)
        }
        val maximum = listOf(maxFlow, maxConcentration)
        assertEquals(30.0, spec.evaluate(maximum), epsilon)
        assertEquals(spec.maximum, spec.evaluate(maximum), epsilon)
        assertEquals(150.0, spec.companionValue(maximum), epsilon)
    }

    @Test fun rateRisesWithEitherInputWhenTheOtherIsPositive() {
        val (flowControl, concentrationControl) = controls
        for (flowStep in flowControl.range) {
            for (concentrationStep in concentrationControl.range) {
                val flow = flowStep / flowControl.scale
                val concentration = concentrationStep / concentrationControl.scale
                val values = listOf(flow, concentration)
                val rate = spec.evaluate(values)
                assertTrue(rate.isFinite() && rate in spec.minimum..spec.maximum)
                assertEquals(concentration * (flow * 5.0), spec.companionValue(values), epsilon)
                if (flowStep > flowControl.range.first) {
                    val previousFlow = (flowStep - 1) / flowControl.scale
                    val previous = spec.evaluate(listOf(previousFlow, concentration))
                    if (concentration == 0.0) assertEquals(previous, rate, epsilon)
                    else assertTrue(rate > previous)
                }
                if (concentrationStep > concentrationControl.range.first) {
                    val previousConcentration = (concentrationStep - 1) / concentrationControl.scale
                    val previous = spec.evaluate(listOf(flow, previousConcentration))
                    if (flow == 0.0) assertEquals(previous, rate, epsilon)
                    else assertTrue(rate > previous)
                }
            }
        }
    }
}
