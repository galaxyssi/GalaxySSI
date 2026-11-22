package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasPanethLuminalReleaseTeachingModelTest {
    private val spec = HealthAtlasPanethLuminalReleaseTeachingModel.spec
    private val controls = spec.inputs.map { it.control }

    @Test fun defaultsSplitSevenIconsBetweenTheCryptLumenAndTheCellSide() {
        assertEquals(setOf("cell-paneth-cell"), spec.entryIds)
        assertEquals("paneth-luminal-release-selected", controls[spec.axis].key)
        assertEquals(listOf(0..10, 1..10), controls.map { it.range })
        assertEquals(listOf(0, 0), spec.inputs.map { it.digits })
        assertEquals(0, spec.digits)
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(10.0, spec.maximum, 0.0)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(4.0, 7.0), defaults)
        assertEquals(4.0, spec.evaluate(defaults), 0.0)
        assertEquals(3.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun transferSaturatesAtTheAvailableIconsAndPreservesTheirTotal() {
        val (selected, starting) = controls
        for (count in starting.range) {
            var previousTransfer = 0.0
            for (arrows in selected.range) {
                val values = listOf(arrows / selected.scale, count / starting.scale)
                val transferred = spec.evaluate(values)
                val remaining = spec.companionValue(values)
                assertEquals(minOf(arrows, count).toDouble(), transferred, 0.0)
                assertTrue(transferred in spec.minimum..spec.maximum && transferred >= previousTransfer)
                assertTrue(remaining in 0.0..count.toDouble())
                assertEquals(count.toDouble(), transferred + remaining, 0.0)
                previousTransfer = transferred
            }
        }

        assertEquals(spec.minimum, spec.evaluate(listOf(0.0, 10.0)), 0.0)
        assertEquals(spec.maximum, spec.evaluate(listOf(10.0, 10.0)), 0.0)
    }

    @Test fun chartSamplesRoundToWholeArrowsBeforeApplyingTheCap() {
        assertEquals(3.0, spec.evaluate(listOf(3.49, 7.0)), 0.0)
        assertEquals(4.0, spec.evaluate(listOf(3.5, 7.0)), 0.0)
        assertEquals(7.0, spec.evaluate(listOf(9.7, 7.0)), 0.0)
        assertEquals(0.0, spec.companionValue(listOf(9.7, 7.0)), 0.0)
    }
}
