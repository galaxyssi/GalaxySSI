package com.galaxyssi.chat

import kotlin.math.roundToInt

internal object HealthAtlasMastCellGranuleTallyTeachingModel {
    private const val STORED_ICONS = 20

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("mast-cell-granule-tally-released", 0..STORED_ICONS, 6),
                R.string.health_atlas_mast_cell_granule_tally_released, unit = "", digits = 0,
            ),
        ),
        axis = 0,
        unit = "%",
        minimum = 0.0,
        maximum = 100.0,
        source = "https://www.histologyguide.com/EM-view/EM-110-mast-cell/03-photo-1.html",
        title = R.string.health_atlas_mast_cell_granule_tally_title,
        scope = R.string.health_atlas_mast_cell_granule_tally_scope,
        formula = R.string.health_atlas_mast_cell_granule_tally_formula,
        companionTitle = R.string.health_atlas_mast_cell_granule_tally_companion,
        entryIds = setOf("cell-mast-cell"),
        evaluate = { (released) -> 100.0 * released.roundToInt() / STORED_ICONS },
        companionValue = { (released) -> (STORED_ICONS - released.roundToInt()).toDouble() },
        digits = 0,
    )
}
