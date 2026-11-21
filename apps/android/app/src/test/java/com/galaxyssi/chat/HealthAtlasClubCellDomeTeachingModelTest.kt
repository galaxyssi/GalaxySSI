package com.galaxyssi.chat

import kotlin.math.PI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasClubCellDomeTeachingModelTest {
    private val spec = HealthAtlasClubCellDomeTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val tolerance = 1e-12

    @Test fun defaultsDescribeOnlyTheClubCellDomeProfile() {
        assertEquals(setOf("cell-club-cell"), spec.entryIds)
        assertEquals("club-cell-dome-rise", controls[spec.axis].key)
        assertEquals(listOf("u", "u"), spec.inputs.map { it.unit })
        assertEquals("%", spec.unit)
        assertEquals(listOf(5..30, 30..60), controls.map { it.range })
        assertEquals(listOf(10.0, 10.0), controls.map { it.scale })

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(1.5, 4.0), defaults)
        assertEquals(1.5 * PI, spec.companionValue(defaults), tolerance)
        assertEquals(150.0 * PI / (16.0 + 1.5 * PI), spec.evaluate(defaults), tolerance)
    }

    @Test fun domeShareIncreasesWithRiseAndDecreasesWithBodyHeight() {
        val (rise, body) = controls
        val smallestShare = spec.evaluate(listOf(0.5, 6.0))
        val largestShare = spec.evaluate(listOf(3.0, 3.0))
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(50.0, spec.maximum, 0.0)
        assertEquals(50.0 * PI / (24.0 + 0.5 * PI), smallestShare, tolerance)
        assertEquals(300.0 * PI / (12.0 + 3.0 * PI), largestShare, tolerance)

        for (bodyStep in body.range) {
            val height = bodyStep / body.scale
            var previousShare = spec.minimum
            for (riseStep in rise.range) {
                val domeRise = riseStep / rise.scale
                val values = listOf(domeRise, height)
                val share = spec.evaluate(values)
                val area = spec.companionValue(values)
                assertTrue(share in spec.minimum..spec.maximum && share > previousShare)
                assertEquals(PI * domeRise, area, tolerance)
                assertEquals(area, (area + 4.0 * height) * share / 100.0, tolerance)
                if (bodyStep < body.range.last) {
                    val tallerBody = listOf(domeRise, (bodyStep + 1) / body.scale)
                    assertTrue(spec.evaluate(tallerBody) < share)
                    assertEquals(area, spec.companionValue(tallerBody), 0.0)
                }
                previousShare = share
            }
        }
    }
}
