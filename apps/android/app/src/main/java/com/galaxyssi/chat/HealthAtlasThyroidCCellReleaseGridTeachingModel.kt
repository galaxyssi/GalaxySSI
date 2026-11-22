package com.galaxyssi.chat

import kotlin.math.roundToInt

internal object HealthAtlasThyroidCCellReleaseGridTeachingModel {
    private const val ICONS_PER_ROW = 5
    private const val MAX_ROWS = 4

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("thyroid-c-cell-release-grid-moved", 0..ICONS_PER_ROW, 2),
                R.string.health_atlas_thyroid_c_cell_release_grid_moved, unit = "", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("thyroid-c-cell-release-grid-rows", 1..MAX_ROWS, 3),
                R.string.health_atlas_thyroid_c_cell_release_grid_rows, unit = "", digits = 0,
            ),
        ),
        axis = 0,
        unit = "",
        minimum = 0.0,
        maximum = (MAX_ROWS * ICONS_PER_ROW).toDouble(),
        source = "https://www.jstage.jst.go.jp/article/endocrine1927/59/9/59_1244/_article/-char/en",
        extraSource = "https://zoomify.luc.edu/endocrine/lumc195-21/popup.html",
        title = R.string.health_atlas_thyroid_c_cell_release_grid_title,
        scope = R.string.health_atlas_thyroid_c_cell_release_grid_scope,
        formula = R.string.health_atlas_thyroid_c_cell_release_grid_formula,
        companionTitle = R.string.health_atlas_thyroid_c_cell_release_grid_companion,
        entryIds = setOf("cell-thyroid-parafollicular-cell"),
        evaluate = { (moved, rows) -> (rows.roundToInt() * moved.roundToInt()).toDouble() },
        companionValue = { (moved, rows) -> (rows.roundToInt() * (ICONS_PER_ROW - moved.roundToInt())).toDouble() },
        digits = 0,
    )
}
