package com.galaxyssi.chat

import kotlin.math.PI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasTestisTubuleSectionTeachingModelTest {
    private val spec = HealthAtlasTestisTubuleSectionTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val tolerance = 1e-12

    @Test fun defaultsUseWallThicknessAxisAndSyntheticUnits() {
        val defaults = controls.map { it.initial / it.scale }

        assertEquals(
            setOf("testes", "cell-sertoli-cell", "cell-leydig-cell", "cell-spermatogonium", "cell-spermatocyte"),
            spec.entryIds,
        )
        assertEquals(1, spec.axis)
        assertEquals(listOf("u", "u"), spec.inputs.map { it.unit })
        assertEquals("%", spec.unit)
        assertEquals(listOf(6.0, 2.0), defaults)
        assertEquals(100.0 * 20.0 / 36.0, spec.evaluate(defaults), tolerance)
        assertEquals(16.0 * PI, spec.companionValue(defaults), tolerance)
    }

    @Test fun thickerWallRaisesShareAndShrinksInnerAreaAcrossSliderBounds() {
        val (radiusControl, thicknessControl) = controls
        assertEquals(
            4.0..8.0,
            radiusControl.range.first / radiusControl.scale..radiusControl.range.last / radiusControl.scale,
        )
        assertEquals(
            1.0..3.0,
            thicknessControl.range.first / thicknessControl.scale..thicknessControl.range.last / thicknessControl.scale,
        )
        assertEquals(0.0, spec.minimum, tolerance)
        assertEquals(100.0, spec.maximum, tolerance)
        assertEquals(23.4375, spec.evaluate(listOf(8.0, 1.0)), tolerance)
        assertEquals(93.75, spec.evaluate(listOf(4.0, 3.0)), tolerance)
        assertEquals(49.0 * PI, spec.companionValue(listOf(8.0, 1.0)), tolerance)
        assertEquals(PI, spec.companionValue(listOf(4.0, 3.0)), tolerance)

        for (radiusStep in radiusControl.range) {
            val radius = radiusStep / radiusControl.scale
            val totalArea = PI * radius * radius
            var previousShare = spec.minimum
            var previousInnerArea = totalArea
            for (thicknessStep in thicknessControl.range) {
                val inputs = listOf(radius, thicknessStep / thicknessControl.scale)
                val share = spec.evaluate(inputs)
                val innerArea = spec.companionValue(inputs)
                assertTrue(share in spec.minimum..spec.maximum && share > previousShare)
                assertTrue(innerArea > 0.0 && innerArea < previousInnerArea)
                assertEquals(totalArea, innerArea + totalArea * share / 100.0, tolerance)
                previousShare = share
                previousInnerArea = innerArea
            }
        }
    }

    @Test fun largerRadiusLowersShareAndGrowsInnerAreaAtFixedThickness() {
        val smaller = listOf(4.0, 2.0)
        val larger = listOf(8.0, 2.0)

        assertTrue(spec.evaluate(larger) < spec.evaluate(smaller))
        assertTrue(spec.companionValue(larger) > spec.companionValue(smaller))
    }
}
