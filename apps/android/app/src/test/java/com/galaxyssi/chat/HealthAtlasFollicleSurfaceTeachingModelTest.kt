package com.galaxyssi.chat

import kotlin.math.PI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasFollicleSurfaceTeachingModelTest {
    private val spec = HealthAtlasFollicleSurfaceTeachingModel.spec
    private val diameter = spec.inputs[0].control
    private val thickness = spec.inputs[1].control

    @Test fun plotsOuterAreaAgainstCavityDiameterForTheThreeFollicleEntries() {
        assertEquals(setOf("ovaries", "cell-granulosa-cell", "cell-theca-cell"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("mm", "mm"), spec.inputs.map { it.unit })
        assertEquals("mm\u00b2", spec.unit)
    }

    @Test fun defaultGeometryUsesTheOuterSphereAndExcludesTheCavityFromVolume() {
        val defaults = spec.inputs.map { it.control.initial / it.control.scale }
        assertEquals(listOf(8.0, 0.5), defaults)
        assertEquals(81.0 * PI, spec.evaluate(defaults), 1e-9)
        assertEquals(217.0 * PI / 6.0, spec.companionValue(defaults), 1e-9)
    }

    @Test fun sliderExtremesKeepBothRegionsPositiveAndTheAreaInBounds() {
        val diameters = diameter.values()
        val thicknesses = thickness.values()
        val smallest = listOf(diameters.first(), thicknesses.first())
        val largest = listOf(diameters.last(), thicknesses.last())
        assertEquals(listOf(4.0, 0.2), smallest)
        assertEquals(listOf(14.0, 1.0), largest)
        assertEquals(19.36 * PI, spec.evaluate(smallest), 1e-9)
        assertEquals(4.0 * PI * 2.648 / 3.0, spec.companionValue(smallest), 1e-9)
        assertEquals(256.0 * PI, spec.evaluate(largest), 1e-9)
        assertEquals(676.0 * PI / 3.0, spec.companionValue(largest), 1e-9)

        for (d in diameters) {
            for (t in thicknesses) {
                val point = listOf(d, t)
                assertTrue(spec.evaluate(point) in spec.minimum..spec.maximum)
                val volume = spec.companionValue(point)
                assertTrue(volume.isFinite() && volume > 0.0)
            }
        }
    }

    @Test fun bothOutputsIncreaseAlongTheChartAndWithGreaterThickness() {
        val diameters = diameter.values()
        val thicknesses = thickness.values()
        val chartPoints = (0..40).map { diameters.first() + (diameters.last() - diameters.first()) * it / 40.0 }
        for (t in thicknesses) assertBothIncrease(chartPoints.map { d -> listOf(d, t) })
        for (d in diameters) assertBothIncrease(thicknesses.map { t -> listOf(d, t) })
    }

    @Test fun geometryRejectsNonpositiveOrNonfiniteDimensions() {
        for (invalid in listOf(0.0, -1.0, Double.NaN, Double.POSITIVE_INFINITY)) {
            for (point in listOf(listOf(invalid, 0.5), listOf(8.0, invalid))) {
                assertThrows(IllegalArgumentException::class.java) { spec.evaluate(point) }
                assertThrows(IllegalArgumentException::class.java) { spec.companionValue(point) }
            }
        }
    }

    private fun HealthAtlasInput.values() = range.map { it / scale }

    private fun assertBothIncrease(points: List<List<Double>>) {
        for ((before, after) in points.zipWithNext()) {
            assertTrue(spec.evaluate(after) > spec.evaluate(before))
            assertTrue(spec.companionValue(after) > spec.companionValue(before))
        }
    }
}
