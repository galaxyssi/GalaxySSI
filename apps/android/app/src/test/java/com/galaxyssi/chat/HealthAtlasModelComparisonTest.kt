package com.galaxyssi.chat

import kotlin.math.exp
import org.junit.Assert.*
import org.junit.Test

class HealthAtlasModelComparisonTest {
    @Test fun independentFourHourFixtureBoundsTheDefaultScenario() {
        val point = HealthAtlasModelComparison().point
        // Central amount from expm(A * 4) * [100, 0, 0] for the exchange and faster presets.
        assertEquals(31.31146654418996, point.two.central, 1e-10)
        assertEquals(23.34020536954366, point.low, 1e-10)
        assertEquals(100.0 * exp(-0.4), point.one, 1e-12)
        assertEquals(point.one, point.high, 1e-12)
        assertEquals(-35.72053805937397, point.centralGap, 1e-10)
    }

    @Test fun noExchangeReducesExactlyToTheSingleCompartmentControl() {
        val control = HealthAtlasModelComparison(HealthAtlasComparisonScenario.CONTROL)
        for (quarter in 0..192) {
            val point = control.copy(quarterHours = quarter).point
            assertEquals(point.one, point.two.central, 0.0)
            assertEquals(0.0, point.two.peripheral, 0.0)
            assertEquals(0.0, point.centralGap, 0.0)
        }
    }

    @Test fun eachScenarioConservesTheInitialAmountAndSharesThePresetRange() {
        for (quarter in 0..192) {
            val points = HealthAtlasComparisonScenario.entries.map { HealthAtlasModelComparison(it, quarter).point }
            val lower = points.minOf { it.two.central }
            val upper = points.maxOf { it.two.central }
            points.forEach { point ->
                assertEquals(lower, point.low, 0.0)
                assertEquals(upper, point.high, 0.0)
                assertEquals(points.first().one, point.one, 0.0)
                assertEquals(100.0, point.two.central + point.two.peripheral + point.two.eliminated, 1e-10)
            }
        }
    }

    @Test fun boundsAndIndependentSavedStateAreEnforced() {
        val state = HealthAtlasDrugState(HealthAtlasDrugMode.COMPARISON, HealthAtlasDistribution(63, 20, 10, 41),
            HealthAtlasModelComparison(HealthAtlasComparisonScenario.FASTER, 23))
        assertEquals(state, HealthAtlasDrugState.restore(state.encode()))
        assertEquals(state.copy(comparison = HealthAtlasModelComparison()), HealthAtlasDrugState.restore(
            intArrayOf(1, 63, 20, 10, 41))?.copy(mode = HealthAtlasDrugMode.COMPARISON))
        assertNull(HealthAtlasDrugState.restore(state.encode().apply { this[5] = 3 }))
        assertNull(HealthAtlasDrugState.restore(state.encode().apply { this[6] = 193 }))
        assertThrows(IllegalArgumentException::class.java) { HealthAtlasModelComparison(quarterHours = -1) }
        assertThrows(IllegalArgumentException::class.java) { state.comparison.at(Double.NaN) }
    }
}
