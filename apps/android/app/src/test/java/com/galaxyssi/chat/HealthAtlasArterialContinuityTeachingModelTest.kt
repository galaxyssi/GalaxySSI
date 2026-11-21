package com.galaxyssi.chat

import kotlin.math.PI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasArterialContinuityTeachingModelTest {
    @Test fun speedTimesAreaConservesTheChosenFlow() {
        val kind = HealthAtlasPhysiologyKind.ARTERIAL_CONTINUITY
        val start = HealthAtlasPhysiology(kind)
        assertEquals(PI * 1.44, start.companionValue, 1e-10)
        assertEquals(70.0, start.result * start.companionValue, 1e-10)
        for (diameter in kind.inputs[0].range) for (flow in kind.inputs[1].range) {
            val model = start.withInput(0, diameter).withInput(1, flow)
            assertTrue(model.result in kind.minimum..kind.maximum)
            assertEquals(flow.toDouble(), model.result * model.companionValue, 1e-9)
        }
    }

    @Test fun largerLumenQuadraticallyDecreasesSpeedAtFixedFlow() {
        val start = HealthAtlasPhysiology(HealthAtlasPhysiologyKind.ARTERIAL_CONTINUITY)
        val narrow = start.withInput(0, 20)
        val wide = start.withInput(0, 40)
        assertEquals(4 * wide.result, narrow.result, 1e-9)
        assertTrue(narrow.withInput(1, 110).result > narrow.result)
        assertEquals(0.0, wide.withInput(1, 0).result, 0.0)
        assertEquals(setOf("aorta", "pulmonary-trunk"), start.kind.teaching?.entryIds)
        assertEquals(HealthAtlasPhysiologyKind.VESSEL_FLOW, HealthAtlasPhysiologyKind.forItem("arteries"))
    }
}
