package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasNerveTransitTest {
    private val kind = HealthAtlasPhysiologyKind.NERVE_TRANSIT

    @Test fun convertsCentimetresAndSecondsToMilliseconds() {
        val model = HealthAtlasPhysiology(kind)
        assertEquals(12.0, model.result, 1e-9)
        assertEquals(2.0, model.companionValue, 1e-9)
        assertEquals(30.0, model.plotMaximum, 1e-9)
        assertEquals(20.0, model.withInput(1, 120).plotMaximum, 1e-9)
        assertEquals(24.0, model.withInput(0, 120).result, 1e-9)
        assertEquals(6.0, model.withInput(1, 100).result, 1e-9)
        assertEquals(1500.0, HealthAtlasPhysiology(kind, listOf(150, 1)).result, 1e-9)
        assertEquals(10.0 / 12, HealthAtlasPhysiology(kind, listOf(10, 120)).result, 1e-9)
    }

    @Test fun restoresOnlyNervePathsAndRejectsZeroSpeed() {
        for (id in listOf("peripheral-nerves", "spinal-nerves", "cranial-nerves")) {
            val stored = HealthAtlasPhysiology.restore(id, intArrayOf(75, 30))!!
            assertEquals(kind, stored.kind)
            assertEquals(25.0, stored.result, 1e-9)
            assertNull(HealthAtlasPhysiology.restore(id, intArrayOf(75, 0)))
        }
        assertEquals(HealthAtlasPhysiologyKind.POTASSIUM, HealthAtlasPhysiologyKind.forItem("spinal-cord"))
        assertEquals(HealthAtlasPhysiologyKind.NEURAL_RELAY_DELAYS, HealthAtlasPhysiologyKind.forItem("ganglia"))
        assertEquals(HealthAtlasPhysiologyKind.FOLLICLE_SURFACE, HealthAtlasPhysiologyKind.forItem("ovaries"))
        assertNull(HealthAtlasPhysiology.restore("ganglia", intArrayOf(75, 30)))
    }
}
