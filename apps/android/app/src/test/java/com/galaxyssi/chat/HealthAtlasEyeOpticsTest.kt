package com.galaxyssi.chat

import kotlin.math.abs
import org.junit.Assert.*
import org.junit.Test

class HealthAtlasEyeOpticsTest {
    private val kind = HealthAtlasPhysiologyKind.EYE_FOCUS

    @Test fun thinLensFixturesUseMetresAndReportSignedMillimetres() {
        assertEquals(17.001020061203672, HealthAtlasEyeOptics().imageDistanceMm, 1e-10)
        assertEquals(2.6078431372549034, HealthAtlasEyeOptics(.25, 55.0).offsetMm, 1e-10)
        assertEquals(-1.5758354755784065, HealthAtlasEyeOptics(6.0, 65.0).offsetMm, 1e-10)
        assertEquals(.24137931034482563, HealthAtlasEyeOptics(.5, 60.0).offsetMm, 1e-10)
        assertEquals(62.8235294117647, HealthAtlasEyeOptics(.25).targetPowerDiopters, 1e-10)
    }

    @Test fun hundredthDiopterControlMatchesRetinalPlaneAcrossTheObjectRange() {
        for (distance in 25..600) {
            val eye = HealthAtlasEyeOptics(distance / 100.0)
            val aligned = eye.copy(powerDiopters = eye.targetPowerSteps / 100.0)
            assertTrue(abs(aligned.offsetMm) < .002)
            assertEquals(HealthAtlasEyeOptics.FocusSide.AT_PLANE, aligned.focusSide)
            assertEquals(HealthAtlasEyeOptics.FocusSide.BEHIND, eye.copy(powerDiopters = 55.0).focusSide)
            assertEquals(HealthAtlasEyeOptics.FocusSide.IN_FRONT, eye.copy(powerDiopters = 65.0).focusSide)
        }
    }

    @Test fun raysCrossAtTheCalculatedImageAndSwapSidesPastIt() {
        for (eye in listOf(HealthAtlasEyeOptics(.25, 55.0), HealthAtlasEyeOptics(), HealthAtlasEyeOptics(6.0, 65.0))) {
            for (height in listOf(-1.0, 1.0)) {
                assertEquals(0.0, eye.rayHeight(-1000 * eye.distanceMetres, height), 1e-12)
                assertEquals(height, eye.rayHeight(0.0, height), 0.0)
                assertEquals(height / 2, eye.rayHeight(eye.imageDistanceMm / 2, height), 1e-12)
                assertEquals(0.0, eye.rayHeight(eye.imageDistanceMm, height), 1e-12)
                assertEquals(-height, eye.rayHeight(2 * eye.imageDistanceMm, height), 1e-12)
            }
        }
    }

    @Test fun morePowerBringsTheImageCloserAndNearObjectsNeedMorePower() {
        val close = HealthAtlasEyeOptics(.25, 60.0)
        val distant = close.copy(distanceMetres = 6.0)
        assertTrue(close.imageDistanceMm > distant.imageDistanceMm)
        assertTrue(close.targetPowerDiopters > distant.targetPowerDiopters)
        assertTrue(close.copy(powerDiopters = 65.0).imageDistanceMm < close.imageDistanceMm)
        val model = HealthAtlasPhysiology(kind, listOf(25, 6000))
        assertEquals(close.offsetMm, model.result, 0.0)
        assertEquals(model.result, model.resultAt(model.input(kind.axis)), 0.0)
    }

    @Test fun restorationRejectsInvalidOrUnrelatedInputs() {
        for (bad in listOf(Double.NaN, Double.POSITIVE_INFINITY, .24, 6.01))
            assertTrue(runCatching { HealthAtlasEyeOptics(distanceMetres = bad) }.isFailure)
        for (bad in listOf(Double.NaN, Double.NEGATIVE_INFINITY, 54.99, 65.01))
            assertTrue(runCatching { HealthAtlasEyeOptics(powerDiopters = bad) }.isFailure)
        for (id in listOf("eye", "lens")) {
            assertEquals(kind, HealthAtlasPhysiologyKind.forItem(id))
            assertEquals(listOf(25, 6500), HealthAtlasPhysiology.restore(id, intArrayOf(25, 6500))?.inputs)
            assertNull(HealthAtlasPhysiology.restore(id, intArrayOf(25, 6501)))
            assertNull(HealthAtlasPhysiology.restore(id, intArrayOf(25)))
        }
        for (id in listOf("ear", "cornea", "retina", "cell-rod-photoreceptor", "sensory"))
            assertNull(HealthAtlasPhysiology.restore(id, intArrayOf(25, 6500)))
    }
}
