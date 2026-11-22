package com.galaxyssi.chat

internal enum class HealthAtlasBreathingStage(val title: Int, val caption: Int) {
    INHALE(R.string.health_atlas_breathe_inhale, R.string.health_atlas_breathe_inhale_caption),
    REACH_ALVEOLUS(R.string.health_atlas_breathe_reach, R.string.health_atlas_breathe_reach_caption),
    DIFFUSE(R.string.health_atlas_breathe_diffuse, R.string.health_atlas_breathe_diffuse_caption),
    PERFUSE(R.string.health_atlas_breathe_perfuse, R.string.health_atlas_breathe_perfuse_caption),
    EXHALE(R.string.health_atlas_breathe_exhale, R.string.health_atlas_breathe_exhale_caption);

    val exhales get() = this == EXHALE

    fun closeUp(fraction: Float) = when (this) {
        REACH_ALVEOLUS -> ease((fraction - .12f) / .62f)
        DIFFUSE, PERFUSE -> 1f
        EXHALE -> 1f - ease(fraction / .35f)
        INHALE -> 0f
    }

    fun expansion(fraction: Float) = when (this) {
        INHALE -> ease(fraction)
        EXHALE -> 1f - ease(fraction)
        else -> 1f
    }

    private fun ease(value: Float) = value.coerceIn(0f, 1f).let { it * it * (3f - 2f * it) }
}
