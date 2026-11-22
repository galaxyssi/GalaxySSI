package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasMelaninDistributionTeachingModelTest {
    private val spec = HealthAtlasMelaninDistributionTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-12

    @Test fun defaultsShareTwelvePacketUnitsAmongFourCells() {
        assertEquals(setOf("cell-melanocyte"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("PPU", ""), spec.inputs.map { it.unit })
        assertEquals("PPU/cell", spec.unit)
        assertEquals(listOf(0, 0), spec.inputs.map { it.digits })

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(12.0, 4.0), defaults)
        assertEquals(3.0, spec.evaluate(defaults), epsilon)
        assertEquals(12.0, spec.companionValue(defaults), epsilon)
    }

    @Test fun zeroAmountAndMaximumAmountAtRecipientExtremesFitTheChart() {
        val (amount, cells) = controls
        val low = amount.range.first / amount.scale
        val high = amount.range.last / amount.scale
        val few = cells.range.first / cells.scale
        val many = cells.range.last / cells.scale

        assertEquals(0.0, spec.minimum, epsilon)
        assertEquals(12.0, spec.maximum, epsilon)
        assertEquals(spec.minimum, spec.evaluate(listOf(low, few)), epsilon)
        assertEquals(spec.minimum, spec.evaluate(listOf(low, many)), epsilon)
        assertEquals(3.0, spec.evaluate(listOf(high, many)), epsilon)
        assertEquals(spec.maximum, spec.evaluate(listOf(high, few)), epsilon)
    }

    @Test fun addingRecipientsReducesPositiveSharesWithoutChangingTheTotal() {
        val (amount, cells) = controls
        for (total in amount.range.map { it / amount.scale }) {
            val shares = cells.range.map { count ->
                val recipients = count / cells.scale
                val values = listOf(total, recipients)
                val share = spec.evaluate(values)
                assertEquals(total, spec.companionValue(values), epsilon)
                assertEquals(total, share * recipients, epsilon)
                share
            }
            assertTrue(shares.zipWithNext().all { (before, after) ->
                if (total == 0.0) before == after else before > after
            })
        }
    }

    @Test fun chartSamplesRiseSmoothlyAndDoublingRecipientsHalvesTheSlope() {
        val (amount, cells) = controls
        val low = amount.range.first / amount.scale
        val high = amount.range.last / amount.scale
        val defaultCells = cells.initial / cells.scale

        // Match the parameter sweep used by the shared chart.
        val samples = (0..120).map { low + (high - low) * it / 120 }
        val defaultCurve = samples.map { spec.evaluate(listOf(it, defaultCells)) }
        assertTrue(defaultCurve.zipWithNext().all { (before, after) -> before < after })

        for ((packetUnits, share) in samples.zip(defaultCurve)) {
            assertTrue(share in spec.minimum..spec.maximum)
            assertEquals(packetUnits / defaultCells, share, epsilon)
            assertEquals(share / 2, spec.evaluate(listOf(packetUnits, defaultCells * 2)), epsilon)
        }
    }
}
