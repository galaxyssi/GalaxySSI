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
}
