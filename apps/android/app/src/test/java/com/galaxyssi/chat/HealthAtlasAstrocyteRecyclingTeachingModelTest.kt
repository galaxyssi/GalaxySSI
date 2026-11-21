package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasAstrocyteRecyclingTeachingModelTest {
    private val spec = HealthAtlasAstrocyteRecyclingTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val tolerance = 1e-12

    @Test fun defaultsShowTwoSharesOfTheSameStartingPool() {
        val defaults = controls.map { it.initial / it.scale }
        assertEquals(setOf("cell-astrocyte"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("%", "%"), spec.inputs.map { it.unit })
        assertEquals("%", spec.unit)
        assertEquals(listOf(60.0, 50.0), defaults)
        assertEquals(30.0, spec.evaluate(defaults), tolerance)
        assertEquals(40.0, spec.companionValue(defaults), tolerance)
    }

    @Test fun zeroUptakeZeroReturnAndFullReturnAreDistinctEdges() {
        assertEquals(0.0, spec.minimum, tolerance)
        assertEquals(100.0, spec.maximum, tolerance)
        assertEquals(0.0, spec.evaluate(listOf(0.0, 100.0)), tolerance)
        assertEquals(100.0, spec.companionValue(listOf(0.0, 100.0)), tolerance)
        assertEquals(0.0, spec.evaluate(listOf(100.0, 0.0)), tolerance)
        assertEquals(0.0, spec.companionValue(listOf(100.0, 0.0)), tolerance)
        assertEquals(100.0, spec.evaluate(listOf(100.0, 100.0)), tolerance)
    }

    @Test fun returnedShareGrowsWithoutExceedingUptake() {
        val (uptakeControl, returnControl) = controls
        for (u in uptakeControl.range) {
            val uptake = u / uptakeControl.scale
            for (r in returnControl.range) {
                val returned = r / returnControl.scale
                val inputs = listOf(uptake, returned)
                val recycled = spec.evaluate(inputs)
                val outside = spec.companionValue(inputs)

                assertTrue(recycled in spec.minimum..spec.maximum)
                assertTrue(recycled in 0.0..uptake)
                assertEquals(100.0, outside + uptake, tolerance)
                if (u > uptakeControl.range.first) {
                    val lessUptake = listOf((u - 1) / uptakeControl.scale, returned)
                    assertTrue(recycled >= spec.evaluate(lessUptake))
                    assertTrue(outside < spec.companionValue(lessUptake))
                }
                if (r > returnControl.range.first) {
                    val lessReturn = listOf(uptake, (r - 1) / returnControl.scale)
                    assertTrue(recycled >= spec.evaluate(lessReturn))
                    assertEquals(outside, spec.companionValue(lessReturn), tolerance)
                }
            }
        }
    }
}
