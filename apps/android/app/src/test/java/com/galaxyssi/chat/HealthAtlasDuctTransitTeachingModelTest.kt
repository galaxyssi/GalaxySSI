package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasDuctTransitTeachingModelTest {
    private val spec = HealthAtlasDuctTransitTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-12

    @Test fun defaultInputsUsePathLengthAsTheAxisAndSyntheticUnits() {
        assertEquals(setOf("male", "epididymis", "vas-deferens", "ejaculatory-ducts"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("LU", "LU/TU"), spec.inputs.map { it.unit })
        assertEquals("TU", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(12.0, 2.5), defaults)
        assertEquals(4.8, spec.evaluate(defaults), epsilon)
        assertEquals(0.4, spec.companionValue(defaults), epsilon)
    }

    @Test fun doublingLengthDoublesTimeAndDoublingSpeedHalvesTime() {
        val base = listOf(12.0, 2.5)
        val longer = listOf(24.0, 2.5)
        val faster = listOf(12.0, 5.0)

        assertEquals(2.0 * spec.evaluate(base), spec.evaluate(longer), epsilon)
        assertEquals(0.5 * spec.evaluate(base), spec.evaluate(faster), epsilon)
        assertEquals(spec.companionValue(base), spec.companionValue(longer), epsilon)
        assertEquals(0.5 * spec.companionValue(base), spec.companionValue(faster), epsilon)
    }

    @Test fun allSliderCombinationsFitChartAndTimeIncreasesWithPathLength() {
        val (lengthControl, speedControl) = controls
        var minimum = Double.POSITIVE_INFINITY
        var maximum = Double.NEGATIVE_INFINITY
        for (speedStep in speedControl.range) {
            val speed = speedStep / speedControl.scale
            var previous = 0.0
            for (lengthStep in lengthControl.range) {
                val length = lengthStep / lengthControl.scale
                val values = listOf(length, speed)
                val time = spec.evaluate(values)
                assertTrue(time.isFinite() && time in spec.minimum..spec.maximum)
                assertTrue(time > previous)
                assertEquals(length, time * speed, epsilon)
                assertEquals(time, spec.companionValue(values) * length, epsilon)
                previous = time
                minimum = minOf(minimum, time)
                maximum = maxOf(maximum, time)
            }
        }
        assertEquals(0.8, minimum, epsilon)
        assertEquals(24.0, maximum, epsilon)
    }
}
