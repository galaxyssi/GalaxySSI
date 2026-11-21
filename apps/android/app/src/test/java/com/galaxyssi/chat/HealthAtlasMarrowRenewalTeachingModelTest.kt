package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasMarrowRenewalTeachingModelTest {
    private val spec = HealthAtlasMarrowRenewalTeachingModel.spec
    private val controls = spec.inputs.map { it.control }

    @Test fun defaultsShowNetGainAndEndingCountForTheTwoAtlasEntries() {
        assertEquals(setOf("bone-marrow", "cell-hematopoietic-stem-cell"), spec.entryIds)
        assertEquals("marrow-renewal-added", controls[spec.axis].key)
        assertEquals(listOf("marrow-renewal-added", "marrow-renewal-left"), controls.map { it.key })
        assertEquals(listOf(0..12, 0..12), controls.map { it.range })
        assertEquals(listOf(0, 0), spec.inputs.map { it.digits })
        assertEquals(0, spec.digits)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(5.0, 3.0), defaults)
        assertEquals(2.0, spec.evaluate(defaults), 0.0)
        assertEquals(14.0, spec.companionValue(defaults), 0.0)
    }

    @Test fun emptyingAddingAndBalancingReachTheExpectedCounts() {
        val allLeave = listOf(0.0, 12.0)
        val onlyRenewal = listOf(12.0, 0.0)
        val balanced = listOf(12.0, 12.0)

        assertEquals(-12.0, spec.minimum, 0.0)
        assertEquals(12.0, spec.maximum, 0.0)
        assertEquals(spec.minimum, spec.evaluate(allLeave), 0.0)
        assertEquals(spec.maximum, spec.evaluate(onlyRenewal), 0.0)
        assertEquals(0.0, spec.evaluate(balanced), 0.0)
        assertEquals(0.0, spec.companionValue(allLeave), 0.0)
        assertEquals(24.0, spec.companionValue(onlyRenewal), 0.0)
        assertEquals(12.0, spec.companionValue(balanced), 0.0)
    }

    @Test fun allWholeIconInputsFollowSingleIntervalBookkeeping() {
        val (renewal, departures) = controls
        for (renewalStep in renewal.range) {
            for (departureStep in departures.range) {
                val added = renewalStep / renewal.scale
                val left = departureStep / departures.scale
                val values = listOf(added, left)
                val net = spec.evaluate(values)
                val ending = spec.companionValue(values)
                assertEquals(added - left, net, 0.0)
                assertTrue(net in spec.minimum..spec.maximum)
                assertEquals(12.0 + net, ending, 0.0)
                assertTrue(ending in 0.0..24.0)
                if (renewalStep < renewal.range.last) {
                    assertEquals(net + 1.0, spec.evaluate(listOf(added + 1.0, left)), 0.0)
                }
            }
        }
    }

    @Test fun chartSamplesStayWholeAndDoNotDecreaseAsRenewalIncreases() {
        val (renewal, departures) = controls
        val low = renewal.range.first / renewal.scale
        val high = renewal.range.last / renewal.scale
        for (departureStep in departures.range) {
            val left = departureStep / departures.scale
            var previous = spec.evaluate(listOf(low, left))
            for (step in 1..120) {
                val x = low + (high - low) * step / 120
                val current = spec.evaluate(listOf(x, left))
                assertTrue(current in spec.minimum..spec.maximum)
                assertEquals(current.toInt().toDouble(), current, 0.0)
                assertTrue(current >= previous)
                previous = current
            }
        }

        assertEquals(1.0, spec.evaluate(listOf(4.49, 3.0)), 0.0)
        assertEquals(2.0, spec.evaluate(listOf(4.5, 3.0)), 0.0)
    }
}
