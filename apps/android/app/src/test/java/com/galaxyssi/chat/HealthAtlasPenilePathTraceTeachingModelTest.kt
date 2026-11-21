package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasPenilePathTraceTeachingModelTest {
    private val spec = HealthAtlasPenilePathTraceTeachingModel.spec
    private val input = spec.inputs.single()
    private val control = input.control
    private val tolerance = 1e-9

    @Test fun defaultIsFourDrawingUnitsFromTheBulbAndSixFromTheOpening() {
        assertEquals(setOf("penis"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals("%", input.unit)
        assertEquals("u", spec.unit)
        assertEquals(0..100, control.range)

        val defaults = listOf(control.initial / control.scale)
        assertEquals(listOf(40.0), defaults)
        assertEquals(4.0, spec.evaluate(defaults), tolerance)
        assertEquals(6.0, spec.companionValue(defaults), tolerance)
    }

    @Test fun endpointsCorrespondToTheBulbAndExternalOpening() {
        val start = listOf(control.range.first / control.scale)
        val end = listOf(control.range.last / control.scale)
        assertEquals(0.0, spec.minimum, tolerance)
        assertEquals(10.0, spec.maximum, tolerance)
        assertEquals(spec.minimum, spec.evaluate(start), tolerance)
        assertEquals(spec.maximum, spec.companionValue(start), tolerance)
        assertEquals(spec.maximum, spec.evaluate(end), tolerance)
        assertEquals(spec.minimum, spec.companionValue(end), tolerance)
    }

    @Test fun traceAndRemainingDistancePartitionTheSameLineAtEveryPosition() {
        var previousTraced = spec.evaluate(listOf(0.0))
        var previousLeft = spec.companionValue(listOf(0.0))
        for (step in 1..200) {
            val position = listOf(step / 2.0)
            val traced = spec.evaluate(position)
            val left = spec.companionValue(position)
            assertTrue(traced in spec.minimum..spec.maximum && traced > previousTraced)
            assertTrue(left in spec.minimum..spec.maximum && left < previousLeft)
            assertEquals(spec.maximum, traced + left, tolerance)
            assertEquals(0.05, traced - previousTraced, tolerance)
            previousTraced = traced
            previousLeft = left
        }
    }
}
