package com.galaxyssi.chat

/** Steady-state solute mass balance, not water balance or a patient clearance estimate. */
internal object HealthAtlasRenal {
    data class Amounts(val filtered: Double, val reabsorbed: Double, val secreted: Double) {
        init {
            require(filtered.isFinite() && filtered >= 0 && reabsorbed.isFinite() && reabsorbed in 0.0..filtered)
            require(secreted.isFinite() && secreted >= 0 && (filtered - reabsorbed + secreted).isFinite())
        }
        val excreted get() = filtered - reabsorbed + secreted
    }
    fun amounts(filtered: Double, reabsorbedPercent: Double, secreted: Double): Amounts {
        require(filtered.isFinite() && filtered >= 0 && secreted.isFinite() && secreted >= 0)
        require(reabsorbedPercent.isFinite() && reabsorbedPercent in 0.0..100.0)
        val result = Amounts(filtered, filtered * (reabsorbedPercent / 100), secreted)
        require(result.excreted.isFinite())
        return result
    }
}
