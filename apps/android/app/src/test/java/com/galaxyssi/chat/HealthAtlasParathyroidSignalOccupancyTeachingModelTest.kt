package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasParathyroidSignalOccupancyTeachingModelTest {
    private val spec = HealthAtlasParathyroidSignalOccupancyTeachingModel.spec
    private val controls = spec.inputs.map { it.control }
    private val signals = controls[0].let { control -> control.range.map { it / control.scale } }
    private val halfPoints = controls[1].let { control -> control.range.map { it / control.scale } }
    private val epsilon = 1e-9

    @Test fun defaultIsHalfOccupiedAndPlotsAgainstUnitlessSignal() {
        assertEquals(setOf("parathyroid-glands", "cell-parathyroid-chief-cell"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("", ""), spec.inputs.map { it.unit })
        assertEquals("%", spec.unit)
        assertEquals(0.0, spec.minimum, epsilon)
        assertEquals(100.0, spec.maximum, epsilon)

        val defaults = controls.map { it.initial / it.scale }
        assertEquals(listOf(2.0, 2.0), defaults)
        assertEquals(50.0, spec.evaluate(defaults), epsilon)
        assertEquals(50.0, spec.companionValue(defaults), epsilon)
    }

    @Test fun sliderExtremesRunFromNoBindingToBelowFullOccupancy() {
        assertEquals(0.0, signals.first(), epsilon)
        assertTrue(halfPoints.first() > 0.0)
        for (halfPoint in listOf(halfPoints.first(), halfPoints.last())) {
            val noSignal = listOf(signals.first(), halfPoint)
            assertEquals(0.0, spec.evaluate(noSignal), epsilon)
            assertEquals(100.0, spec.companionValue(noSignal), epsilon)
        }
        assertEquals(96.0, spec.evaluate(listOf(signals.last(), halfPoints.first())), epsilon)
        assertEquals(200.0 / 3.0, spec.evaluate(listOf(signals.last(), halfPoints.last())), epsilon)
    }

    @Test fun occupancyRisesWithSignalWithDiminishingGains() {
        for (halfPoint in halfPoints) {
            val occupied = signals.map { signal ->
                val values = listOf(signal, halfPoint)
                val bound = spec.evaluate(values)
                val unbound = spec.companionValue(values)
                assertTrue(bound in spec.minimum..<spec.maximum)
                assertTrue(unbound in spec.minimum..spec.maximum)
                assertEquals(100.0, bound + unbound, epsilon)
                bound
            }
            val gains = occupied.zipWithNext { before, after -> after - before }
            assertTrue(gains.all { it > 0.0 })
            assertTrue(gains.zipWithNext().all { (before, after) -> before > after })
        }
    }

    @Test fun increasingTheHalfPointLowersOccupancyAtPositiveSignal() {
        for (signal in signals.drop(1)) {
            val occupied = halfPoints.map { spec.evaluate(listOf(signal, it)) }
            assertTrue(occupied.zipWithNext().all { (before, after) -> before > after })
        }
    }
}
