package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasJointArticularArcTeachingModelTest {
    private val spec = HealthAtlasJointArticularArcTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-9

    @Test fun defaultsPlotArcDistanceInMillimetersAgainstAngleInDegrees() {
        assertEquals(setOf("joints", "scapula"), spec.entryIds)
        assertEquals(listOf("joint-articular-arc-angle", "joint-articular-arc-radius"), controls.map { it.key })
        assertEquals(listOf("\u00b0", "mm"), spec.inputs.map { it.unit })
        assertEquals("mm", spec.unit)
        assertEquals(0, spec.axis)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(45.0, 25.0), defaults)
        assertEquals(19.634954085, spec.evaluate(defaults), epsilon)
        assertEquals(0.785398163, spec.companionValue(defaults), epsilon)
    }

    @Test fun sliderExtremesIncludeZeroAndAQuarterCircle() {
        val (angle, radius) = controls
        assertEquals(0..90, angle.range)
        assertEquals(10..40, radius.range)

        val zeroSweep = listOf(angle.range.first / angle.scale, radius.range.last / radius.scale)
        assertEquals(0.0, spec.evaluate(zeroSweep), epsilon)
        assertEquals(0.0, spec.companionValue(zeroSweep), epsilon)

        val quarterTurn = angle.range.last / angle.scale
        val smallestRadius = listOf(quarterTurn, radius.range.first / radius.scale)
        val largestRadius = listOf(quarterTurn, radius.range.last / radius.scale)
        assertEquals(5.0 * Math.PI, spec.evaluate(smallestRadius), epsilon)
        assertEquals(20.0 * Math.PI, spec.evaluate(largestRadius), epsilon)
        assertEquals(Math.PI / 2.0, spec.companionValue(smallestRadius), epsilon)
        assertEquals(Math.PI / 2.0, spec.companionValue(largestRadius), epsilon)
    }

    @Test fun allSliderCombinationsFitTheChartAndLengthIncreasesWithPositiveSweepAndRadius() {
        val (angle, radius) = controls
        for (radiusStep in radius.range) {
            val r = radiusStep / radius.scale
            var previousDistance = -1.0
            for (angleStep in angle.range) {
                val degrees = angleStep / angle.scale
                val distance = spec.evaluate(listOf(degrees, r))
                assertTrue(distance in spec.minimum..spec.maximum)
                assertTrue(distance > previousDistance)
                if (degrees == 0.0) {
                    assertEquals(0.0, distance, epsilon)
                } else if (radiusStep > radius.range.first) {
                    val smallerRadius = (radiusStep - 1) / radius.scale
                    assertTrue(distance > spec.evaluate(listOf(degrees, smallerRadius)))
                }
                previousDistance = distance
            }
        }
    }
}
