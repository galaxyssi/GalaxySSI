package com.galaxyssi.chat

import kotlin.math.atan2
import kotlin.math.hypot

internal object HealthAtlasVestibularTiltTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("vestibular-tilt-lateral", 0..100, 30, 100.0),
                label = R.string.health_atlas_vestibular_tilt_lateral,
                unit = "g",
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("vestibular-tilt-downward", 50..150, 100, 100.0),
                label = R.string.health_atlas_vestibular_tilt_downward,
                unit = "g",
            ),
        ),
        axis = 0,
        unit = "\u00b0",
        minimum = 0.0,
        maximum = 65.0,
        source = "https://www.nature.com/articles/19303",
        title = R.string.health_atlas_vestibular_tilt_title,
        scope = R.string.health_atlas_vestibular_tilt_scope,
        formula = R.string.health_atlas_vestibular_tilt_formula,
        companionTitle = R.string.health_atlas_vestibular_tilt_magnitude,
        entryIds = setOf("vestibular-apparatus"),
        evaluate = { (lateral, downward) -> Math.toDegrees(atan2(lateral, downward)) },
        companionValue = { (lateral, downward) -> hypot(lateral, downward) },
        extraSource = "https://www.ncbi.nlm.nih.gov/books/NBK10792/",
    )
}
