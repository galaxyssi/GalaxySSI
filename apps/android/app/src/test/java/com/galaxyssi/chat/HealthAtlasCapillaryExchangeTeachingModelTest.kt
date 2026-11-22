package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasCapillaryExchangeTeachingModelTest {
    @Test fun exchangeUsesTheCapacityToFlowRatioNotEitherInputAlone() {
        val kind = HealthAtlasPhysiologyKind.CAPILLARY_EXCHANGE
        val model = HealthAtlasPhysiology(kind)
        assertEquals(63.2120558829, model.result, 1e-9)
        assertEquals(36.7879441171, model.companionValue, 1e-9)
        assertEquals(model.result, model.withInput(0, 40).withInput(1, 40).result, 1e-9)
        assertEquals(0.0, model.withInput(0, 0).result, 0.0)
        assertEquals(100.0, model.withInput(0, 0).companionValue, 0.0)
        assertTrue(model.withInput(0, 40).result > model.result)
        assertTrue(model.withInput(1, 40).result < model.result)
        for (capacity in kind.inputs[0].range) for (flow in kind.inputs[1].range) {
            val scenario = model.withInput(0, capacity).withInput(1, flow)
            assertTrue(scenario.result in 0.0..100.0)
            assertEquals(100.0, scenario.result + scenario.companionValue, 1e-10)
        }
    }

    @Test fun referenceModelIsLimitedToSystemicCapillaryExchange() {
        val kind = HealthAtlasPhysiologyKind.CAPILLARY_EXCHANGE
        for (id in listOf("capillaries", "tissue-vascular-endothelium", "cell-vascular-endothelial-cell")) {
            assertEquals(kind, HealthAtlasPhysiology.restore(id, intArrayOf(20, 20))?.kind)
        }
        assertNull(HealthAtlasPhysiology.restore("capillaries", intArrayOf(20, 0)))
        assertEquals(HealthAtlasPhysiologyKind.ALVEOLAR_DIFFUSION,
            HealthAtlasPhysiologyKind.forItem("pulmonary-capillaries"))
        assertEquals(HealthAtlasPhysiologyKind.VESSEL_FLOW, HealthAtlasPhysiologyKind.forItem("veins"))
    }
}
