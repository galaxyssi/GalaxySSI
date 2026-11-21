package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasGametePathDistanceTeachingModelTest {
    private val spec = HealthAtlasGametePathDistanceTeachingModel.spec
    private val sperm = spec.inputs[0].control
    private val oocyte = spec.inputs[1].control

    @Test fun mapsOnlyTheTwoCellEntriesAndPlotsSpermShiftInPositionUnits() {
        assertEquals(setOf("cell-spermatozoon", "cell-oocyte-or-ovum"), spec.entryIds)
        assertEquals(0, spec.axis)
        assertEquals(listOf("PU", "PU"), spec.inputs.map { it.unit })
        assertEquals("PU", spec.unit)
    }

    @Test fun defaultsClosePartOfTheFixedStartingGap() {
        val defaults = spec.inputs.map { it.control.initial / it.control.scale }
        assertEquals(listOf(4.0, 2.0), defaults)
        assertEquals(10.0, spec.evaluate(defaults), 1e-9)
        assertEquals(16.0, spec.companionValue(defaults), 1e-9)
    }

    @Test fun allSliderPairsStayWithinThePlotBoundsWithoutContact() {
        assertEquals(0..8, sperm.range)
        assertEquals(0..6, oocyte.range)
        assertEquals(2.0, spec.minimum, 1e-9)
        assertEquals(16.0, spec.maximum, 1e-9)
        assertEquals(spec.maximum, remainingDistance(sperm.range.first, oocyte.range.first), 1e-9)
        assertEquals(spec.minimum, remainingDistance(sperm.range.last, oocyte.range.last), 1e-9)

        for (spermShift in sperm.range) {
            for (oocyteShift in oocyte.range) {
                val inputs = scaledShifts(spermShift, oocyteShift)
                assertTrue(spec.evaluate(inputs) in spec.minimum..spec.maximum)
                assertEquals(16.0, spec.companionValue(inputs), 1e-9)
            }
        }
    }

    @Test fun movingEitherIconInwardIndependentlyReducesTheGap() {
        for (spermShift in sperm.range) {
            for (oocyteShift in oocyte.range) {
                val distance = remainingDistance(spermShift, oocyteShift)
                if (spermShift < sperm.range.last) {
                    assertEquals(distance - 1.0, remainingDistance(spermShift + 1, oocyteShift), 1e-9)
                }
                if (oocyteShift < oocyte.range.last) {
                    assertEquals(distance - 1.0, remainingDistance(spermShift, oocyteShift + 1), 1e-9)
                }
            }
        }
        assertEquals(9.5, spec.evaluate(listOf(4.5, 2.0)), 1e-9)
    }

    private fun remainingDistance(spermShift: Int, oocyteShift: Int) =
        spec.evaluate(scaledShifts(spermShift, oocyteShift))

    private fun scaledShifts(spermShift: Int, oocyteShift: Int) =
        listOf(spermShift / sperm.scale, oocyteShift / oocyte.scale)
}
