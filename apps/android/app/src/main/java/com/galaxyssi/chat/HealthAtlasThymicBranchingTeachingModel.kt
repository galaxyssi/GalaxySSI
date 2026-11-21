package com.galaxyssi.chat

internal object HealthAtlasThymicBranchingTeachingModel {
    private const val TILE_UNIT = "tiles"
    private const val TALLY_SCALE = 0.05
    private const val MAX_TALLY_STEP = 10

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("thymic-branching-starting-tally", 1..MAX_TALLY_STEP, 4, TALLY_SCALE),
                R.string.health_atlas_thymic_branching_starting_tally,
                TILE_UNIT,
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("thymic-branching-selected-percent", 0..20, 7, 0.2),
                R.string.health_atlas_thymic_branching_selected_percent,
                "%",
                digits = 0,
            ),
        ),
        axis = 1,
        unit = TILE_UNIT,
        minimum = 0.0,
        maximum = MAX_TALLY_STEP / TALLY_SCALE,
        source = "https://www.ncbi.nlm.nih.gov/sites/books/NBK27089/",
        title = R.string.health_atlas_thymic_branching_title,
        scope = R.string.health_atlas_thymic_branching_scope,
        formula = R.string.health_atlas_thymic_branching_formula,
        companionTitle = R.string.health_atlas_thymic_branching_companion,
        entryIds = setOf("thymus", "cell-helper-t-cell", "cell-cytotoxic-t-cell", "cell-regulatory-t-cell"),
        evaluate = { (tally, percent) -> selectedTiles(tally, percent) },
        companionValue = { (tally, percent) -> tally - selectedTiles(tally, percent) },
        extraSource = "https://pmc.ncbi.nlm.nih.gov/articles/PMC3620359/",
        digits = 0,
    )

    private fun selectedTiles(tally: Double, percent: Double): Double = tally * percent / 100.0
}
