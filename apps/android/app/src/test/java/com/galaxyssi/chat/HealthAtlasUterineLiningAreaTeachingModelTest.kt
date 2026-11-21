package com.galaxyssi.chat

import kotlin.math.PI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasUterineLiningAreaTeachingModelTest {
    private val spec = HealthAtlasUterineLiningAreaTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-9

    @Test fun defaultsUseRadiusAsTheAxisAndSyntheticUnits() {
        assertEquals(setOf("uterus", "cervix", "cell-endometrial-epithelial-cell"), spec.entryIds)
        assertEquals("uterine-lining-radius", controls[spec.axis].key)
        assertEquals(listOf("LU", "LU"), spec.inputs.map { it.unit })
        assertEquals("LU\u00b2", spec.unit)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(2.0, 4.0), defaults)
        assertEquals(16.0 * PI, spec.evaluate(defaults), epsilon)
        assertEquals(4.0 * PI, spec.companionValue(defaults), epsilon)
    }

    @Test fun allSliderCombinationsFitThePlotAndIncreaseWithEitherDimension() {
        val (radiusControl, lengthControl) = controls
        assertEquals(1.0, radiusControl.range.first / radiusControl.scale, epsilon)
        assertEquals(4.0, radiusControl.range.last / radiusControl.scale, epsilon)
        assertEquals(2.0, lengthControl.range.first / lengthControl.scale, epsilon)
        assertEquals(8.0, lengthControl.range.last / lengthControl.scale, epsilon)

        for (lengthStep in lengthControl.range) {
            val length = lengthStep / lengthControl.scale
            var previousArea: Double? = null
            for (radiusStep in radiusControl.range) {
                val radius = radiusStep / radiusControl.scale
                val area = spec.evaluate(listOf(radius, length))
                assertTrue(area.isFinite() && area in spec.minimum..spec.maximum)
                previousArea?.let { assertTrue(area > it) }
                if (lengthStep > lengthControl.range.first) {
                    val shorter = (lengthStep - 1) / lengthControl.scale
                    assertTrue(area > spec.evaluate(listOf(radius, shorter)))
                }
                previousArea = area
            }
        }
    }

    @Test fun doublingRadiusOrLengthDoublesOnlyTheCurvedSideArea() {
        val base = listOf(2.0, 4.0)
        val wider = listOf(4.0, 4.0)
        val longer = listOf(2.0, 8.0)

        assertEquals(2.0 * spec.evaluate(base), spec.evaluate(wider), epsilon)
        assertEquals(2.0 * spec.evaluate(base), spec.evaluate(longer), epsilon)
        assertEquals(2.0 * spec.companionValue(base), spec.companionValue(wider), epsilon)
        assertEquals(spec.companionValue(base), spec.companionValue(longer), epsilon)
    }
}
