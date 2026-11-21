package com.galaxyssi.chat

import kotlin.math.roundToInt

internal object HealthAtlasPlasmaCellSecretionTallyTeachingModel {
    private const val MAX_CELL_ICONS = 8
    private const val SYMBOLS_PER_ICON = 3

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("plasma-cell-secretion-tally-cells", 0..MAX_CELL_ICONS, 4),
                R.string.health_atlas_plasma_cell_secretion_tally_cells, unit = "", digits = 0,
            ),
        ),
        axis = 0,
        unit = "",
        minimum = 0.0,
        maximum = (MAX_CELL_ICONS * SYMBOLS_PER_ICON).toDouble(),
        source = "https://www.cancer.gov/publications/dictionaries/cancer-terms/def/plasma-cell",
        title = R.string.health_atlas_plasma_cell_secretion_tally_title,
        scope = R.string.health_atlas_plasma_cell_secretion_tally_scope,
        formula = R.string.health_atlas_plasma_cell_secretion_tally_formula,
        companionTitle = R.string.health_atlas_plasma_cell_secretion_tally_companion,
        entryIds = setOf("cell-plasma-cell"),
        evaluate = { (cells) -> (cells.roundToInt() * SYMBOLS_PER_ICON).toDouble() },
        companionValue = { SYMBOLS_PER_ICON.toDouble() },
        digits = 0,
    )
}
