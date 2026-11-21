package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasPleuralSlideTeachingModelTest {
    private val kind = HealthAtlasPhysiologyKind.PLEURAL_SLIDE

    @Test fun relativeSpeedAndSeparationControlTheModelShear() {
        val model = HealthAtlasPhysiology(kind)
        assertEquals(10.0, model.result, 1e-9)
        assertEquals(.1, model.companionValue, 1e-9)
        for (speed in kind.inputs[0].range) for (gap in kind.inputs[1].range) {
            val state = model.withInput(0, speed).withInput(1, gap)
            assertTrue(state.result in kind.minimum..kind.maximum)
            assertEquals(speed.toDouble(), state.result * state.input(1), 1e-9)
            assertEquals(.01 * state.result, state.companionValue, 1e-9)
            assertEquals(state.result, state.resultAt(speed.toDouble()), 1e-9)
        }
        assertEquals(0.0, model.withInput(0, 0).result, 0.0)
        assertEquals(setOf("pleura"), kind.teaching?.entryIds)
        assertEquals(HealthAtlasPhysiologyKind.VENTILATION, HealthAtlasPhysiologyKind.forItem("lungs"))
    }

    @Test fun theArtUsesTheTwoSurfaceVelocitiesAndLinearInteriorValues() {
        val speed = HealthAtlasPleuralSlideTeachingModel::relativeVelocity
        assertEquals(0.0, speed(18.0, 0f), 0.0)
        assertEquals(9.0, speed(18.0, .5f), 0.0)
        assertEquals(18.0, speed(18.0, 1f), 0.0)
        assertEquals(0.0, speed(0.0, .75f), 0.0)
    }
}
