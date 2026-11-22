package com.galaxyssi.chat

import kotlin.math.PI
import kotlin.math.cos

internal object HealthAtlasVocalCycleTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(HealthAtlasInput("vocal-cycle-frequency", 60..240, 140),
                R.string.health_atlas_vocal_cycles_frequency, "Hz", digits = 0),
            HealthAtlasTeachingInput(HealthAtlasInput("vocal-cycle-duration", 5..30, 20),
                R.string.health_atlas_vocal_cycles_duration, "ms", digits = 0),
        ),
        axis = 0,
        unit = "cycles",
        minimum = 0.0,
        maximum = 7.2,
        source = "https://www.nidcd.nih.gov/news/multimedia/how-does-human-body-produce-voice-and-speech-text-version",
        title = R.string.health_atlas_vocal_cycles_title,
        scope = R.string.health_atlas_vocal_cycles_scope,
        formula = R.string.health_atlas_vocal_cycles_formula,
        companionTitle = R.string.health_atlas_vocal_cycles_period,
        entryIds = setOf("larynx"),
        evaluate = { (frequency, timeMs) -> frequency * timeMs / 1000.0 },
        companionValue = { (frequency, _) -> 1000.0 / frequency },
    )

    /** One ideal opening-and-closing cycle. This is a relative area, not a sound signal. */
    fun relativeOpening(cycles: Double, phase: Float) = (.5 - .5 * cos(2 * PI * cycles * phase)).toFloat()
}
