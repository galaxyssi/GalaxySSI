package com.galaxyssi.chat

import kotlin.math.exp
import kotlin.math.expm1
import kotlin.math.sqrt

/** Linear two-compartment amounts after a normalized central bolus; no patient parameters. */
internal data class HealthAtlasDistribution(
    val outward: Int = 30, val returning: Int = 15, val elimination: Int = 10, val quarterHours: Int = 16,
) {
    init { require(outward in 0..300 && returning in 0..300 && elimination in 0..300 && quarterHours in 0..192) }
    val k12 get() = outward / 100.0
    val k21 get() = returning / 100.0
    val k10 get() = elimination / 100.0
    val hours get() = quarterHours / 4.0
    val amounts get() = at(hours)

    fun at(hours: Double): HealthAtlasDistributionAmounts {
        require(hours.isFinite() && hours in 0.0..48.0)
        if (hours == 0.0) return HealthAtlasDistributionAmounts(100.0, 0.0, 0.0)
        if (outward == 0) {
            val central = 100.0 * exp(-k10 * hours)
            return HealthAtlasDistributionAmounts(central, 0.0, 100.0 - central)
        }
        val sum = k10 + k12 + k21
        val delta = sqrt((k10 + k12 - k21) * (k10 + k12 - k21) + 4.0 * k12 * k21)
        val alpha = (sum + delta) / 2.0
        val beta = k10 * k21 / alpha
        val slow = exp(-beta * hours)
        val fast = exp(-alpha * hours)
        val central = 100.0 * ((alpha - k21) * fast + (k21 - beta) * slow) / delta
        // expm1 avoids cancellation near t=0; the zero-transfer repeated-root case is handled above.
        val peripheral = 100.0 * k12 * slow * -expm1(-delta * hours) / delta
        return HealthAtlasDistributionAmounts(central.coerceIn(0.0, 100.0), peripheral.coerceIn(0.0, 100.0),
            (100.0 - central - peripheral).coerceIn(0.0, 100.0))
    }

    companion object {
        const val SOURCE = "https://doi.org/10.12793/tcp.2019.27.2.43"
    }
}

internal data class HealthAtlasDistributionAmounts(val central: Double, val peripheral: Double, val eliminated: Double)

internal enum class HealthAtlasDrugMode { SINGLE, TWO }

internal data class HealthAtlasDrugState(val mode: HealthAtlasDrugMode = HealthAtlasDrugMode.SINGLE,
    val distribution: HealthAtlasDistribution = HealthAtlasDistribution()) {
    fun encode() = intArrayOf(mode.ordinal, distribution.outward, distribution.returning,
        distribution.elimination, distribution.quarterHours)
    companion object {
        fun restore(values: IntArray?): HealthAtlasDrugState? = values?.takeIf { it.size == 5 }?.let {
            runCatching { HealthAtlasDrugState(HealthAtlasDrugMode.entries[it[0]],
                HealthAtlasDistribution(it[1], it[2], it[3], it[4])) }.getOrNull()
        }
    }
}
