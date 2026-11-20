package com.galaxyssi.chat

internal enum class HealthAtlasGas { OXYGEN, CARBON_DIOXIDE }
internal data class HealthAtlasGasGradient(val gas: HealthAtlasGas, val alveolar: Int, val incomingBlood: Int) {
    val towardBlood get() = alveolar > incomingBlood
    val difference get() = kotlin.math.abs(alveolar - incomingBlood)
}

/** Fixed textbook examples of partial pressure, not outputs of the ventilation model. */
internal object HealthAtlasGasExchange {
    const val SOURCE = "https://openstax.org/books/anatomy-and-physiology-2e/pages/22-4-gas-exchange"
    val gradients = listOf(HealthAtlasGasGradient(HealthAtlasGas.OXYGEN, 104, 40),
        HealthAtlasGasGradient(HealthAtlasGas.CARBON_DIOXIDE, 40, 45))
    fun supports(id: String) = id in setOf("alveoli", "respiratory-membrane", "pulmonary-capillaries")
    fun phase(value: Float) = if (value.isFinite()) value.coerceIn(0f, 1f) else 0f
    fun stage(value: Float) = (phase(value) * 4).toInt().coerceAtMost(3)
    fun position(gas: HealthAtlasGas, value: Float): Float = phase(value).let {
        if (gas == HealthAtlasGas.OXYGEN) it else 1f - it
    }
}
