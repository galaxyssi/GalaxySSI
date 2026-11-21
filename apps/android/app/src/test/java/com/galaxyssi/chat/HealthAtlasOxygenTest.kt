package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasOxygenTest {
    private val defaults = HealthAtlasPhysiology(HealthAtlasPhysiologyKind.OXYGEN_BINDING)

    @Test fun halfSaturationAndZeroPressureAreExact() {
        for (p50 in listOf(15.0, 26.8, 40.0)) {
            assertEquals(0.5, HealthAtlasOxygen.saturation(p50, p50), 0.0)
            assertEquals(0.0, HealthAtlasOxygen.saturation(0.0, p50), 0.0)
            assertEquals(0.0, HealthAtlasOxygen.amounts(0.0, p50, 150.0).total, 0.0)
        }
        assertEquals(26.8, defaults.input(1), 1e-9)
        assertEquals(50.0, defaults.resultAt(26.8), 1e-9)
    }

    @Test fun contentConvertsGramsPerLiterAndSaturationFractionOnlyOnce() {
        val half = HealthAtlasOxygen.amounts(26.8, 26.8, 150.0)
        assertEquals(10.05, half.bound, 1e-9)
        assertEquals(0.08308, half.dissolved, 1e-9)
        assertEquals(10.13308, half.total, 1e-9)
        assertEquals(97.2220233, defaults.result, .0000001)
        assertEquals(19.8516267, defaults.companionValue, .0000001)
        val noHemoglobin = HealthAtlasOxygen.amounts(100.0, 26.8, 0.0)
        assertEquals(0.0, noHemoglobin.bound, 0.0)
        assertEquals(0.31, noHemoglobin.total, 1e-9)
    }

    @Test fun hemoglobinChangesContentButNotTheSaturationCurve() {
        val low = defaults.withInput(2, 75)
        assertEquals(defaults.result, low.result, 0.0)
        for (pressure in 0..150) assertEquals(defaults.resultAt(pressure.toDouble()), low.resultAt(pressure.toDouble()), 0.0)
        assertEquals(defaults.oxygenAmounts!!.bound / 2, low.oxygenAmounts!!.bound, 1e-9)
        assertEquals(defaults.oxygenAmounts!!.dissolved, low.oxygenAmounts!!.dissolved, 0.0)
        assertTrue(low.companionValue < defaults.companionValue)
    }

    @Test fun higherP50LowersAffinityAndMovesTheCurveRight() {
        val highP50 = defaults.withInput(1, 400)
        assertTrue(highP50.result < defaults.result)
        assertEquals(50.0, highP50.resultAt(40.0), 0.0)
        assertTrue(highP50.companionValue < defaults.companionValue)
        for (p50 in 150..400 step 5) for (pressure in 0..150) {
            val fraction = HealthAtlasOxygen.saturation(pressure.toDouble(), p50 / 10.0)
            assertTrue(fraction.isFinite() && fraction in 0.0..1.0)
        }
    }

    @Test fun invalidParametersAreRejectedAndExtremeFiniteRatiosRemainStable() {
        for (value in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, -1.0)) {
            assertTrue(runCatching { HealthAtlasOxygen.saturation(value, 26.8) }.isFailure)
            assertTrue(runCatching { HealthAtlasOxygen.saturation(100.0, value) }.isFailure)
            assertTrue(runCatching { HealthAtlasOxygen.amounts(100.0, 26.8, value) }.isFailure)
        }
        assertTrue(runCatching { HealthAtlasOxygen.saturation(100.0, 0.0) }.isFailure)
        assertEquals(1.0, HealthAtlasOxygen.saturation(Double.MAX_VALUE, Double.MIN_VALUE), 0.0)
        assertEquals(0.0, HealthAtlasOxygen.saturation(Double.MIN_VALUE, Double.MAX_VALUE), 0.0)
        assertTrue(HealthAtlasOxygen.amounts(Double.MAX_VALUE, 26.8, Double.MAX_VALUE).total.isFinite())
    }

    @Test fun savedStateIsScopedToBloodAndErythrocytes() {
        for (id in listOf("blood", "cell-erythrocyte")) {
            assertEquals(defaults, HealthAtlasPhysiology.restore(id, intArrayOf(100, 268, 150)))
            assertNull(HealthAtlasPhysiology.restore(id, intArrayOf(100, 26, 150)))
            assertNull(HealthAtlasPhysiology.restore(id, intArrayOf(100, 268)))
        }
        assertEquals(HealthAtlasPhysiologyKind.IMMUNE_COMPOSITION, HealthAtlasPhysiologyKind.forItem("cell-neutrophil"))
        assertNull(HealthAtlasPhysiology.restore("cell-neutrophil", intArrayOf(100, 268, 150)))
        assertNull(HealthAtlasPhysiologyKind.forItem("cell-platelet"))
        assertNull(HealthAtlasPhysiology(HealthAtlasPhysiologyKind.POTASSIUM).oxygenAmounts)
        assertEquals(2, defaults.kind.sources.size)
    }
}
