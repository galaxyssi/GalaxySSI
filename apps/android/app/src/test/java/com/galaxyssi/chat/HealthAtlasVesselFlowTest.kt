package com.galaxyssi.chat

import kotlin.math.PI
import org.junit.Assert.*
import org.junit.Test

class HealthAtlasVesselFlowTest {
    private val kind = HealthAtlasPhysiologyKind.VESSEL_FLOW
    @Test fun independentSiFixturesCoverConversionsAndExtremes() {
        val model = HealthAtlasVesselFlow()
        assertEquals(.017950485959955423, model.flowMlPerMinute, 1e-12)
        assertEquals(557.0879820361606, model.resistanceMmHgMinutesPerMl, 1e-9)
        assertEquals(9.523028571428572, model.meanSpeedMmPerSecond, 1e-10)
        assertEquals(19.046057142857144, model.centreSpeedMmPerSecond, 1e-10)
        assertEquals(1.333224, model.wallShearPascals, 1e-10)
        assertEquals(2.5130680343937595, HealthAtlasVesselFlow(20.0, .2, 20.0, 2.0).flowMlPerMinute, 1e-10)
        assertEquals(.00003272224003116874, HealthAtlasVesselFlow(1.0, .05, 100.0, 6.0).flowMlPerMinute, 1e-14)
    }
    @Test fun zeroPressureStopsFlowWithoutLosingFiniteResistance() {
        val model = HealthAtlasVesselFlow(pressureMmHg = 0.0)
        assertEquals(0.0, model.flowMlPerMinute, 0.0)
        assertEquals(0.0, model.meanSpeedMmPerSecond, 0.0)
        assertEquals(0.0, model.centreSpeedMmPerSecond, 0.0)
        assertEquals(0.0, model.wallShearPascals, 0.0)
        assertEquals(HealthAtlasVesselFlow().resistanceMmHgMinutesPerMl, model.resistanceMmHgMinutesPerMl, 0.0)
        assertTrue(HealthAtlasPhysiology(kind).withInput(0, 0).plotMaximum > 0)
    }
    @Test fun radiusPressureLengthAndViscosityHaveIndependentEffects() {
        val base = HealthAtlasVesselFlow()
        val wide = base.copy(radiusMm = .2)
        assertEquals(base.flowMlPerMinute * 16, wide.flowMlPerMinute, 1e-10)
        assertEquals(base.resistanceMmHgMinutesPerMl / 16, wide.resistanceMmHgMinutesPerMl, 1e-10)
        assertEquals(base.meanSpeedMmPerSecond * 4, wide.meanSpeedMmPerSecond, 1e-10)
        assertEquals(base.wallShearPascals * 2, wide.wallShearPascals, 1e-10)
        assertEquals(base.flowMlPerMinute * 2, base.copy(pressureMmHg = 20.0).flowMlPerMinute, 1e-10)
        assertEquals(base.flowMlPerMinute / 2, base.copy(lengthMm = 100.0).flowMlPerMinute, 1e-10)
        val viscous = base.copy(viscosityMilliPascalSeconds = 5.0)
        assertEquals(base.flowMlPerMinute * 3.5 / 5, viscous.flowMlPerMinute, 1e-10)
        assertEquals(base.wallShearPascals, viscous.wallShearPascals, 1e-10)
    }
    @Test fun circularProfileIntegratesToFlowAndHasNoSlipAtWall() {
        val model = HealthAtlasVesselFlow()
        val rings = 10000
        var volumeMm3PerSecond = 0.0
        for (i in 0 until rings) {
            val inner = i.toDouble() / rings; val outer = (i + 1.0) / rings
            val ringArea = PI * model.radiusMm * model.radiusMm * (outer * outer - inner * inner)
            val relative = (inner + outer) / 2
            volumeMm3PerSecond += ringArea * model.speedMmPerSecond(relative)
            assertEquals(model.speedMmPerSecond(relative), model.speedMmPerSecond(-relative), 0.0)
        }
        assertEquals(model.flowMlPerMinute, volumeMm3PerSecond * .06, 1e-9)
        assertEquals(2 * model.meanSpeedMmPerSecond, model.speedMmPerSecond(0.0), 0.0)
        assertEquals(0.0, model.speedMmPerSecond(1.0), 0.0)
        assertEquals(0.0, model.speedMmPerSecond(-1.0), 0.0)
    }
    @Test fun allControlCornersAndCurvesRemainFiniteAndWithinLabeledScale() {
        for (p in listOf(0, 1, 10, 20)) for (r in listOf(50, 101, 200))
            for (l in listOf(20, 50, 100)) for (m in listOf(20, 35, 60)) {
                val model = HealthAtlasPhysiology(kind, listOf(p, r, l, m))
                assertEquals(model.result, model.resultAt(model.input(1)), 0.0)
                assertTrue(model.result in 0.0..model.plotMaximum)
                assertTrue(model.plotMaximum <= kind.maximum)
                assertTrue(model.companionValue.isFinite() && model.companionValue > 0)
                assertEquals(p.toDouble(), model.result * model.companionValue, 1e-9)
                for (radius in 50..200) assertTrue(model.resultAt(radius / 1000.0) in 0.0..model.plotMaximum)
            }
    }
    @Test fun invalidNonfiniteAndMismatchedStoredValuesAreRejected() {
        for (bad in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, -1.0, 21.0))
            assertTrue(runCatching { HealthAtlasVesselFlow(pressureMmHg = bad) }.isFailure)
        for (bad in listOf(Double.NaN, Double.POSITIVE_INFINITY, 0.0, .049, .201))
            assertTrue(runCatching { HealthAtlasVesselFlow(radiusMm = bad) }.isFailure)
        for (bad in listOf(Double.NaN, Double.POSITIVE_INFINITY, 0.0, 19.0, 101.0))
            assertTrue(runCatching { HealthAtlasVesselFlow(lengthMm = bad) }.isFailure)
        for (bad in listOf(Double.NaN, Double.POSITIVE_INFINITY, 0.0, 1.9, 6.1))
            assertTrue(runCatching { HealthAtlasVesselFlow(viscosityMilliPascalSeconds = bad) }.isFailure)
        for (bad in listOf(Double.NaN, Double.POSITIVE_INFINITY, -1.01, 1.01))
            assertTrue(runCatching { HealthAtlasVesselFlow().speedMmPerSecond(bad) }.isFailure)
        for (id in listOf("blood-vessels", "arteries", "veins", "coronary-vessels")) {
            assertEquals(kind, HealthAtlasPhysiologyKind.forItem(id))
            assertEquals(listOf(10, 100, 50, 35), HealthAtlasPhysiology.restore(id, intArrayOf(10, 100, 50, 35))?.inputs)
            assertNull(HealthAtlasPhysiology.restore(id, intArrayOf(10, 100, 50)))
            assertNull(HealthAtlasPhysiology.restore(id, intArrayOf(10, 49, 50, 35)))
        }
        for (id in listOf("heart", "cardiovascular", "capillaries", "cell-vascular-endothelium", "unknown"))
            assertNotEquals(kind, HealthAtlasPhysiologyKind.forItem(id))
        assertNull(HealthAtlasPhysiology(HealthAtlasPhysiologyKind.POTASSIUM).vesselFlow)
    }
}
