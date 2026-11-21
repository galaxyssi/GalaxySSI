package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasBiliaryFlowTallyTeachingModelTest {
    private val spec = HealthAtlasBiliaryFlowTallyTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val flowControl = controls[0]
    private val channelControl = controls[1]

    @Test fun defaultsShowMergedFlowAndVolume() {
        val defaults = controls.map { it.initial / it.scale }

        assertEquals(setOf("liver", "biliary-tract", "cell-hepatocyte", "cell-cholangiocyte"), spec.entryIds)
        assertEquals("biliary-flow-tally-per-channel", controls[spec.axis].key)
        assertEquals(listOf("VU/min", ""), spec.inputs.map { it.unit })
        assertEquals("VU/min", spec.unit)
        assertEquals(listOf(2.5, 4.0), defaults)
        assertEquals(10.0, spec.evaluate(defaults), 0.0)
        assertEquals(40.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun extremesAndAllSliderSettingsConserveVolumeWithinBounds() {
        val lowFlow = flowControl.range.first / flowControl.scale
        val highFlow = flowControl.range.last / flowControl.scale
        val fewChannels = channelControl.range.first / channelControl.scale
        val manyChannels = channelControl.range.last / channelControl.scale
        val zeroInput = listOf(lowFlow, manyChannels)
        val peakInput = listOf(highFlow, manyChannels)

        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(48.0, spec.maximum, 0.0)
        assertEquals(spec.minimum, spec.evaluate(zeroInput), 0.0)
        assertEquals(0.0, spec.companionValue(zeroInput), 0.0)
        assertEquals(6.0, spec.evaluate(listOf(highFlow, fewChannels)), 0.0)
        assertEquals(spec.maximum, spec.evaluate(peakInput), 0.0)
        assertEquals(192.0, spec.companionValue(peakInput), 0.0)

        for (channels in channelControl.range) {
            for (flowStep in flowControl.range) {
                val perChannel = flowStep / flowControl.scale
                val values = listOf(perChannel, channels / channelControl.scale)
                val outflow = spec.evaluate(values)
                assertTrue(outflow.isFinite() && outflow in spec.minimum..spec.maximum)
                assertEquals(List(channels) { perChannel }.sum(), outflow, 0.0)
                assertEquals(outflow * 4.0, spec.companionValue(values), 0.0)
            }
        }
    }

    @Test fun chartRisesWithPerChannelFlowAtEveryChannelCount() {
        for (channels in channelControl.range) {
            val outflows = flowControl.range.map { flowStep ->
                spec.evaluate(listOf(flowStep / flowControl.scale, channels / channelControl.scale))
            }
            assertTrue(outflows.zipWithNext().all { (before, after) -> after > before })
        }

        assertEquals(10.5, spec.evaluate(listOf(2.625, 4.0)), 0.0)
    }

    @Test fun addingAChannelAddsExactlyItsOwnFlow() {
        for (flowStep in flowControl.range) {
            val perChannel = flowStep / flowControl.scale
            val outflows = channelControl.range.map { channels ->
                spec.evaluate(listOf(perChannel, channels / channelControl.scale))
            }
            outflows.zipWithNext().forEach { (before, after) ->
                assertEquals(perChannel, after - before, 0.0)
            }
        }
    }
}
