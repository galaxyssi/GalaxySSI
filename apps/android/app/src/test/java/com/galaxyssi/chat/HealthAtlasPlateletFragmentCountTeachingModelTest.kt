package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasPlateletFragmentCountTeachingModelTest {
    private val spec = HealthAtlasPlateletFragmentCountTeachingModel.spec
    private val controls = spec.inputs.map { it.control }

    @Test fun defaultsCountTwelveTilesAndAddThreePerExtraIcon() {
        assertEquals(setOf("fragment-platelet", "cell-megakaryocyte"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("", ""), spec.inputs.map { it.unit })
        assertEquals("", spec.unit)
        assertEquals(listOf(0, 0), spec.inputs.map { it.digits })
        assertEquals(0, spec.digits)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(4.0, 3.0), defaults)
        assertEquals(12.0, spec.evaluate(defaults), 0.0)
        assertEquals(3.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun chartBoundsFitAllFourCorners() {
        val (icons, tiles) = controls
        val fewestIcons = icons.range.first / icons.scale
        val mostIcons = icons.range.last / icons.scale
        val fewestTiles = tiles.range.first / tiles.scale
        val mostTiles = tiles.range.last / tiles.scale

        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(48.0, spec.maximum, 0.0)
        assertEquals(spec.minimum, spec.evaluate(listOf(fewestIcons, fewestTiles)), 0.0)
        assertEquals(spec.minimum, spec.evaluate(listOf(fewestIcons, mostTiles)), 0.0)
        assertEquals(spec.minimum, spec.evaluate(listOf(mostIcons, fewestTiles)), 0.0)
        assertEquals(spec.maximum, spec.evaluate(listOf(mostIcons, mostTiles)), 0.0)
        assertEquals(0.0, spec.companionValue(listOf(mostIcons, fewestTiles)), 0.0)
        assertEquals(6.0, spec.companionValue(listOf(mostIcons, mostTiles)), 0.0)
    }

    @Test fun eachWholeStepAddsTheOtherFactor() {
        val (icons, tiles) = controls
        for (iconCount in icons.range) {
            for (tilesPerIcon in tiles.range) {
                val values = listOf(iconCount / icons.scale, tilesPerIcon / tiles.scale)
                val total = spec.evaluate(values)
                assertTrue(total in spec.minimum..spec.maximum)
                if (iconCount < icons.range.last) {
                    val next = spec.evaluate(listOf((iconCount + 1) / icons.scale, values[1]))
                    assertEquals(tilesPerIcon.toDouble(), next - total, 0.0)
                    assertEquals(spec.companionValue(values), next - total, 0.0)
                }
                if (tilesPerIcon < tiles.range.last) {
                    val next = spec.evaluate(listOf(values[0], (tilesPerIcon + 1) / tiles.scale))
                    assertEquals(iconCount.toDouble(), next - total, 0.0)
                }
            }
        }
    }

    @Test fun chartSamplesRoundToWholeIconsBeforeCountingTiles() {
        assertEquals(6.0, spec.evaluate(listOf(2.49, 3.0)), 0.0)
        assertEquals(9.0, spec.evaluate(listOf(2.5, 3.0)), 0.0)
        assertEquals(9.0, spec.evaluate(listOf(2.51, 3.0)), 0.0)
    }
}
