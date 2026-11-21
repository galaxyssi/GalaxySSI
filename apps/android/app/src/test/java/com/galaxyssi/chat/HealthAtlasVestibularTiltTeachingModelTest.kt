package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasVestibularTiltTeachingModelTest {
    private val spec = HealthAtlasVestibularTiltTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-9

    @Test fun defaultsPlotLateralMagnitudeInGAgainstCueAngleInDegrees() {
        assertEquals(setOf("vestibular-apparatus"), spec.entryIds)
        assertEquals(listOf("vestibular-tilt-lateral", "vestibular-tilt-downward"), controls.map { it.key })
        assertEquals(0, spec.axis)
        assertEquals(listOf("g", "g"), spec.inputs.map { it.unit })
        assertEquals("\u00b0", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(0.30, 1.00), defaults)
        assertEquals(16.699244234, spec.evaluate(defaults), epsilon)
        assertEquals(1.044030651, spec.companionValue(defaults), epsilon)
    }

    @Test fun extremesUseHeadDownAsZeroAndAllowAnglesBeyond45Degrees() {
        val (lateral, downward) = controls
        assertEquals(0..100, lateral.range)
        assertEquals(50..150, downward.range)
        assertEquals(listOf(100.0, 100.0), controls.map { it.scale })

        val downOnly = listOf(0.0, 0.5)
        val mostLateral = listOf(1.0, 0.5)
        val largest = listOf(1.0, 1.5)
        assertEquals(0.0, spec.evaluate(downOnly), epsilon)
        assertEquals(0.5, spec.companionValue(downOnly), epsilon)
        assertEquals(63.434948823, spec.evaluate(mostLateral), epsilon)
        assertEquals(1.118033989, spec.companionValue(mostLateral), epsilon)
        assertEquals(33.690067526, spec.evaluate(largest), epsilon)
        assertEquals(1.802775638, spec.companionValue(largest), epsilon)
    }

    @Test fun equalComponentRatiosGiveTheSameDirectionButNotTheSameMagnitude() {
        val shorter = listOf(0.4, 0.6)
        val longer = listOf(0.8, 1.2)
        assertEquals(spec.evaluate(shorter), spec.evaluate(longer), epsilon)
        assertEquals(2.0 * spec.companionValue(shorter), spec.companionValue(longer), epsilon)
    }

    @Test fun allSliderCombinationsFitChartAndAngleFollowsComponentDirection() {
        val (lateral, downward) = controls
        for (downwardStep in downward.range) {
            val d = downwardStep / downward.scale
            var previousAngle = Double.NEGATIVE_INFINITY
            for (lateralStep in lateral.range) {
                val l = lateralStep / lateral.scale
                val values = listOf(l, d)
                val angle = spec.evaluate(values)
                assertTrue(angle in spec.minimum..spec.maximum && angle > previousAngle)
                assertTrue(spec.companionValue(values) in 0.5..1.803)
                if (l > 0.0 && downwardStep < downward.range.last) {
                    val moreDownward = listOf(l, (downwardStep + 1) / downward.scale)
                    assertTrue(spec.evaluate(moreDownward) < angle)
                }
                previousAngle = angle
            }
        }
    }
}
