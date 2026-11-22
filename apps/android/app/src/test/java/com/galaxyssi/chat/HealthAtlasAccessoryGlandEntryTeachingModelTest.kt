package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasAccessoryGlandEntryTeachingModelTest {
    private val spec = HealthAtlasAccessoryGlandEntryTeachingModel.spec
    private val controls = spec.inputs.map { it.control }

    @Test fun defaultsCountMarkersAtTheirOwnEntrySites() {
        assertEquals(setOf("seminal-vesicles", "prostate", "bulbourethral-glands"), spec.entryIds)
        assertEquals("accessory-gland-entry-vesicle-markers", controls[spec.axis].key)
        assertEquals(listOf(0..4, 0..4, 0..4), controls.map { it.range })
        assertEquals(listOf(0, 0, 0), spec.inputs.map { it.digits })
        assertEquals(0, spec.digits)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(3.0, 2.0, 1.0), defaults)
        assertEquals(5.0, spec.evaluate(defaults), 0.0)
        assertEquals(1.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun bothEntryTalliesReachTheirBoundsIndependently() {
        val spongyOnly = listOf(0.0, 0.0, 4.0)
        val prostaticOnly = listOf(4.0, 4.0, 0.0)
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(8.0, spec.maximum, 0.0)
        assertEquals(spec.minimum, spec.evaluate(spongyOnly), 0.0)
        assertEquals(4.0, spec.companionValue(spongyOnly), 0.0)
        assertEquals(spec.maximum, spec.evaluate(prostaticOnly), 0.0)
        assertEquals(0.0, spec.companionValue(prostaticOnly), 0.0)
    }

    @Test fun eachMarkerIsCountedOnceAtItsFirstEntryAcrossTheControlRanges() {
        val (vesicles, prostate, bulbourethral) = controls
        for (v in vesicles.range) {
            for (p in prostate.range) {
                for (b in bulbourethral.range) {
                    val values = listOf(v / vesicles.scale, p / prostate.scale, b / bulbourethral.scale)
                    val prostaticEntry = spec.evaluate(values)
                    val spongyEntry = spec.companionValue(values)
                    assertEquals((v + p).toDouble(), prostaticEntry, 0.0)
                    assertEquals(b.toDouble(), spongyEntry, 0.0)
                    assertTrue(prostaticEntry in spec.minimum..spec.maximum)
                    assertTrue(spongyEntry in 0.0..4.0)
                    assertEquals(values.sum(), prostaticEntry + spongyEntry, 0.0)
                }
            }
        }
    }

    @Test fun interpolatedChartSamplesStayWholeAndNondecreasing() {
        val samples = (0..40).map { spec.evaluate(listOf(it / 10.0, 2.0, 1.0)) }
        assertTrue(samples.all { it in 2.0..6.0 && it == it.toInt().toDouble() })
        assertTrue(samples.zipWithNext().all { (before, after) -> before <= after })
        assertEquals(2.0, spec.evaluate(listOf(0.49, 2.0, 1.0)), 0.0)
        assertEquals(3.0, spec.evaluate(listOf(0.5, 2.0, 1.0)), 0.0)
    }
}
