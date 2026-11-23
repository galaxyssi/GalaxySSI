package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasMechanismCloseUpTest {
    @Test fun thePressureTraceRespectsValveDirectionThroughoutEachStage() {
        for (stage in HealthAtlasBeatStage.entries) {
            for (i in 1..19) {
                val pressure = HealthAtlasBeatPressureTrace.sample(stage, i / 20f)
                val mitral = pressure.atrium > pressure.ventricle
                val aortic = pressure.ventricle > pressure.aorta
                assertEquals(stage.name, stage.fillsVentricles, mitral)
                assertEquals(stage.name, stage.ejects, aortic)
            }
        }
    }

    @Test fun pressureTraceRemainsContinuousAcrossChaptersAndWhenReplayed() {
        val stages = HealthAtlasBeatStage.entries
        for (stage in stages) {
            val next = stages[(stage.ordinal + 1) % stages.size]
            val end = HealthAtlasBeatPressureTrace.sample(stage, 1f)
            val start = HealthAtlasBeatPressureTrace.sample(next, 0f)
            assertEquals(start.atrium, end.atrium, 1e-6f)
            assertEquals(start.ventricle, end.ventricle, 1e-6f)
            assertEquals(start.aorta, end.aorta, 1e-6f)
        }
    }

    @Test fun tipLinkDeflectionControlsTheRelativeOpeningInBothDirections() {
        val resting = HealthAtlasSoundStage.relativeChannelOpening(0f)
        val toward = HealthAtlasSoundStage.relativeChannelOpening(1f)
        val away = HealthAtlasSoundStage.relativeChannelOpening(-1f)
        assertTrue(away in 0f..<resting)
        assertTrue(toward > resting && toward <= 1f)
        assertEquals(toward, HealthAtlasSoundStage.relativeChannelOpening(4f), 0f)
    }

    @Test fun myosinCycleMovesFromBindingToStrokeToAtpReleaseAndReset() {
        val geometry = HealthAtlasMovementGeometry
        val cycle = (0..3).map { geometry.crossBridge((it + .5f) / 4f) }
        assertEquals(listOf(
            HealthAtlasCrossBridge.BIND,
            HealthAtlasCrossBridge.PULL,
            HealthAtlasCrossBridge.DETACH,
            HealthAtlasCrossBridge.RESET,
        ), cycle)
        assertEquals(HealthAtlasCrossBridge.RESET, geometry.crossBridge(1f))
        assertTrue(geometry.sarcomereHalfWidth(1f) < geometry.sarcomereHalfWidth(0f))
    }

    @Test fun theSchematicVoltageRisesAfterPotassiumChannelsStartClosing() {
        val diagram = HealthAtlasInsulinDiagram
        assertEquals(0f, diagram.relativeDepolarization(.18f), 0f)
        assertTrue(diagram.potassiumOpen(.18f) < diagram.potassiumOpen(0f))
        for (i in 1..100) {
            val t = i / 100f
            val previous = (i - 1) / 100f
            assertTrue(diagram.potassiumOpen(t) <= diagram.potassiumOpen(previous))
            assertTrue(diagram.relativeDepolarization(t) >= diagram.relativeDepolarization(previous))
        }
        assertEquals(0f, diagram.potassiumOpen(1f), 0f)
        assertEquals(1f, diagram.relativeDepolarization(1f), 0f)
    }

    @Test fun lightLowersRodMessengerBeforeTheChannelClosesAndTransmitterReleaseFalls() {
        val rod = HealthAtlasRodResponse
        assertEquals(0f, rod.light(0f), 0f)
        assertEquals(1f, rod.opening(0f), 0f)
        assertEquals(1f, rod.release(0f), 0f)
        assertTrue(rod.light(.29f) > 0f)
        assertEquals(1f, rod.messenger(.29f), 0f)
        assertTrue(rod.messenger(.37f) < 1f)
        assertEquals(1f, rod.opening(.37f), 0f)
        assertTrue(rod.opening(.55f) < 1f)
        assertEquals(1f, rod.release(.55f), 0f)
        assertEquals(0f, rod.opening(1f), 0f)
        assertTrue(rod.release(1f) in 0f.. .25f)
    }
}
