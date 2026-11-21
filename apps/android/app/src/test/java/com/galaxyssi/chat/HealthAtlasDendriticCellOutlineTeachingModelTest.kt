package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasDendriticCellOutlineTeachingModelTest {
    private val spec = HealthAtlasDendriticCellOutlineTeachingModel.spec
    private val control = spec.inputs.single().control

    @Test fun threeDefaultTabsMakeEighteenOutlineMarksAndTwelveTiles() {
        assertEquals(setOf("cell-dendritic-cell"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals("dendritic-cell-outline-tabs", control.key)
        assertEquals(0..4, control.range)
        assertEquals(0, spec.inputs.single().digits)
        assertEquals(0, spec.digits)

        val defaults = listOf(control.initial / control.scale)
        assertEquals(listOf(3.0), defaults)
        assertEquals(18.0, spec.evaluate(defaults), 0.0)
        assertEquals(12.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun marksAgreeWithTheExposedEdgesOfTheTiledSketch() {
        assertEquals(12.0, spec.minimum, 0.0)
        assertEquals(20.0, spec.maximum, 0.0)
        assertEquals(spec.minimum, spec.evaluate(listOf(0.0)), 0.0)
        assertEquals(spec.maximum, spec.evaluate(listOf(4.0)), 0.0)

        val body = (0..2).flatMap { x -> (0..2).map { y -> x to y } }
        val tabs = listOf(1 to -1, 3 to 1, 1 to 3, -1 to 1)
        for (tabCount in control.range) {
            val tiles = (body + tabs.take(tabCount)).toSet()
            val exposedEdges = tiles.sumOf { (x, y) ->
                listOf((x - 1) to y, (x + 1) to y, x to (y - 1), x to (y + 1)).count { it !in tiles }
            }
            val values = listOf(tabCount / control.scale)
            assertEquals(exposedEdges.toDouble(), spec.evaluate(values), 0.0)
            assertEquals(tiles.size.toDouble(), spec.companionValue(values), 0.0)
        }
    }

    @Test fun chartAddsOnlyWholeTabsAndNeverLosesMarks() {
        var previous = spec.minimum
        for (step in 0..120) {
            val x = control.range.last * step / 120.0
            val marks = spec.evaluate(listOf(x))
            assertTrue(marks in spec.minimum..spec.maximum && marks >= previous)
            assertEquals(0.0, marks % 2.0, 0.0)
            previous = marks
        }
        assertEquals(14.0, spec.evaluate(listOf(1.49)), 0.0)
        assertEquals(16.0, spec.evaluate(listOf(1.5)), 0.0)
    }
}
