package com.galaxyssi.chat

internal enum class HealthAtlasBeatStage(val title: Int, val caption: Int) {
    FILLING(R.string.health_atlas_beat_fill, R.string.health_atlas_beat_fill_caption),
    ATRIAL_SQUEEZE(R.string.health_atlas_beat_atrial, R.string.health_atlas_beat_atrial_caption),
    PRESSURE_RISE(R.string.health_atlas_beat_pressure, R.string.health_atlas_beat_pressure_caption),
    EJECTION(R.string.health_atlas_beat_eject, R.string.health_atlas_beat_eject_caption),
    RELAXATION(R.string.health_atlas_beat_relax, R.string.health_atlas_beat_relax_caption);

    val fillsVentricles: Boolean get() = this == FILLING || this == ATRIAL_SQUEEZE
    val ejects: Boolean get() = this == EJECTION

    fun valveOpenness(valve: HealthAtlasValve, fraction: Float): Float = when {
        valve.openAt(0) && fillsVentricles -> when (this) {
            FILLING -> ease(fraction / .14f)
            else -> ease((1f - fraction) / .14f)
        }
        valve.openAt(2) && ejects -> ease(fraction / .14f) * ease((1f - fraction) / .14f)
        else -> 0f
    }

    // Illustration envelope, not a volume, pressure or time measurement.
    fun ventricularNarrowing(fraction: Float): Float = when (this) {
        FILLING -> 1f - .84f * ease(fraction)
        ATRIAL_SQUEEZE -> .16f * (1f - ease(fraction))
        PRESSURE_RISE -> 0f
        EJECTION -> ease(fraction)
        RELAXATION -> 1f
    }

    private fun ease(value: Float) = value.coerceIn(0f, 1f).let { it * it * (3f - 2f * it) }
}
