package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasElbowTest {
    private val kind = HealthAtlasPhysiologyKind.ELBOW_BALANCE
    @Test fun openStaxExampleMatchesUnroundedEquilibrium() {
        val result = HealthAtlasElbow.forces(4.0, 38.0, 40.0)
        assertEquals(470.4, result.muscle, 1e-9)
        assertEquals(406.7, result.jointDown, 1e-9)
        assertEquals(18.816, result.torque, 1e-9)
        assertEquals(63.7, result.armWeight + result.loadWeight, 1e-9)
        assertEquals(result.muscle, HealthAtlasPhysiology(kind).result, 1e-9)
    }
    @Test fun independentFixturesCoverUnitsAndNoExternalLoad() {
        assertEquals(98.0, HealthAtlasElbow.forces(0.0, 38.0, 40.0).muscle, 1e-9)
        assertEquals(73.5, HealthAtlasElbow.forces(0.0, 38.0, 40.0).jointDown, 1e-9)
        assertEquals(215.6, HealthAtlasElbow.forces(1.5, 32.0, 40.0).muscle, 1e-9)
        assertEquals(176.4, HealthAtlasElbow.forces(1.5, 32.0, 40.0).jointDown, 1e-9)
        assertEquals(2646.0, HealthAtlasElbow.forces(10.0, 50.0, 20.0).muscle, 1e-9)
    }
    @Test fun forcesAndMomentsBalanceAcrossControlDomain() {
        for (load in 0..100 step 5) for (distance in 20..50 step 3) for (arm in 20..60 step 4) {
            val result = HealthAtlasElbow.forces(load / 10.0, distance.toDouble(), arm.toDouble())
            assertEquals(0.0, result.muscle - result.jointDown - result.armWeight - result.loadWeight, 1e-9)
            assertEquals(result.armWeight * .16 + result.loadWeight * result.loadArmMetres,
                result.muscle * result.muscleArmMetres, 1e-9)
            assertTrue(result.jointDown >= 0.0)
            val model = HealthAtlasPhysiology(kind, listOf(load, distance, arm))
            assertTrue(model.result in 0.0..model.plotMaximum)
            assertTrue(model.plotMaximum <= kind.maximum)
        }
    }
    @Test fun leverChangesHaveTheExpectedDirection() {
        val model = HealthAtlasPhysiology(kind)
        assertEquals(model.result / 1.5, model.withInput(2, 60).result, 1e-9)
        assertTrue(model.withInput(1, 50).result > model.result)
        assertTrue(model.withInput(0, 50).result > model.result)
        assertEquals(model.withInput(0, 0).result, model.withInput(0, 0).withInput(1, 50).result, 1e-9)
        assertEquals(1100.0, model.plotMaximum, 1e-9)
        assertEquals(2700.0, model.withInput(1, 50).withInput(2, 20).plotMaximum, 1e-9)
    }
    @Test fun invalidAndNonfiniteValuesAreRejected() {
        for (value in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, -1.0, 11.0))
            assertTrue(runCatching { HealthAtlasElbow.forces(value, 38.0, 40.0) }.isFailure)
        for (value in listOf(Double.NaN, Double.POSITIVE_INFINITY, 0.0, 19.0, 51.0))
            assertTrue(runCatching { HealthAtlasElbow.forces(4.0, value, 40.0) }.isFailure)
        for (value in listOf(Double.NaN, Double.POSITIVE_INFINITY, 0.0, 19.0, 61.0))
            assertTrue(runCatching { HealthAtlasElbow.forces(4.0, 38.0, value) }.isFailure)
    }
    @Test fun restorationIsStrictAndMappingIsElbowSpecific() {
        for (id in listOf("skeletal", "muscle", "biceps-brachii", "humerus", "radius", "ulna")) {
            assertEquals(kind, HealthAtlasPhysiologyKind.forItem(id))
            assertEquals(470.4, requireNotNull(HealthAtlasPhysiology.restore(id, intArrayOf(40, 38, 40))).result, 1e-9)
            assertNull(HealthAtlasPhysiology.restore(id, intArrayOf(40, 38, 0)))
            assertNull(HealthAtlasPhysiology.restore(id, intArrayOf(40, 38)))
        }
        for (id in listOf("triceps-brachii", "cell-skeletal-myocyte", "tendons", "cell-osteoblast"))
            assertNull(id, HealthAtlasPhysiologyKind.forItem(id))
        val femur = requireNotNull(HealthAtlasPhysiology.restore("femur", intArrayOf(6, 20, 60)))
        assertEquals(HealthAtlasPhysiologyKind.BONE_BENDING, femur.kind)
        assertNull(femur.elbowForces)
        assertNull(HealthAtlasPhysiology(HealthAtlasPhysiologyKind.POTASSIUM).elbowForces)
    }
}
