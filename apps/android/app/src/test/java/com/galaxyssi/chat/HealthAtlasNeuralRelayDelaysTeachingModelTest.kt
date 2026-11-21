package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasNeuralRelayDelaysTeachingModelTest {
    private val spec = HealthAtlasNeuralRelayDelaysTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-12

    @Test fun defaultChainAddsThreeDelaysBeforeArrival() {
        assertEquals(
            setOf("cerebrum", "cerebellum", "brainstem", "ganglia", "autonomic-nerves", "tissue-central-nervous"),
            spec.entryIds,
        )
        assertEquals(1, spec.axis)
        assertEquals(listOf("", "ms"), spec.inputs.map { it.unit })
        assertEquals("ms", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(3.0, 1.5), defaults)
        assertEquals(4.5, spec.evaluate(defaults), epsilon)
        assertEquals(3.0, spec.companionValue(defaults), epsilon)
    }

    @Test fun extremeInputsFitChartBoundsAndOneStageHasNoPriorDelay() {
        val (count, delay) = controls
        val minCount = count.range.first / count.scale
        val maxCount = count.range.last / count.scale
        val minDelay = delay.range.first / delay.scale
        val maxDelay = delay.range.last / delay.scale

        assertEquals(0.0, spec.minimum, epsilon)
        assertEquals(20.0, spec.maximum, epsilon)
        assertEquals(0.5, spec.evaluate(listOf(minCount, minDelay)), epsilon)
        assertEquals(2.5, spec.evaluate(listOf(minCount, maxDelay)), epsilon)
        assertEquals(4.0, spec.evaluate(listOf(maxCount, minDelay)), epsilon)
        assertEquals(spec.maximum, spec.evaluate(listOf(maxCount, maxDelay)), epsilon)
        assertEquals(0.0, spec.companionValue(listOf(minCount, minDelay)), epsilon)
        assertEquals(0.0, spec.companionValue(listOf(minCount, maxDelay)), epsilon)
        assertEquals(17.5, spec.companionValue(listOf(maxCount, maxDelay)), epsilon)
    }

    @Test fun chartIncreasesLinearlyForEveryStageCountBetweenSliderSteps() {
        val (count, delay) = controls
        val start = delay.range.first / delay.scale
        val end = delay.range.last / delay.scale
        for (countStep in count.range) {
            val stages = countStep / count.scale
            var previous = spec.evaluate(listOf(stages, start))
            for (sample in 1..120) {
                val delayMs = start + (end - start) * sample / 120
                val inputs = listOf(stages, delayMs)
                val total = spec.evaluate(inputs)
                assertTrue(total > previous)
                assertTrue(total in spec.minimum..spec.maximum)
                assertEquals(stages * (end - start) / 120, total - previous, epsilon)
                assertEquals(delayMs, total - spec.companionValue(inputs), epsilon)
                previous = total
            }
        }
    }

    @Test fun eachAdditionalStageAddsOneDelayAtEverySliderSetting() {
        val (count, delay) = controls
        for (delayStep in delay.range) {
            val delayMs = delayStep / delay.scale
            for (countStep in count.range.first until count.range.last) {
                val before = spec.evaluate(listOf(countStep / count.scale, delayMs))
                val after = spec.evaluate(listOf((countStep + 1) / count.scale, delayMs))
                assertEquals(delayMs, after - before, epsilon)
            }
        }
    }
}
