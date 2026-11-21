package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasImmuneCompositionTeachingModelTest {
    private val spec = HealthAtlasImmuneCompositionTeachingModel.spec
    private val controls = spec.inputs.map { it.control }

    @Test fun defaultsReportSelectedAndOtherCountsForTheExactEntries() {
        assertEquals(
            setOf(
                "immune",
                "cell-neutrophil",
                "cell-eosinophil",
                "cell-basophil",
                "cell-monocyte",
                "cell-t-cell",
                "cell-b-cell",
                "cell-natural-killer-cell",
            ),
            spec.entryIds,
        )
        assertEquals(1, spec.axis)
        assertEquals(listOf("cells", "%"), spec.inputs.map { it.unit })
        assertEquals("cells", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(200.0, 25.0), defaults)
        assertEquals(50.0, spec.evaluate(defaults), 0.0)
        assertEquals(150.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun theSameFractionCanGiveDifferentCountsAndTheSameCountCanGiveDifferentFractions() {
        val smallerSample = listOf(100.0, 50.0)
        val largerSample = listOf(200.0, 50.0)
        assertEquals(50.0, spec.evaluate(smallerSample), 0.0)
        assertEquals(100.0, spec.evaluate(largerSample), 0.0)
        assertEquals(50.0, spec.evaluate(listOf(200.0, 25.0)), 0.0)
    }

    @Test fun allSliderCombinationsGiveWholeCountsThatPartitionTheSampleAndFitTheChart() {
        val (size, percent) = controls
        for (sizeStep in size.range) {
            val sampleSize = sizeStep / size.scale
            for (percentStep in percent.range) {
                val percentage = percentStep / percent.scale
                val inputs = listOf(sampleSize, percentage)
                val selected = spec.evaluate(inputs)
                val other = spec.companionValue(inputs)
                assertTrue("Selected count outside chart at $inputs", selected in spec.minimum..spec.maximum)
                assertTrue("Other count invalid at $inputs", other in 0.0..sampleSize)
                assertEquals(sampleSize, selected + other, 0.0)
                assertEquals(percentage, 100.0 * selected / sampleSize, 0.0)
                assertEquals(selected.toInt().toDouble(), selected, 0.0)
                assertEquals(other.toInt().toDouble(), other, 0.0)
            }
        }
        assertEquals(0.0, spec.evaluate(listOf(500.0, 0.0)), 0.0)
        assertEquals(500.0, spec.evaluate(listOf(500.0, 100.0)), 0.0)
    }
}
