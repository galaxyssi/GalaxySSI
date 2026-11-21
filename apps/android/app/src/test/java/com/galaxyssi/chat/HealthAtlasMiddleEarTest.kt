package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasMiddleEarTest {
    private val kind = HealthAtlasPhysiologyKind.MIDDLE_EAR

    @Test fun nominalAndExtremeFixturesSeparatePressureRatioFromDecibels() {
        val normal = HealthAtlasMiddleEar()
        assertEquals(17.1875, normal.areaRatio, 1e-10)
        assertEquals(22.34375, normal.pressureRatio, 1e-10)
        assertEquals(26.983121269623492, normal.pressureGainDb, 1e-10)
        assertEquals(.044755244755244755, normal.volumeVelocityRatio, 1e-10)
        assertEquals(7.0, HealthAtlasMiddleEar(35.0, 5.0, 1.0).pressureRatio, 1e-10)
        assertEquals(35.56302500767287, HealthAtlasMiddleEar(75.0, 2.0, 1.6).pressureGainDb, 1e-10)
    }

    @Test fun modelConservesThePressureVolumeVelocityProductAtAllCorners() {
        for (input in listOf(35, 55, 75)) for (output in listOf(20, 32, 50)) for (lever in listOf(100, 130, 160)) {
            val model = HealthAtlasPhysiology(kind, listOf(input, output, lever))
            val ear = requireNotNull(model.middleEar)
            assertEquals(1.0, ear.pressureRatio * ear.volumeVelocityRatio, 1e-12)
            assertEquals(ear.pressureRatio, model.result, 1e-12)
            assertEquals(ear.pressureGainDb, model.companionValue, 1e-12)
            assertTrue(ear.pressureRatio in 7.0..60.0)
            assertTrue(ear.volumeVelocityRatio in 0.0..1.0)
        }
    }

    @Test fun theThreeControlsAffectPressureInTheExpectedDirections() {
        val model = HealthAtlasMiddleEar()
        assertTrue(model.copy(membraneAreaMm2 = 75.0).pressureRatio > model.pressureRatio)
        assertTrue(model.copy(footplateAreaMm2 = 5.0).pressureRatio < model.pressureRatio)
        assertTrue(model.copy(leverRatio = 1.6).pressureRatio > model.pressureRatio)
        val selected = HealthAtlasPhysiology(kind, listOf(64, 40, 140))
        assertEquals(22.4, selected.result, 1e-10)
        assertEquals(selected.result, selected.resultAt(64.0), 1e-12)
    }

    @Test fun invalidInputsAndUnrelatedEntriesNeverRestoreTheModel() {
        for (bad in listOf(Double.NaN, Double.POSITIVE_INFINITY, 34.0, 76.0))
            assertTrue(runCatching { HealthAtlasMiddleEar(membraneAreaMm2 = bad) }.isFailure)
        for (bad in listOf(Double.NaN, Double.NEGATIVE_INFINITY, 0.0, 1.9, 5.1))
            assertTrue(runCatching { HealthAtlasMiddleEar(footplateAreaMm2 = bad) }.isFailure)
        for (bad in listOf(Double.NaN, Double.POSITIVE_INFINITY, .99, 1.61))
            assertTrue(runCatching { HealthAtlasMiddleEar(leverRatio = bad) }.isFailure)
        for (id in listOf("ear", "middle-ear")) {
            assertEquals(kind, HealthAtlasPhysiologyKind.forItem(id))
            assertEquals(listOf(35, 20, 160), HealthAtlasPhysiology.restore(id, intArrayOf(35, 20, 160))?.inputs)
            assertNull(HealthAtlasPhysiology.restore(id, intArrayOf(35, 20)))
            assertNull(HealthAtlasPhysiology.restore(id, intArrayOf(35, 0, 160)))
        }
        for (id in listOf("external-ear", "vestibular-apparatus"))
            assertNotEquals(id, kind, HealthAtlasPhysiologyKind.forItem(id))
        for (id in listOf("inner-ear", "cochlea", "cell-inner-ear-hair-cell")) {
            assertEquals(id, HealthAtlasPhysiologyKind.COCHLEAR_FREQUENCY, HealthAtlasPhysiologyKind.forItem(id))
            assertNull(HealthAtlasPhysiology.restore(id, intArrayOf(35, 20, 160)))
            assertEquals(listOf(50), HealthAtlasPhysiology.restore(id, intArrayOf(50))?.inputs)
        }
    }
}
