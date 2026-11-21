package com.galaxyssi.chat

import kotlin.math.roundToInt

internal object HealthAtlasMuscleSatelliteFusionTallyTeachingModel {
    private const val DESCENDANT_ICONS = 8
    private const val MIN_STARTING_NUCLEUS_ICONS = 1
    private const val MAX_STARTING_NUCLEUS_ICONS = 12

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("muscle-satellite-fusion-tally-fused", 0..DESCENDANT_ICONS, 3),
                R.string.health_atlas_muscle_satellite_fusion_tally_fused, unit = "", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput(
                    "muscle-satellite-fusion-tally-starting",
                    MIN_STARTING_NUCLEUS_ICONS..MAX_STARTING_NUCLEUS_ICONS, 6,
                ),
                R.string.health_atlas_muscle_satellite_fusion_tally_starting, unit = "", digits = 0,
            ),
        ),
        axis = 0,
        unit = "",
        minimum = MIN_STARTING_NUCLEUS_ICONS.toDouble(),
        maximum = (MAX_STARTING_NUCLEUS_ICONS + DESCENDANT_ICONS).toDouble(),
        source = "https://discovery.ucl.ac.uk/id/eprint/1340766/",
        extraSource = "https://pmc.ncbi.nlm.nih.gov/articles/PMC4618654/",
        title = R.string.health_atlas_muscle_satellite_fusion_tally_title,
        scope = R.string.health_atlas_muscle_satellite_fusion_tally_scope,
        formula = R.string.health_atlas_muscle_satellite_fusion_tally_formula,
        companionTitle = R.string.health_atlas_muscle_satellite_fusion_tally_companion,
        entryIds = setOf("cell-muscle-satellite-cell"),
        evaluate = { (fused, starting) -> (starting.roundToInt() + fused.roundToInt()).toDouble() },
        companionValue = { (fused) -> (DESCENDANT_ICONS - fused.roundToInt()).toDouble() },
        digits = 0,
    )
}
