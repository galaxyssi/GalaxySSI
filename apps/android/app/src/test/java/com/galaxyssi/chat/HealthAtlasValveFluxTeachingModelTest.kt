package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasValveFluxTeachingModelTest {
    private val spec = HealthAtlasValveFluxTeachingModel.spec

    @Test fun defaultsUseScaledAreaAndReportFlowAndSteadyVolume() {
        val defaults = spec.inputs.map { it.control.initial / it.control.scale }
        assertEquals(listOf(2.5, 50.0), defaults)
        assertEquals(listOf("cm\u00b2", "cm/s"), spec.inputs.map { it.unit })
        assertEquals("mL/s", spec.unit)
        assertEquals(125.0, spec.evaluate(defaults), 1e-9)
        assertEquals(12.5, spec.companionValue(defaults), 1e-9)
        assertEquals(1, spec.axis)
    }

    @Test fun everySliderPairFitsTheChartAndMatchesTheFormula() {
        val areaControl = spec.inputs[0].control
        val speedControl = spec.inputs[1].control
        assertEquals(10..50, areaControl.range)
        assertEquals(0..100, speedControl.range)
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(500.0, spec.maximum, 0.0)
        for (areaStep in areaControl.range) for (speedStep in speedControl.range) {
            val area = areaStep / areaControl.scale
            val speed = speedStep / speedControl.scale
            val inputs = listOf(area, speed)
            val flow = spec.evaluate(inputs)
            assertTrue("area=$area, speed=$speed, flow=$flow", flow in spec.minimum..spec.maximum)
            assertEquals(area * speed, flow, 1e-9)
            assertEquals(area * speed / 10.0, spec.companionValue(inputs), 1e-9)
        }
        assertEquals(spec.minimum, spec.evaluate(listOf(5.0, 0.0)), 0.0)
        assertEquals(spec.maximum, spec.evaluate(listOf(5.0, 100.0)), 0.0)
        assertEquals(50.0, spec.companionValue(listOf(5.0, 100.0)), 1e-9)
    }

    @Test fun flowIncreasesWithSpeedAndWithAreaAtPositiveSpeed() {
        val flow = spec.evaluate(listOf(1.5, 30.0))
        assertEquals(45.0, flow, 1e-9)
        assertEquals(2 * flow, spec.evaluate(listOf(3.0, 30.0)), 1e-9)
        assertEquals(2 * flow, spec.evaluate(listOf(1.5, 60.0)), 1e-9)
        assertEquals(0.0, spec.evaluate(listOf(1.5, 0.0)), 0.0)
        assertEquals(0.0, spec.companionValue(listOf(1.5, 0.0)), 0.0)
    }

    @Test fun modelTargetsOnlyTheHeartValveEntries() {
        assertEquals(
            setOf("heart-valves", "tricuspid-valve", "mitral-valve", "pulmonary-valve", "aortic-valve"),
            spec.entryIds,
        )
    }
}
