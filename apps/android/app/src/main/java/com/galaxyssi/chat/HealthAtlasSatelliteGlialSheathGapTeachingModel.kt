package com.galaxyssi.chat

import kotlin.math.PI

internal object HealthAtlasSatelliteGlialSheathGapTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("satellite-glial-sheath-gap-radius", 40..80, 60, scale = 10.0),
                R.string.health_atlas_satellite_glial_sheath_gap_radius, "u", digits = 1,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("satellite-glial-sheath-gap-width", 0..5, 3, scale = 10.0),
                R.string.health_atlas_satellite_glial_sheath_gap_width, "u", digits = 1,
            ),
        ),
        axis = 1,
        unit = "u\u00B2",
        minimum = 0.0,
        maximum = 26.0,
        source = "https://advanced.onlinelibrary.wiley.com/doi/10.1002/advs.202511569",
        title = R.string.health_atlas_satellite_glial_sheath_gap_title,
        scope = R.string.health_atlas_satellite_glial_sheath_gap_scope,
        formula = R.string.health_atlas_satellite_glial_sheath_gap_formula,
        companionTitle = R.string.health_atlas_satellite_glial_sheath_gap_companion,
        entryIds = setOf("cell-satellite-glial-cell"),
        evaluate = { (radius, gap) -> PI * gap * (2 * radius + gap) },
        companionValue = { (radius, gap) -> radius + gap },
    )
}
