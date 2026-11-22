package com.galaxyssi.chat

import kotlin.math.PI

internal object HealthAtlasClubCellDomeTeachingModel {
    private const val WIDTH = 4.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("club-cell-dome-rise", 5..30, 15, scale = 10.0),
                R.string.health_atlas_club_cell_dome_rise, "u", digits = 1,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("club-cell-dome-body-height", 30..60, 40, scale = 10.0),
                R.string.health_atlas_club_cell_dome_body_height, "u", digits = 1,
            ),
        ),
        axis = 0,
        unit = "%",
        minimum = 0.0,
        maximum = 50.0,
        source = "https://pmc.ncbi.nlm.nih.gov/articles/PMC6290945/",
        title = R.string.health_atlas_club_cell_dome_title,
        scope = R.string.health_atlas_club_cell_dome_scope,
        formula = R.string.health_atlas_club_cell_dome_formula,
        companionTitle = R.string.health_atlas_club_cell_dome_companion,
        entryIds = setOf("cell-club-cell"),
        evaluate = { (rise, bodyHeight) ->
            val cap = capArea(rise)
            100.0 * cap / (cap + WIDTH * bodyHeight)
        },
        companionValue = { (rise) -> capArea(rise) },
    )

    private fun capArea(rise: Double) = PI * (WIDTH / 2.0) * rise / 2.0
}
