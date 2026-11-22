package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasCardiacPhaseTimeTeachingModelTest {
    private val spec = HealthAtlasCardiacPhaseTimeTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-9

    @Test fun scopeAndDefaultValuesMatchTheTeachingModel() {
        assertEquals(
            setOf(
                "cardio", "heart", "atria", "left-atrium", "right-atrium",
                "tissue-cardiac-muscle", "cell-cardiomyocyte",
            ),
            spec.entryIds,
        )
        assertEquals(1, spec.axis)
        assertEquals(listOf("bpm", "%"), spec.inputs.map { it.unit })
        assertEquals("ms", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(75.0, 50.0), defaults)
        assertEquals(400.0, spec.evaluate(defaults), epsilon)
        assertEquals(800.0, spec.companionValue(defaults), epsilon)
    }

    @Test fun heartRateChangesTheCurveAndTheChosenPercentageDoesNotChangeTheCycle() {
        val base = listOf(75.0, 50.0)
        val faster = listOf(150.0, 50.0)
        val largerShare = listOf(75.0, 60.0)

        assertEquals(200.0, spec.evaluate(faster), epsilon)
        assertEquals(400.0, spec.companionValue(faster), epsilon)
        assertEquals(480.0, spec.evaluate(largerShare), epsilon)
        assertEquals(spec.companionValue(base), spec.companionValue(largerShare), epsilon)
    }

    @Test fun everySliderCombinationFitsTheChartAndPreservesTheChosenTimeFraction() {
        val (rateControl, fractionControl) = controls
        val chart = spec.minimum..spec.maximum
        for (rateStep in rateControl.range) {
            val rate = rateStep / rateControl.scale
            for (fractionStep in fractionControl.range) {
                val percent = fractionStep / fractionControl.scale
                val values = listOf(rate, percent)
                val filling = spec.evaluate(values)
                val cycle = spec.companionValue(values)

                assertTrue(filling in chart && cycle in chart)
                assertTrue(filling > 0.0 && filling < cycle)
                assertEquals(60_000.0, cycle * rate, epsilon)
                assertEquals(percent, 100.0 * filling / cycle, epsilon)
            }
        }
        assertEquals(120.0, spec.evaluate(listOf(150.0, 30.0)), epsilon)
        assertEquals(840.0, spec.evaluate(listOf(50.0, 70.0)), epsilon)
    }
}
