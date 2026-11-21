package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasEnteroendocrinePolarityTeachingModelTest {
    private val spec = HealthAtlasEnteroendocrinePolarityTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val tolerance = 1e-12

    @Test fun defaultsLocateTheMarkerFromBothEndsOfTheOpenTypeCell() {
        assertEquals(setOf("cell-enteroendocrine-cell"), spec.entryIds)
        assertEquals("enteroendocrine-polarity-basal-offset", controls[spec.axis].key)
        assertEquals(listOf("u", "u"), spec.inputs.map { it.unit })
        assertEquals("%", spec.unit)
        assertEquals(listOf(5..25, 60..120), controls.map { it.range })
        assertEquals(listOf(10.0, 10.0), controls.map { it.scale })

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(1.5, 8.0), defaults)
        assertEquals(18.75, spec.evaluate(defaults), tolerance)
        assertEquals(6.5, spec.companionValue(defaults), tolerance)
    }

    @Test fun markerRemainsCloserToTheBasalEdgeAtAllDrawingSizes() {
        val (offset, height) = controls
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(50.0, spec.maximum, 0.0)
        assertEquals(50.0 / 12.0, spec.evaluate(listOf(0.5, 12.0)), tolerance)
        assertEquals(250.0 / 6.0, spec.evaluate(listOf(2.5, 6.0)), tolerance)
        assertEquals(11.5, spec.companionValue(listOf(0.5, 12.0)), tolerance)
        assertEquals(3.5, spec.companionValue(listOf(2.5, 6.0)), tolerance)

        for (heightStep in height.range) {
            val drawnHeight = heightStep / height.scale
            var previousPercent = spec.minimum
            var previousApicalDistance = drawnHeight
            for (offsetStep in offset.range) {
                val basalDistance = offsetStep / offset.scale
                val values = listOf(basalDistance, drawnHeight)
                val basalPercent = spec.evaluate(values)
                val apicalDistance = spec.companionValue(values)
                assertTrue(basalPercent > previousPercent && basalPercent < spec.maximum)
                assertTrue(apicalDistance > basalDistance && apicalDistance < previousApicalDistance)
                assertEquals(drawnHeight, basalDistance + apicalDistance, tolerance)
                assertEquals(basalDistance, drawnHeight * basalPercent / 100.0, tolerance)
                previousPercent = basalPercent
                previousApicalDistance = apicalDistance
            }
        }
    }
}
