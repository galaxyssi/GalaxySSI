package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasGastricPrecursorBalanceTeachingModelTest {
    private val spec = HealthAtlasGastricPrecursorBalanceTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val epsilon = 1e-10

    @Test fun defaultsSplitTheStartingAmountIntoConvertedAndRemainingShares() {
        assertEquals(setOf("cell-gastric-chief-cell", "cell-gastric-parietal-cell"), spec.entryIds)
        assertEquals(listOf("gastric-precursor-amount", "gastric-precursor-converted-percent"), controls.map { it.key })
        assertEquals(listOf(0..20, 0..100), controls.map { it.range })
        assertEquals(listOf("MU", "%"), spec.inputs.map { it.unit })
        assertEquals("MU", spec.unit)
        assertEquals(1, spec.axis)
        assertEquals(0.0, spec.minimum, epsilon)
        assertEquals(20.0, spec.maximum, epsilon)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(12.0, 35.0), defaults)
        assertEquals(4.2, spec.evaluate(defaults), epsilon)
        assertEquals(7.8, spec.companionValue(defaults), epsilon)
    }

    @Test fun zeroAmountAndZeroOrFullConversionReachTheExpectedLimits() {
        for (percent in controls[1].range) {
            val empty = listOf(0.0, percent / controls[1].scale)
            assertEquals(0.0, spec.evaluate(empty), epsilon)
            assertEquals(0.0, spec.companionValue(empty), epsilon)
        }
        val none = listOf(20.0, 0.0)
        assertEquals(spec.minimum, spec.evaluate(none), epsilon)
        assertEquals(20.0, spec.companionValue(none), epsilon)
        val all = listOf(20.0, 100.0)
        assertEquals(spec.maximum, spec.evaluate(all), epsilon)
        assertEquals(0.0, spec.companionValue(all), epsilon)
    }

    @Test fun chartIncreasesConversionAndDecreasesRemainingWithoutChangingTheTotal() {
        val (amountControl, percentControl) = controls
        val firstPercent = percentControl.range.first / percentControl.scale
        val lastPercent = percentControl.range.last / percentControl.scale
        for (amountStep in amountControl.range) {
            val amount = amountStep / amountControl.scale
            var previousConverted = 0.0
            var previousRemaining = amount
            for (step in 1..120) {
                val percent = firstPercent + (lastPercent - firstPercent) * step / 120.0
                val values = listOf(amount, percent)
                val converted = spec.evaluate(values)
                val remaining = spec.companionValue(values)
                assertTrue(converted in spec.minimum..spec.maximum)
                assertTrue(converted in 0.0..amount && remaining in 0.0..amount)
                assertEquals(amount, converted + remaining, epsilon)
                if (amount > 0.0) {
                    assertTrue(converted > previousConverted)
                    assertTrue(remaining < previousRemaining)
                }
                previousConverted = converted
                previousRemaining = remaining
            }
        }
    }
}
