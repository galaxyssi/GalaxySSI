package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasLangerhansDendriteReachTeachingModelTest {
    private val spec = HealthAtlasLangerhansDendriteReachTeachingModel.spec
    private val controls = spec.inputs.map { it.control }

    @Test fun defaultsReachAllTenSpacesWithOneSharedSpace() {
        assertEquals(setOf("cell-langerhans-cell"), spec.entryIds)
        assertEquals("langerhans-dendrite-reach-left", controls[spec.axis].key)
        assertEquals(listOf(0..8, 0..8), controls.map { it.range })
        assertEquals(listOf(0, 0), spec.inputs.map { it.digits })
        assertEquals(0, spec.digits)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(6.0, 5.0), defaults)
        assertEquals(10.0, spec.evaluate(defaults), 0.0)
        assertEquals(1.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun coverageAndOverlapMatchTheUnionAndIntersectionOfNumberedSpaces() {
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(10.0, spec.maximum, 0.0)
        assertEquals(spec.minimum, spec.evaluate(listOf(0.0, 0.0)), 0.0)
        assertEquals(spec.maximum, spec.evaluate(listOf(8.0, 8.0)), 0.0)
        assertEquals(6.0, spec.companionValue(listOf(8.0, 8.0)), 0.0)

        val (leftControl, rightControl) = controls
        for (right in rightControl.range) {
            var previousCoverage = spec.minimum
            for (left in leftControl.range) {
                val values = listOf(left.toDouble(), right.toDouble())
                val covered = spec.evaluate(values)
                val overlap = spec.companionValue(values)
                val leftSpaces = (1..left).toSet()
                val rightSpaces = (11 - right..10).toSet()
                assertTrue(covered in spec.minimum..spec.maximum && covered >= previousCoverage)
                assertEquals(leftSpaces.union(rightSpaces).size.toDouble(), covered, 0.0)
                assertEquals(leftSpaces.intersect(rightSpaces).size.toDouble(), overlap, 0.0)
                previousCoverage = covered
            }
        }
    }

    @Test fun chartRoundsBeforeCountingOverlap() {
        assertEquals(9.0, spec.evaluate(listOf(5.49, 4.0)), 0.0)
        assertEquals(10.0, spec.evaluate(listOf(5.5, 4.0)), 0.0)
        assertEquals(0.0, spec.companionValue(listOf(5.5, 4.0)), 0.0)
        assertEquals(1.0, spec.companionValue(listOf(6.5, 4.0)), 0.0)
    }
}
