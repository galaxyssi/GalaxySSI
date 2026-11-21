package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasPlasmaCellSecretionTallyTeachingModelTest {
    private val spec = HealthAtlasPlasmaCellSecretionTallyTeachingModel.spec
    private val control = spec.inputs.single().control

    @Test fun fourDefaultIconsContributeTwelveOutputSymbols() {
        assertEquals(setOf("cell-plasma-cell"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals("plasma-cell-secretion-tally-cells", control.key)
        assertEquals(0..8, control.range)
        assertEquals(0, spec.inputs.single().digits)
        assertEquals(0, spec.digits)

        val defaults = listOf(control.initial / control.scale)
        assertEquals(listOf(4.0), defaults)
        assertEquals(12.0, spec.evaluate(defaults), 0.0)
        assertEquals(3.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun eachIconAddsExactlyThreeSymbolsWithinChartBounds() {
        assertEquals(0.0, spec.minimum, 0.0)
        assertEquals(24.0, spec.maximum, 0.0)
        assertEquals(spec.minimum, spec.evaluate(listOf(0.0)), 0.0)
        assertEquals(spec.maximum, spec.evaluate(listOf(8.0)), 0.0)
        for (count in control.range) {
            val values = listOf(count / control.scale)
            assertEquals(3.0 * count, spec.evaluate(values), 0.0)
            assertEquals(3.0, spec.companionValue(values), 0.0)
        }
    }

    @Test fun fractionalChartSamplesDoNotCreatePartialGroups() {
        var previous = spec.minimum
        for (step in 0..120) {
            val x = control.range.last * step / 120.0
            val symbols = spec.evaluate(listOf(x))
            assertTrue(symbols in spec.minimum..spec.maximum && symbols >= previous)
            assertEquals(0.0, symbols % 3.0, 0.0)
            previous = symbols
        }
        assertEquals(9.0, spec.evaluate(listOf(3.49)), 0.0)
        assertEquals(12.0, spec.evaluate(listOf(3.5)), 0.0)
    }
}
