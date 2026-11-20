package com.galaxyssi.chat

internal enum class HealthAtlasBloodNode { TISSUES, RIGHT_HEART, LUNGS, LEFT_HEART }
internal data class HealthAtlasBloodLeg(val from: HealthAtlasBloodNode, val to: HealthAtlasBloodNode, val oxygenRich: Boolean)

/** Direction and relative oxygenation in a simplified adult double circulation. */
internal object HealthAtlasCirculation {
    const val SOURCE = "https://openstax.org/books/anatomy-and-physiology-2e/pages/19-1-heart-anatomy"
    val legs = listOf(
        HealthAtlasBloodLeg(HealthAtlasBloodNode.TISSUES, HealthAtlasBloodNode.RIGHT_HEART, false),
        HealthAtlasBloodLeg(HealthAtlasBloodNode.RIGHT_HEART, HealthAtlasBloodNode.LUNGS, false),
        HealthAtlasBloodLeg(HealthAtlasBloodNode.LUNGS, HealthAtlasBloodNode.LEFT_HEART, true),
        HealthAtlasBloodLeg(HealthAtlasBloodNode.LEFT_HEART, HealthAtlasBloodNode.TISSUES, true),
    )
    fun supports(id: String) = id in setOf("cardio", "heart", "atria", "ventricles", "heart-valves",
        "coronary-vessels", "blood-vessels", "arteries", "veins", "capillaries", "blood")
    fun phase(value: Float) = if (value.isFinite()) value.coerceIn(0f, 1f) else 0f
    fun stage(value: Float) = (phase(value) * legs.size).toInt().coerceAtMost(legs.lastIndex)
    fun fraction(value: Float) = phase(value) * legs.size - stage(value)
}
