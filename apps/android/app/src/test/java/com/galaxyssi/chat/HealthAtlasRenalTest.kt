package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasRenalTest {
    @Test fun exampleSeparatesReabsorptionFromExcretion() {
        val value = HealthAtlasRenal.amounts(100.0, 90.0, 10.0)
        assertEquals(90.0, value.reabsorbed, 1e-12)
        assertEquals(20.0, value.excreted, 1e-12)
    }
    @Test fun allTeachingControlsConserveSoluteMass() {
        for (filtered in 0..200 step 5) for (percent in 0..100) for (secreted in 0..100 step 10) {
            val value = HealthAtlasRenal.amounts(filtered.toDouble(), percent.toDouble(), secreted.toDouble())
            assertEquals(value.filtered + value.secreted, value.reabsorbed + value.excreted, 1e-9)
            assertTrue(value.excreted >= 0.0)
        }
    }
    @Test fun zeroAndFullRecoveryDoNotInventFlow() {
        assertEquals(0.0, HealthAtlasRenal.amounts(0.0, 100.0, 0.0).excreted, 0.0)
        assertEquals(0.0, HealthAtlasRenal.amounts(200.0, 100.0, 0.0).excreted, 0.0)
        assertEquals(50.0, HealthAtlasRenal.amounts(0.0, 90.0, 50.0).excreted, 0.0)
    }
    @Test fun invalidNumbersCannotReachTheDisplay() {
        for (bad in listOf(Double.NaN, Double.NEGATIVE_INFINITY, Double.POSITIVE_INFINITY, -1.0)) {
            assertTrue(runCatching { HealthAtlasRenal.amounts(bad, 90.0, 10.0) }.isFailure)
            assertTrue(runCatching { HealthAtlasRenal.amounts(100.0, bad, 10.0) }.isFailure)
            assertTrue(runCatching { HealthAtlasRenal.amounts(100.0, 90.0, bad) }.isFailure)
        }
        assertTrue(runCatching { HealthAtlasRenal.amounts(100.0, 101.0, 0.0) }.isFailure)
        assertTrue(runCatching { HealthAtlasRenal.amounts(Double.MAX_VALUE, 0.0, Double.MAX_VALUE) }.isFailure)
        assertTrue(runCatching { HealthAtlasRenal.Amounts(10.0, 11.0, 0.0) }.isFailure)
    }
    @Test fun modelCurveAndBalanceUseTheSameEquationWithoutMappingToUnrelatedCells() {
        val model = HealthAtlasPhysiology(HealthAtlasPhysiologyKind.RENAL_EXCRETION, listOf(150, 80, 20))
        assertEquals(model.result, model.renalAmounts!!.excreted, 0.0)
        assertEquals(model.result, model.resultAt(80.0), 0.0)
        for (id in listOf("proximal-tubule", "nephron-loop", "distal-tubule"))
            assertEquals(model, HealthAtlasPhysiology.restore(id, intArrayOf(150, 80, 20)))
        assertNull(HealthAtlasPhysiology.restore("distal-tubule", intArrayOf(150, 101, 20)))
        assertNull(HealthAtlasPhysiology(HealthAtlasPhysiologyKind.VENTILATION).renalAmounts)
        assertNull(HealthAtlasPhysiology.restore("cell-podocyte", intArrayOf(150, 80, 20)))
        assertEquals(HealthAtlasPhysiologyKind.GLOMERULAR_FILTRATION, HealthAtlasPhysiologyKind.forItem("cell-podocyte"))
        assertNull(HealthAtlasPhysiology(HealthAtlasPhysiologyKind.GLOMERULAR_FILTRATION).renalAmounts)
        assertEquals(HealthAtlasPhysiologyKind.CAPILLARY_SUPPORT_SURFACE, HealthAtlasPhysiologyKind.forItem("cell-mesangial-cell"))
    }
}
