package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasRenalTubuleRetentionTeachingModelTest {
    private val model = HealthAtlasRenalTubuleRetentionTeachingModel
    private val spec = model.spec

    @Test fun defaultsUsePercentControlsAndTargetOnlyTubularTissueAndRegions() {
        assertEquals(setOf("tissue-renal-tubular-epithelium", "renal-cortex", "renal-medulla"), spec.entryIds)
        assertEquals(listOf("%", "%"), spec.inputs.map { it.unit })
        assertEquals(listOf(0..80, 0..80), spec.inputs.map { it.control.range })
        assertEquals(1, spec.axis)
        assertEquals("renal-tubule-retention-segment-b", spec.inputs[spec.axis].control.key)
        assertEquals("a.u.", spec.unit)

        val defaults = spec.inputs.map { it.control.initial / it.control.scale }
        assertEquals(listOf(40.0, 25.0), defaults)
        assertEquals(45.0, spec.evaluate(defaults), EPSILON)
        assertEquals(55.0, spec.companionValue(defaults), EPSILON)
    }

    @Test fun secondSegmentReclaimsOnlyFromWhatTheFirstSegmentLeaves() {
        val amounts = model.amounts(40.0, 25.0)
        assertEquals(100.0, amounts.starting, EPSILON)
        assertEquals(40.0, amounts.reclaimedInA, EPSILON)
        assertEquals(60.0, amounts.afterA, EPSILON)
        assertEquals(15.0, amounts.reclaimedInB, EPSILON)
        assertEquals(45.0, amounts.remaining, EPSILON)

        assertEquals(25.0, model.amounts(0.0, 25.0).reclaimedInB, EPSILON)
        assertEquals(0.0, model.amounts(40.0, 0.0).reclaimedInB, EPSILON)
    }

    @Test fun cornersAndFractionalChartSamplesUseTheSameSerialBalance() {
        for ((a, b, remaining) in listOf(
            Triple(0.0, 0.0, 100.0),
            Triple(80.0, 0.0, 20.0),
            Triple(0.0, 80.0, 20.0),
            Triple(80.0, 80.0, 4.0),
            Triple(40.0, 25.5, 44.7),
        )) {
            val inputs = listOf(a, b)
            assertEquals(remaining, spec.evaluate(inputs), EPSILON)
            assertEquals(100.0 - remaining, spec.companionValue(inputs), EPSILON)
        }
    }

    @Test fun everySliderPairConservesMarkerAndBothControlsStrictlyDecreaseThePlot() {
        val (controlA, controlB) = spec.inputs.map { it.control }
        for (a in controlA.range) for (b in controlB.range) {
            val aPercent = a / controlA.scale
            val bPercent = b / controlB.scale
            val inputs = listOf(aPercent, bPercent)
            val amounts = model.amounts(aPercent, bPercent)
            val remaining = spec.evaluate(inputs)
            val reclaimed = spec.companionValue(inputs)

            assertTrue(remaining in spec.minimum..spec.maximum)
            assertTrue(reclaimed in spec.minimum..spec.maximum)
            assertTrue(amounts.afterA in remaining..amounts.starting)
            assertTrue(amounts.reclaimedInA >= 0.0 && amounts.reclaimedInB >= 0.0)
            assertEquals(amounts.starting, remaining + reclaimed, EPSILON)
            assertEquals(reclaimed, amounts.reclaimedInA + amounts.reclaimedInB, EPSILON)

            if (a < controlA.range.last) {
                assertTrue(spec.evaluate(listOf((a + 1) / controlA.scale, bPercent)) < remaining)
            }
            if (b < controlB.range.last) {
                assertTrue(spec.evaluate(listOf(aPercent, (b + 1) / controlB.scale)) < remaining)
            }
        }
    }

    private companion object {
        const val EPSILON = 1e-9
    }
}
