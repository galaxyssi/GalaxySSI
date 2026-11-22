package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasVocalCycleTeachingModelTest {
    private val kind = HealthAtlasPhysiologyKind.VOCAL_CYCLES

    @Test fun timeWindowAndFrequencyProduceConsistentCycleCount() {
        val model = HealthAtlasPhysiology(kind)
        assertEquals(2.8, model.result, 1e-9)
        assertEquals(1000.0 / 140, model.companionValue, 1e-9)
        for (frequency in kind.inputs[0].range) for (window in kind.inputs[1].range) {
            val example = model.withInput(0, frequency).withInput(1, window)
            assertEquals(window.toDouble(), example.result * example.companionValue, 1e-9)
            assertTrue(example.result in kind.minimum..kind.maximum)
        }
        assertEquals(setOf("larynx"), kind.teaching?.entryIds)
    }

    @Test fun animatedOpeningAndWaveformShareTheSameOscillation() {
        val open = HealthAtlasVocalCycleTeachingModel::relativeOpening
        for (cycles in listOf(1.0, 2.0, 3.0, 7.2)) {
            assertEquals(0f, open(cycles, 0f), 1e-6f)
            assertEquals(1f, open(cycles, (.5 / cycles).toFloat()), 1e-6f)
            assertEquals(0f, open(cycles, (1 / cycles).toFloat()), 1e-6f)
            for (at in 0..120) assertTrue(open(cycles, at / 120f) in 0f..1f)
        }
        assertTrue(open(2.8, 1f) > 0f)
    }
}
