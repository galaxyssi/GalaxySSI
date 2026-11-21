package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasThyroidCCellReleaseGridTeachingModelTest {
    private val spec = HealthAtlasThyroidCCellReleaseGridTeachingModel.spec
    private val controls = spec.inputs.map { it.control }

    @Test fun defaultsMoveTwoOfFiveIconsInEachOfThreeRows() {
        assertEquals(setOf("cell-thyroid-parafollicular-cell"), spec.entryIds)
        assertEquals("thyroid-c-cell-release-grid-moved", controls[spec.axis].key)
        assertEquals(listOf(0..5, 1..4), controls.map { it.range })
        assertEquals(listOf(0, 0), spec.inputs.map { it.digits })
        assertEquals(0, spec.digits)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(2.0, 3.0), defaults)
        assertEquals(6.0, spec.evaluate(defaults), 0.0)
        assertEquals(9.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun eachColumnMovedTransfersOneIconPerRowWithoutChangingTotal() {
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(20.0, spec.maximum, 0.0)
        val (movedControl, rowControl) = controls
        for (rows in rowControl.range) {
            assertEquals(spec.minimum, spec.evaluate(listOf(0.0, rows.toDouble())), 0.0)
            assertEquals(0.0, spec.companionValue(listOf(5.0, rows.toDouble())), 0.0)
            for (moved in movedControl.range) {
                val values = listOf(moved.toDouble(), rows.toDouble())
                val outside = spec.evaluate(values)
                val inside = spec.companionValue(values)
                assertTrue(outside in spec.minimum..spec.maximum && inside in 0.0..20.0)
                assertEquals(moved.toDouble() * rows, outside, 0.0)
                assertEquals(5.0 * rows, outside + inside, 0.0)
            }
        }
        assertEquals(spec.maximum, spec.evaluate(listOf(5.0, 4.0)), 0.0)
    }

    @Test fun chartSamplesDoNotSplitIcons() {
        assertEquals(6.0, spec.evaluate(listOf(2.49, 3.0)), 0.0)
        assertEquals(9.0, spec.evaluate(listOf(2.5, 3.0)), 0.0)
        assertEquals(6.0, spec.companionValue(listOf(2.5, 3.0)), 0.0)
    }
}
