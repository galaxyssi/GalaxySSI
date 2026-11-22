package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasDiaphragmTeachingModelTest {
    @Test fun volumeUsesCentimetersAfterConvertingTheDisplacementFromMillimeters() {
        val kind = HealthAtlasPhysiologyKind.DIAPHRAGM_DISPLACEMENT
        val model = HealthAtlasPhysiology(kind)
        assertEquals("mL", kind.unit)
        assertEquals(216.0, model.result, 0.0)
        assertEquals(18.0, model.companionValue, 0.0)
        assertEquals(0.0, model.withInput(0, 0).result, 0.0)
        assertEquals(750.0, model.withInput(0, 30).withInput(1, 250).result, 0.0)
        for (area in kind.inputs[1].range) {
            val scenario = model.withInput(1, area)
            assertTrue(scenario.resultAt(30.0) in kind.minimum..kind.maximum)
            assertEquals(scenario.companionValue, scenario.resultAt(1.0) - scenario.resultAt(0.0), 1e-9)
        }
    }

    @Test fun diaphragmGeometryDoesNotReplaceTheRespiratoryVentilationModel() {
        assertEquals(HealthAtlasPhysiologyKind.DIAPHRAGM_DISPLACEMENT,
            HealthAtlasPhysiology.restore("diaphragm", intArrayOf(12, 180))?.kind)
        assertNull(HealthAtlasPhysiology.restore("diaphragm", intArrayOf(31, 180)))
        assertEquals(HealthAtlasPhysiologyKind.VENTILATION, HealthAtlasPhysiologyKind.forItem("respiratory"))
        assertEquals(HealthAtlasPhysiologyKind.VENTILATION, HealthAtlasPhysiologyKind.forItem("lungs"))
    }
}
