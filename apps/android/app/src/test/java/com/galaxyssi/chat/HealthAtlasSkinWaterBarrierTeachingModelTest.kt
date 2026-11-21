package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasSkinWaterBarrierTeachingModelTest {
    private val spec = HealthAtlasSkinWaterBarrierTeachingModel.spec
    private val controls = spec.inputs.map { it.control }

    @Test fun controlsUseDimensionlessMultiplesOfTheDemoBaseline() {
        assertEquals("\u00d7", spec.unit)
        assertEquals(List(3) { spec.unit }, spec.inputs.map { it.unit })
        assertEquals(1, spec.axis)
        assertEquals(
            listOf(0.5..1.5, 0.0..1.5, 0.5..1.5),
            controls.map { it.range.first / it.scale..it.range.last / it.scale },
        )
        assertEquals(
            setOf("skin", "skin-organ", "epidermis", "tissue-epidermal", "cell-keratinocyte"),
            spec.entryIds,
        )
        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(1.0, 1.0, 1.0), defaults)
        assertEquals(1.0, spec.evaluate(defaults), 0.0)
        assertEquals(1.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun fluxUsesTheScaledInputsAndConductanceExcludesTheGradient() {
        val example = listOf(1.25, 0.60, 0.75)
        assertEquals(1.0, spec.evaluate(example), 1e-9)
        assertEquals(5.0 / 3.0, spec.companionValue(example), 1e-9)

        val equalConcentrations = listOf(1.25, 0.0, 0.75)
        assertEquals(0.0, spec.evaluate(equalConcentrations), 0.0)
        assertEquals(spec.companionValue(example), spec.companionValue(equalConcentrations), 0.0)
    }

    @Test fun chartCoversEverySliderCombination() {
        val (diffusivities, gradients, thicknesses) = controls.map { control ->
            control.range.map { it / control.scale }
        }
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(4.5, spec.maximum, 0.0)
        assertEquals(spec.minimum, spec.evaluate(listOf(0.5, 0.0, 1.5)), 0.0)
        assertEquals(spec.maximum, spec.evaluate(listOf(1.5, 1.5, 0.5)), 0.0)

        for (diffusivity in diffusivities) for (gradient in gradients) for (thickness in thicknesses) {
            val values = listOf(diffusivity, gradient, thickness)
            val flux = spec.evaluate(values)
            val conductance = spec.companionValue(values)
            assertTrue("Flux at $values: $flux", flux in spec.minimum..spec.maximum)
            assertTrue("Conductance at $values: $conductance", conductance in (1.0 / 3.0)..3.0)
            assertEquals(conductance * gradient, flux, 1e-9)
        }
    }

    @Test fun higherDiffusivityOrDifferenceRaisesFluxWhileGreaterThicknessLowersIt() {
        val baseline = spec.evaluate(listOf(1.0, 1.0, 1.0))
        assertTrue(spec.evaluate(listOf(1.5, 1.0, 1.0)) > baseline)
        assertTrue(spec.evaluate(listOf(1.0, 1.5, 1.0)) > baseline)
        assertTrue(spec.evaluate(listOf(1.0, 1.0, 1.5)) < baseline)
    }
}
