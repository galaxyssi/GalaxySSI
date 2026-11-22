package com.galaxyssi.chat

import kotlin.math.exp

/** Frozen joint inputs from a synthetic tracer example, not estimates from a population. */
internal enum class HealthAtlasComparisonScenario(val outward: Int, val returning: Int) {
    CONTROL(0, 0),
    EXCHANGE(30, 15),
    FASTER(100, 40);

    val distribution = HealthAtlasDistribution(outward, returning, elimination = 10)
}

internal data class HealthAtlasComparisonPoint(
    val one: Double,
    val two: HealthAtlasDistributionAmounts,
    val low: Double,
    val high: Double,
) {
    val centralGap get() = two.central - one
}

internal data class HealthAtlasModelComparison(
    val scenario: HealthAtlasComparisonScenario = HealthAtlasComparisonScenario.EXCHANGE,
    val quarterHours: Int = 16,
) {
    init { require(quarterHours in 0..192) }
    val hours get() = quarterHours / 4.0
    val point get() = at(hours)

    fun at(hours: Double): HealthAtlasComparisonPoint {
        require(hours.isFinite() && hours in 0.0..48.0)
        val scenarios = HealthAtlasComparisonScenario.entries.map { it.distribution.at(hours) }
        return HealthAtlasComparisonPoint(
            100.0 * exp(-scenario.distribution.k10 * hours),
            scenarios[scenario.ordinal],
            scenarios.minOf { it.central },
            scenarios.maxOf { it.central },
        )
    }
}
