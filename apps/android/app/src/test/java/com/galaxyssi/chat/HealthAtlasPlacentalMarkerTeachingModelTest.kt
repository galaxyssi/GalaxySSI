package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasPlacentalMarkerTeachingModelTest {
    private val kind = HealthAtlasPhysiologyKind.PLACENTAL_MARKER

    @Test fun bothSidesConserveTheMarkerAndStopAtEqualAmounts() {
        val initial = HealthAtlasPhysiology(kind)
        assertEquals(20.0, initial.result, 0.0)
        assertEquals(60.0, initial.companionValue, 0.0)
        for (start in kind.inputs[0].range) for (progress in kind.inputs[1].range) {
            val state = initial.withInput(0, start).withInput(1, progress)
            assertTrue(state.result in kind.minimum..kind.maximum)
            assertEquals(start.toDouble(), state.result + state.companionValue, 1e-9)
            assertTrue(state.result <= state.companionValue)
            if (progress == 0) assertEquals(0.0, state.result, 0.0)
            if (progress == 100) assertEquals(state.result, state.companionValue, 1e-9)
        }
    }

    @Test fun animationKeepsTheSameTotalWhileShowingOnlyMarkerTransfer() {
        val frame = HealthAtlasPlacentalMarkerTeachingModel::atPhase
        assertEquals(HealthAtlasPlacentalMarkerTeachingModel.Amounts(80.0, 0.0), frame(80.0, 20.0, 0f))
        assertEquals(HealthAtlasPlacentalMarkerTeachingModel.Amounts(70.0, 10.0), frame(80.0, 20.0, .5f))
        assertEquals(HealthAtlasPlacentalMarkerTeachingModel.Amounts(60.0, 20.0), frame(80.0, 20.0, 1f))
        assertEquals(HealthAtlasPlacentalMarkerTeachingModel.Amounts(80.0, 0.0), frame(80.0, 0.0, .5f))
        assertEquals(setOf("placenta", "cell-trophoblast"), kind.teaching?.entryIds)
        assertEquals(HealthAtlasPhysiologyKind.CAPILLARY_EXCHANGE, HealthAtlasPhysiologyKind.forItem("capillaries"))
    }
}
