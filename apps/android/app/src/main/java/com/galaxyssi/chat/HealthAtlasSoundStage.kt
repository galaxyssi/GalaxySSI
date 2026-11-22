package com.galaxyssi.chat

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin

internal enum class HealthAtlasSoundStage(val title: Int, val caption: Int) {
    SOUND(R.string.health_atlas_hear_sound, R.string.health_atlas_hear_sound_caption),
    MIDDLE_EAR(R.string.health_atlas_hear_middle, R.string.health_atlas_hear_middle_caption),
    COCHLEA(R.string.health_atlas_hear_cochlea, R.string.health_atlas_hear_cochlea_caption),
    HAIR_CELL(R.string.health_atlas_hear_hair, R.string.health_atlas_hear_hair_caption),
    NERVE(R.string.health_atlas_hear_nerve, R.string.health_atlas_hear_nerve_caption);

    companion object {
        fun oscillation(progress: Float, delay: Float = 0f): Float =
            sin((progress * 3f - delay) * 2 * PI).toFloat()

        // A moving teaching packet, not a frequency response or speed measurement.
        fun packet(position: Float, progress: Float): Float {
            val center = progress * .92f
            val envelope = (1f - abs(position - center) / .42f).coerceIn(0f, 1f)
            return envelope * oscillation(progress, position * 2.8f)
        }
    }
}
