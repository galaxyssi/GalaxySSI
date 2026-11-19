package com.galaxyssi.chat

import kotlin.math.pow

/** Fixed-exponent equilibrium teaching model, not a measured saturation or a clinical prediction. */
internal object HealthAtlasOxygen {
    data class Amounts(val bound: Double, val dissolved: Double) {
        val total get() = bound + dissolved
    }

    fun saturation(pressure: Double, p50: Double): Double {
        require(pressure.isFinite() && pressure >= 0 && p50.isFinite() && p50 > 0)
        // Reciprocal form avoids infinity/infinity at large pressure ratios. PO2 = 0 is exact.
        return if (pressure == 0.0) 0.0 else 1.0 / (1.0 + (p50 / pressure).pow(2.7))
    }

    fun amounts(pressure: Double, p50: Double, hemoglobinGramsPerLiter: Double): Amounts {
        require(hemoglobinGramsPerLiter.isFinite() && hemoglobinGramsPerLiter >= 0)
        val fraction = saturation(pressure, p50)
        // Hb g/L -> g/dL; both outputs are mL O2 per dL of whole blood.
        return Amounts(1.34 * (hemoglobinGramsPerLiter / 10.0) * fraction, 0.0031 * pressure)
    }
}
