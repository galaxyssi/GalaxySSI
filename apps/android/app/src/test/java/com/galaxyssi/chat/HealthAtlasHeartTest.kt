package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasHeartTest {
    @Test fun inletAndOutletValvesNeverOpenTogetherInTheFourStageModel() {
        val expected = listOf(setOf("tricuspid-valve", "mitral-valve"), emptySet(),
            setOf("pulmonary-valve", "aortic-valve"), emptySet())
        expected.forEachIndexed { stage, ids ->
            assertEquals(ids, HealthAtlasValve.entries.filter { it.openAt(stage) }.map { it.id }.toSet())
        }
        for (valve in HealthAtlasValve.entries) {
            assertTrue(HealthAtlasValve.supports(valve.id))
            assertFalse(HealthAtlasCirculation.supports(valve.id))
            assertTrue(runCatching { valve.openAt(4) }.isFailure)
        }
        assertTrue(HealthAtlasValve.supports("heart-valves"))
        assertFalse(HealthAtlasCirculation.supports("heart-valves"))
    }

    @Test fun fractionIsEjectedVolumeDividedByTheTotalVolumeBeforeEjection() {
        val model = HealthAtlasPhysiology(HealthAtlasPhysiologyKind.VENTRICULAR_EJECTION)
        assertEquals(130.0, model.companionValue, 0.0)
        assertEquals(100.0 * 70 / 130, model.result, 1e-9)
        assertEquals(50.0, model.withInput(0, 60).result, 1e-9)
        assertEquals(0.0, model.withInput(0, 0).result, 0.0)
        assertTrue(model.withInput(1, 100).result < model.result)
        assertTrue(model.withInput(0, 100).result > model.result)
    }

    @Test fun restoreAndChartUseOnlyAnExplicitVentricularModel() {
        val model = HealthAtlasPhysiology.restore("left-ventricle", intArrayOf(90, 60))!!
        assertEquals(60.0, model.result, 1e-9)
        assertEquals(model.result, model.resultAt(90.0), 1e-9)
        assertEquals(model.kind, HealthAtlasPhysiologyKind.forItem("right-ventricle"))
        assertNull(HealthAtlasPhysiology.restore("right-ventricle", intArrayOf(90, 0)))
        for (id in listOf("left-atrium", "aorta", "mitral-valve", "heart-valves", "tissue-cardiac-muscle"))
            assertNull(HealthAtlasPhysiology.restore(id, intArrayOf(90, 60)))
    }
}
