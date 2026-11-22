package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasRetinalLightAttenuationTeachingModelTest {
    private val spec = HealthAtlasRetinalLightAttenuationTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-9

    @Test fun defaultsAndMappingMatchTheFictionalLayer() {
        assertEquals(setOf("cell-cone-photoreceptor", "cell-retinal-pigment-epithelial-cell"), spec.entryIds)
        assertEquals(1, spec.axis)
        assertEquals("retinal-light-attenuation-path-length", controls[spec.axis].key)
        assertEquals(listOf("1/a.u.", "a.u."), spec.inputs.map { it.unit })
        assertEquals("a.u.", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(0.5, 2.0), defaults)
        assertEquals(36.7879441171, spec.evaluate(defaults), epsilon)
        assertEquals(63.2120558829, spec.companionValue(defaults), epsilon)
    }

    @Test fun boundsKeepTheFullBeamAtZeroLengthAndLeaveSomeLightAtMaximumAbsorption() {
        val (coefficient, path) = controls
        assertEquals(1..10, coefficient.range)
        assertEquals(0..40, path.range)
        assertEquals(10.0, coefficient.scale, 0.0)
        assertEquals(10.0, path.scale, 0.0)
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(100.0, spec.maximum, 0.0)

        for (step in coefficient.range) {
            val zeroLength = listOf(step / coefficient.scale, 0.0)
            assertEquals(100.0, spec.evaluate(zeroLength), 0.0)
            assertEquals(0.0, spec.companionValue(zeroLength), 0.0)
        }

        val maximumAttenuation = listOf(coefficient.range.last / coefficient.scale, path.range.last / path.scale)
        assertEquals(1.8315638889, spec.evaluate(maximumAttenuation), epsilon)
    }

    @Test fun longerPathsDecreaseTransmissionAndIncreaseAbsorptionAtEveryCoefficient() {
        val (coefficient, path) = controls
        for (coefficientStep in coefficient.range) {
            var previousTransmitted = Double.POSITIVE_INFINITY
            var previousAbsorbed = Double.NEGATIVE_INFINITY
            for (pathStep in path.range) {
                val values = listOf(coefficientStep / coefficient.scale, pathStep / path.scale)
                val transmitted = spec.evaluate(values)
                val absorbed = spec.companionValue(values)

                assertTrue(transmitted in spec.minimum..spec.maximum)
                assertTrue(absorbed in 0.0..100.0)
                assertTrue(transmitted < previousTransmitted)
                assertTrue(absorbed > previousAbsorbed)
                assertEquals(100.0, transmitted + absorbed, epsilon)
                previousTransmitted = transmitted
                previousAbsorbed = absorbed
            }
        }
    }

    @Test fun strongerAbsorptionLowersTheCurveAtNonzeroPathLengths() {
        val (coefficient, path) = controls
        for (pathStep in (path.range.first + 1)..path.range.last) {
            var previous = Double.POSITIVE_INFINITY
            for (coefficientStep in coefficient.range) {
                val transmitted = spec.evaluate(listOf(coefficientStep / coefficient.scale, pathStep / path.scale))
                assertTrue(transmitted < previous)
                previous = transmitted
            }
        }
    }

    @Test fun equalPathIncrementsTransmitTheSameFractionBetweenSliderSteps() {
        val start = spec.evaluate(listOf(0.5, 2.0))
        val middle = spec.evaluate(listOf(0.5, 2.05))
        val end = spec.evaluate(listOf(0.5, 2.10))
        assertTrue(start > middle && middle > end)
        assertEquals(middle / start, end / middle, epsilon)
    }
}
