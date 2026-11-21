package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasAdiposeVolumeShareTeachingModelTest {
    private val spec = HealthAtlasAdiposeVolumeShareTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-9

    @Test fun defaultsSeparateCellAndTissueVolumeShares() {
        assertEquals(setOf("tissue-white-adipose", "cell-adipocyte"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("", "%"), spec.inputs.map { it.unit })
        assertEquals("%", spec.unit)
        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(0.90, 60.0), defaults)
        assertEquals(43.74, spec.evaluate(defaults), epsilon)
        assertEquals(72.9, spec.companionValue(defaults), epsilon)
    }

    @Test fun sliderEndpointsStayInsideTheCellAndChartBounds() {
        val (radius, cells) = controls
        assertEquals(40..98, radius.range)
        assertEquals(20..70, cells.range)
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(100.0, spec.maximum, 0.0)
        val smallest = listOf(radius.range.first / radius.scale, cells.range.first / cells.scale)
        val largest = listOf(radius.range.last / radius.scale, cells.range.last / cells.scale)
        assertEquals(1.28, spec.evaluate(smallest), epsilon)
        assertEquals(65.88344, spec.evaluate(largest), epsilon)
        assertEquals(6.4, spec.companionValue(smallest), epsilon)
        assertEquals(94.1192, spec.companionValue(largest), epsilon)
    }

    @Test fun chartRisesWithRadiusAtEveryTissueSettingIncludingBetweenSliderSteps() {
        val (radius, cells) = controls
        for (cellStep in cells.range) {
            val cellPercent = cellStep / cells.scale
            var previous = Double.NEGATIVE_INFINITY
            for (halfStep in (2 * radius.range.first)..(2 * radius.range.last)) {
                val ratio = halfStep / (2 * radius.scale)
                val values = listOf(ratio, cellPercent)
                val tissueShare = spec.evaluate(values)
                val cellShare = spec.companionValue(values)
                assertTrue(tissueShare in spec.minimum..spec.maximum)
                assertTrue(tissueShare > previous)
                assertTrue(tissueShare < cellPercent && cellShare in 0.0..100.0)
                assertEquals(cellPercent * cellShare / 100.0, tissueShare, epsilon)
                previous = tissueShare
            }
        }
        assertEquals(8 * spec.evaluate(listOf(0.4, 60.0)), spec.evaluate(listOf(0.8, 60.0)), epsilon)
    }

    @Test fun moreModelCellsRaiseTissueShareWithoutChangingOneCell() {
        val (radius, cells) = controls
        for (radiusStep in radius.range) {
            val ratio = radiusStep / radius.scale
            var previous = Double.NEGATIVE_INFINITY
            val oneCell = spec.companionValue(listOf(ratio, cells.range.first / cells.scale))
            for (cellStep in cells.range) {
                val values = listOf(ratio, cellStep / cells.scale)
                val tissueShare = spec.evaluate(values)
                assertTrue(tissueShare > previous)
                assertEquals(oneCell, spec.companionValue(values), epsilon)
                previous = tissueShare
            }
        }
    }
}
