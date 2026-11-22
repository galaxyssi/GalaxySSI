package com.galaxyssi.chat

import kotlin.math.roundToInt

internal object HealthAtlasMacrophageClearanceTallyTeachingModel {
    private const val MAX_OUTSIDE_ICONS = 12
    private const val MAX_DRAWN_SPACES = 8

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("macrophage-clearance-tally-outside", 0..MAX_OUTSIDE_ICONS, 8),
                R.string.health_atlas_macrophage_clearance_tally_outside, unit = "", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("macrophage-clearance-tally-spaces", 0..MAX_DRAWN_SPACES, 5),
                R.string.health_atlas_macrophage_clearance_tally_spaces, unit = "", digits = 0,
            ),
        ),
        axis = 0,
        unit = "",
        minimum = 0.0,
        maximum = MAX_DRAWN_SPACES.toDouble(),
        source = "https://www.cancer.gov/publications/dictionaries/cancer-terms/def/macrophage",
        title = R.string.health_atlas_macrophage_clearance_tally_title,
        scope = R.string.health_atlas_macrophage_clearance_tally_scope,
        formula = R.string.health_atlas_macrophage_clearance_tally_formula,
        companionTitle = R.string.health_atlas_macrophage_clearance_tally_companion,
        entryIds = setOf("cell-macrophage"),
        evaluate = { (outside, spaces) -> movedInside(outside, spaces).toDouble() },
        companionValue = { (outside, spaces) -> (outside.roundToInt() - movedInside(outside, spaces)).toDouble() },
        digits = 0,
    )

    private fun movedInside(outside: Double, spaces: Double) = minOf(outside.roundToInt(), spaces.roundToInt())
}
