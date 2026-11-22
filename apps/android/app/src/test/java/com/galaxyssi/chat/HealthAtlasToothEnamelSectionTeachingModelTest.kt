package com.galaxyssi.chat

import kotlin.math.PI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasToothEnamelSectionTeachingModelTest {
    private val spec = HealthAtlasToothEnamelSectionTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val tolerance = 1e-10

    @Test fun defaultsPlotEnamelShareAgainstThicknessForTeeth() {
        val defaults = controls.map { it.initial / it.scale }

        assertEquals(setOf("teeth"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(
            listOf("tooth-enamel-section-thickness", "tooth-enamel-section-radius"),
            controls.map { it.key },
        )
        assertEquals(listOf("mm", "mm"), spec.inputs.map { it.unit })
        assertEquals("%", spec.unit)
        assertEquals(listOf(1.0, 4.0), defaults)
        assertEquals(43.75, spec.evaluate(defaults), tolerance)
        assertEquals(9.0 * PI, spec.companionValue(defaults), tolerance)
    }

    @Test fun sliderExtremaKeepBothRegionsPresent() {
        val (thickness, radius) = controls
        assertEquals(0.5..2.0, thickness.range.first / thickness.scale..thickness.range.last / thickness.scale)
        assertEquals(3.0..6.0, radius.range.first / radius.scale..radius.range.last / radius.scale)
        assertEquals(100.0 * 23.0 / 144.0, spec.evaluate(listOf(0.5, 6.0)), tolerance)
        assertEquals(800.0 / 9.0, spec.evaluate(listOf(2.0, 3.0)), tolerance)
        assertEquals(30.25 * PI, spec.companionValue(listOf(0.5, 6.0)), tolerance)
        assertEquals(PI, spec.companionValue(listOf(2.0, 3.0)), tolerance)
    }

    @Test fun everySliderPairPartitionsTheSectionAndFitsTheChart() {
        val (thickness, radius) = controls
        for (tStep in thickness.range) {
            for (rStep in radius.range) {
                val t = tStep / thickness.scale
                val r = rStep / radius.scale
                val inputs = listOf(t, r)
                val enamelShare = spec.evaluate(inputs)
                val fullArea = PI * r * r
                val innerArea = spec.companionValue(inputs)

                assertTrue(enamelShare in spec.minimum..spec.maximum)
                assertTrue(enamelShare > 0.0 && enamelShare < 100.0)
                assertTrue(innerArea > 0.0 && innerArea < fullArea)
                assertEquals(fullArea, innerArea + fullArea * enamelShare / 100.0, tolerance)
            }
        }
    }

    @Test fun enamelShareIncreasesWithThicknessAndDecreasesWithRadius() {
        val (thickness, radius) = controls
        for (tStep in thickness.range) {
            for (rStep in radius.range) {
                val t = tStep / thickness.scale
                val r = rStep / radius.scale
                val share = spec.evaluate(listOf(t, r))
                if (tStep < thickness.range.last) {
                    assertTrue(spec.evaluate(listOf((tStep + 1) / thickness.scale, r)) > share)
                }
                if (rStep < radius.range.last) {
                    assertTrue(spec.evaluate(listOf(t, (rStep + 1) / radius.scale)) < share)
                }
            }
        }
    }
}
