package com.galaxyssi.chat

import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasCornealRefractionTeachingModelTest {
    private val spec = HealthAtlasCornealRefractionTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-9

    @Test fun defaultsUseIncidentDegreesAndADimensionlessIndex() {
        assertEquals(setOf("cornea", "cell-corneal-epithelial-cell"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("\u00b0", ""), spec.inputs.map { it.unit })
        assertEquals("\u00b0", spec.unit)
        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(40.0, 1.34), defaults)
        assertEquals(28.665304049, spec.evaluate(defaults), epsilon)
        assertEquals(11.334695951, spec.companionValue(defaults), epsilon)
    }

    @Test fun extremaIncludeNoBendAtNormalIncidenceAndBoundedAnglesAtMaxIncidence() {
        val (incident, medium) = controls
        val lowIndex = medium.range.first / medium.scale
        val highIndex = medium.range.last / medium.scale
        val normalIncidence = incident.range.first / incident.scale
        val maxIncidence = incident.range.last / incident.scale
        for (index in listOf(lowIndex, highIndex)) {
            val values = listOf(normalIncidence, index)
            assertEquals(0.0, spec.evaluate(values), epsilon)
            assertEquals(0.0, spec.companionValue(values), epsilon)
        }
        assertEquals(49.248195474, spec.evaluate(listOf(maxIncidence, lowIndex)), epsilon)
        assertEquals(42.779423730, spec.evaluate(listOf(maxIncidence, highIndex)), epsilon)
        assertEquals(37.220576270, spec.companionValue(listOf(maxIncidence, highIndex)), epsilon)
    }

    @Test fun allSliderValuesObeySnellsLawAndTheChartRisesWithIncidence() {
        val (incident, medium) = controls
        for (mediumStep in medium.range) {
            val index = mediumStep / medium.scale
            var previousAngle = Double.NEGATIVE_INFINITY
            for (incidentStep in incident.range) {
                val angle = incidentStep / incident.scale
                val inputs = listOf(angle, index)
                val refracted = spec.evaluate(inputs)
                assertTrue(refracted in spec.minimum..spec.maximum)
                assertTrue(refracted > previousAngle)
                assertEquals(sin(Math.toRadians(angle)), index * sin(Math.toRadians(refracted)), epsilon)
                assertEquals(angle, refracted + spec.companionValue(inputs), epsilon)
                previousAngle = refracted
            }
        }
    }

    @Test fun higherIndexBendsObliqueRaysCloserToTheNormal() {
        val (incident, medium) = controls
        for (incidentStep in (incident.range.first + 1)..incident.range.last) {
            val angle = incidentStep / incident.scale
            for (mediumStep in (medium.range.first + 1)..medium.range.last) {
                val lower = listOf(angle, (mediumStep - 1) / medium.scale)
                val higher = listOf(angle, mediumStep / medium.scale)
                assertTrue(spec.evaluate(higher) < spec.evaluate(lower))
                assertTrue(spec.companionValue(higher) > spec.companionValue(lower))
            }
        }
    }
}
