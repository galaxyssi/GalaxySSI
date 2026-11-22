package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasMicrogliaSurveillanceTeachingModelTest {
    private val spec = HealthAtlasMicrogliaSurveillanceTeachingModel.spec
    private val controls = spec.inputs.map { it.control }

    @Test fun defaultsCountEachOfTwoOverlappingTilesOnce() {
        val defaults = controls.map { it.initial / it.scale }
        assertEquals(setOf("cell-microglia"), spec.entryIds)
        assertEquals(1, spec.axis)
        assertEquals(listOf(4.0, 2.0), defaults)
        assertEquals(6.0, spec.evaluate(defaults), 0.0)
        assertEquals(2.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun emptyIdenticalAndDisjointSnapshotsSetTheBounds() {
        val empty = listOf(0.0, 6.0)
        val identical = listOf(6.0, 0.0)
        val disjoint = listOf(6.0, 6.0)
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(12.0, spec.maximum, 0.0)
        assertEquals(spec.minimum, spec.evaluate(empty), 0.0)
        assertEquals(0.0, spec.companionValue(empty), 0.0)
        assertEquals(6.0, spec.evaluate(identical), 0.0)
        assertEquals(6.0, spec.companionValue(identical), 0.0)
        assertEquals(spec.maximum, spec.evaluate(disjoint), 0.0)
        assertEquals(0.0, spec.companionValue(disjoint), 0.0)
    }

    @Test fun distinctAndRepeatedTileCountsMatchTheDiagramForEverySliderPair() {
        val (widthControl, offsetControl) = controls
        for (width in widthControl.range) {
            val first = (0 until width).toSet()
            for (offset in offsetControl.range) {
                val second = (offset until offset + width).toSet()
                val values = listOf(width / widthControl.scale, offset / offsetControl.scale)
                assertTrue((first union second).all { it in 0 until 12 })
                assertEquals((first union second).size.toDouble(), spec.evaluate(values), 0.0)
                assertEquals((first intersect second).size.toDouble(), spec.companionValue(values), 0.0)
            }
        }
    }

    @Test fun chartSamplesRoundToWholeTilesAndPlateauAfterOverlapEnds() {
        assertEquals(6.0, spec.evaluate(listOf(4.0, 2.49)), 0.0)
        assertEquals(7.0, spec.evaluate(listOf(4.0, 2.5)), 0.0)
        assertEquals(1.0, spec.companionValue(listOf(4.0, 2.5)), 0.0)
        assertEquals(8.0, spec.evaluate(listOf(4.0, 4.0)), 0.0)
        assertEquals(8.0, spec.evaluate(listOf(4.0, 6.0)), 0.0)
    }
}
