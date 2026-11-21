package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasThymicBranchingTeachingModelTest {
    private val spec = HealthAtlasThymicBranchingTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val tallyControl = controls[0]
    private val percentControl = controls[1]

    @Test fun defaultsShowTheSelectedAndRemainingTiles() {
        val defaults = controls.map { it.initial / it.scale }

        assertEquals(
            setOf("thymus", "cell-helper-t-cell", "cell-cytotoxic-t-cell", "cell-regulatory-t-cell"),
            spec.entryIds,
        )
        assertEquals("thymic-branching-selected-percent", controls[spec.axis].key)
        assertEquals(listOf("tiles", "%"), spec.inputs.map { it.unit })
        assertEquals("tiles", spec.unit)
        assertEquals(listOf(80.0, 35.0), defaults)
        assertEquals(28.0, spec.evaluate(defaults), 0.0)
        assertEquals(52.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun sliderSettingsConserveWholeTilesWithinBounds() {
        val tallies = tallyControl.range.map { it / tallyControl.scale }
        val percentages = percentControl.range.map { it / percentControl.scale }
        assertEquals((20..200 step 20).map { it.toDouble() }, tallies)
        assertEquals((0..100 step 5).map { it.toDouble() }, percentages)
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(200.0, spec.maximum, 0.0)

        for (tally in tallies) {
            assertEquals(0.0, spec.evaluate(listOf(tally, 0.0)), 0.0)
            assertEquals(tally, spec.companionValue(listOf(tally, 0.0)), 0.0)
            assertEquals(tally, spec.evaluate(listOf(tally, 100.0)), 0.0)
            assertEquals(0.0, spec.companionValue(listOf(tally, 100.0)), 0.0)

            for (percent in percentages) {
                val values = listOf(tally, percent)
                val selected = spec.evaluate(values)
                val remaining = spec.companionValue(values)
                assertTrue(selected in spec.minimum..spec.maximum)
                assertTrue(remaining in 0.0..tally)
                assertEquals(selected.toInt().toDouble(), selected, 0.0)
                assertEquals(tally, selected + remaining, 0.0)
            }
        }
    }

    @Test fun chartRisesAndRemainingTallyFallsAsTheSelectedShareRises() {
        for (step in tallyControl.range) {
            val tally = step / tallyControl.scale
            val values = (0..120).map { listOf(tally, it * 100.0 / 120) }
            assertTrue(values.map(spec.evaluate).zipWithNext().all { (before, after) -> after > before })
            assertTrue(values.map(spec.companionValue).zipWithNext().all { (before, after) -> after < before })
        }

        assertEquals(34.2, spec.evaluate(listOf(80.0, 42.75)), 1e-9)
    }
}
