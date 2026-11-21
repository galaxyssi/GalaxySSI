package com.galaxyssi.chat

import kotlin.math.roundToInt

internal object HealthAtlasDendriticCellOutlineTeachingModel {
    private const val BODY_WIDTH = 3
    private const val SIDES = 4
    private const val BODY_EDGE_MARKS = BODY_WIDTH * SIDES
    private const val EDGE_MARKS_PER_TAB = 2

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("dendritic-cell-outline-tabs", 0..SIDES, 3),
                R.string.health_atlas_dendritic_cell_outline_tabs, unit = "", digits = 0,
            ),
        ),
        axis = 0,
        unit = "",
        minimum = BODY_EDGE_MARKS.toDouble(),
        maximum = (BODY_EDGE_MARKS + EDGE_MARKS_PER_TAB * SIDES).toDouble(),
        source = "https://rupress.org/jem/article-pdf/163/2/436/1666573/436.pdf",
        extraSource = "https://openstax.org/books/anatomy-and-physiology-2e/pages/21-3-the-adaptive-immune-response-t-lymphocytes-and-their-functional-types",
        title = R.string.health_atlas_dendritic_cell_outline_title,
        scope = R.string.health_atlas_dendritic_cell_outline_scope,
        formula = R.string.health_atlas_dendritic_cell_outline_formula,
        companionTitle = R.string.health_atlas_dendritic_cell_outline_companion,
        entryIds = setOf("cell-dendritic-cell"),
        evaluate = { (tabs) -> (BODY_EDGE_MARKS + EDGE_MARKS_PER_TAB * tabs.roundToInt()).toDouble() },
        companionValue = { (tabs) -> (BODY_WIDTH * BODY_WIDTH + tabs.roundToInt()).toDouble() },
        digits = 0,
    )
}
