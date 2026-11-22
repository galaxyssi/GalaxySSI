package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasMuscleShorteningTeachingModelTest {
    private val spec = HealthAtlasMuscleShorteningTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val defaults = controls.map { it.initial / it.scale }
    private val tolerance = 1e-12

    @Test fun defaultsGiveSegmentShorteningAndRemainingLengthInMillimeters() {
        assertEquals(listOf("", "\u00b5m"), spec.inputs.map { it.unit })
        assertEquals("mm", spec.unit)
        assertEquals(1, spec.axis)
        assertEquals(listOf(1000.0, 0.25), defaults)
        assertEquals(0.25, spec.evaluate(defaults), tolerance)
        assertEquals(2.25, spec.companionValue(defaults), tolerance)
    }

    @Test fun nonDefaultInputsAddTheSameShorteningAcrossAllSarcomeres() {
        val inputs = listOf(750.0, 0.32)
        assertEquals(0.24, spec.evaluate(inputs), tolerance)
        assertEquals(1.635, spec.companionValue(inputs), tolerance)
    }

    @Test fun sliderCornersFitTheChartAndLeavePositiveRemainingLength() {
        val (counts, changes) = controls.map { control ->
            listOf(control.range.first / control.scale, control.range.last / control.scale)
        }
        assertEquals(0.0, spec.minimum, tolerance)
        assertEquals(0.0, changes.first(), tolerance)
        for (count in counts) {
            val unshortened = listOf(count, changes.first())
            assertEquals(0.0, spec.evaluate(unshortened), tolerance)
            val startingLength = spec.companionValue(unshortened)
            for (change in changes) {
                val inputs = listOf(count, change)
                val shortening = spec.evaluate(inputs)
                val remaining = spec.companionValue(inputs)
                assertTrue(shortening in spec.minimum..spec.maximum)
                assertTrue(remaining > 0.0)
                assertEquals(startingLength, shortening + remaining, tolerance)
            }
        }
        val peak = listOf(counts.last(), changes.last())
        assertEquals(1.0, spec.evaluate(peak), tolerance)
        assertEquals(spec.maximum, spec.evaluate(peak), tolerance)
        assertEquals(4.0, spec.companionValue(peak), tolerance)
    }

    @Test fun moreSarcomeresIncreaseShorteningAndSteepenTheIncreasingAxis() {
        val (count, shortening) = defaults
        val moreSarcomeres = listOf(count * 1.5, shortening)
        val moreShortening = listOf(count, shortening * 2)
        assertEquals(1.5 * spec.evaluate(defaults), spec.evaluate(moreSarcomeres), tolerance)
        assertEquals(2 * spec.evaluate(defaults), spec.evaluate(moreShortening), tolerance)
        assertTrue(spec.companionValue(moreShortening) < spec.companionValue(defaults))

        val (countControl, axisControl) = controls
        for (step in listOf(countControl.range.first, countControl.range.last)) {
            val samples = axisControl.range.map { spec.evaluate(listOf(step / countControl.scale, it / axisControl.scale)) }
            assertTrue(samples.zipWithNext().all { (left, right) -> right > left })
        }
    }

    @Test fun targetsOnlyTheRequestedAtlasEntries() {
        assertEquals(
            setOf(
                "cell-skeletal-myocyte", "tissue-skeletal-muscle", "pectoralis-major", "deltoid",
                "triceps-brachii", "rectus-abdominis", "oblique-abdominal-muscles", "trapezius",
                "latissimus-dorsi", "erector-spinae", "gluteus-maximus", "hamstrings",
            ),
            spec.entryIds,
        )
    }
}
