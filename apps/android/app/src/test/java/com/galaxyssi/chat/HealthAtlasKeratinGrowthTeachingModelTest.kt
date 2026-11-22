package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasKeratinGrowthTeachingModelTest {
    private val spec = HealthAtlasKeratinGrowthTeachingModel.spec
    private val time = spec.inputs[0].control
    private val rate = spec.inputs[1].control
    private val epsilon = 1e-9

    @Test fun coversOnlyHairEntriesAndPlotsLengthAgainstElapsedDays() {
        assertEquals(setOf("hair", "hair-follicles", "cell-hair-matrix-cell"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("d", "mm/d"), spec.inputs.map { it.unit })
        assertEquals("mm", spec.unit)
    }

    @Test fun multipliesElapsedTimeByTheConstantExampleRate() {
        val defaults = scaled(time.initial, rate.initial)
        assertEquals(listOf(8.0, 0.5), defaults)
        assertEquals(4.0, spec.evaluate(defaults), epsilon)
        assertEquals(2.0, spec.companionValue(defaults), epsilon)

        val other = scaled(7, 4)
        assertEquals(2.8, spec.evaluate(other), epsilon)
        assertEquals(2.5, spec.companionValue(other), epsilon)
    }

    @Test fun zeroTimeAndMaximumInputsReachTheChartBounds() {
        assertEquals(0.0, spec.minimum, epsilon)
        for (rawRate in rate.range) {
            assertEquals(spec.minimum, spec.evaluate(scaled(time.range.first, rawRate)), epsilon)
        }
        assertEquals(16.0, spec.maximum, epsilon)
        assertEquals(spec.maximum, spec.evaluate(scaled(time.range.last, rate.range.last)), epsilon)
        assertEquals(5.0, spec.companionValue(scaled(time.initial, rate.range.first)), epsilon)
        assertEquals(1.25, spec.companionValue(scaled(time.initial, rate.range.last)), epsilon)
    }

    @Test fun allSliderPairsStayInBoundsAndMoreTimeOrRateAddsLength() {
        for (rawTime in time.range) {
            for (rawRate in rate.range) {
                val values = scaled(rawTime, rawRate)
                val length = spec.evaluate(values)
                val daysPerMm = spec.companionValue(values)
                assertTrue(length in spec.minimum..spec.maximum)
                if (rawTime > time.range.first) {
                    val earlier = scaled(rawTime - 1, rawRate)
                    assertTrue(length > spec.evaluate(earlier))
                    assertEquals(daysPerMm, spec.companionValue(earlier), epsilon)
                }
                if (rawRate > rate.range.first) {
                    val slower = scaled(rawTime, rawRate - 1)
                    if (rawTime > time.range.first) assertTrue(length > spec.evaluate(slower))
                    assertTrue(daysPerMm < spec.companionValue(slower))
                }
            }
        }
    }

    private fun scaled(rawTime: Int, rawRate: Int) = listOf(rawTime / time.scale, rawRate / rate.scale)
}
