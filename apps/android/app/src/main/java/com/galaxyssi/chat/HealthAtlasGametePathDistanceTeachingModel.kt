package com.galaxyssi.chat

internal object HealthAtlasGametePathDistanceTeachingModel {
    private const val SPERM_START = 0.0
    private const val OOCYTE_START = 16.0
    private const val SPERM_MAX_SHIFT = 8
    private const val OOCYTE_MAX_SHIFT = 6
    private const val POSITION_UNIT = "PU"

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("gamete-path-distance-sperm-shift", 0..SPERM_MAX_SHIFT, 4),
                label = R.string.health_atlas_gamete_path_distance_sperm_shift,
                unit = POSITION_UNIT,
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("gamete-path-distance-oocyte-shift", 0..OOCYTE_MAX_SHIFT, 2),
                label = R.string.health_atlas_gamete_path_distance_oocyte_shift,
                unit = POSITION_UNIT,
                digits = 0,
            ),
        ),
        axis = 0,
        unit = POSITION_UNIT,
        minimum = (OOCYTE_START - OOCYTE_MAX_SHIFT) - (SPERM_START + SPERM_MAX_SHIFT),
        maximum = OOCYTE_START - SPERM_START,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-2-anatomy-and-physiology-of-the-ovarian-reproductive-system",
        title = R.string.health_atlas_gamete_path_distance_title,
        scope = R.string.health_atlas_gamete_path_distance_scope,
        formula = R.string.health_atlas_gamete_path_distance_formula,
        companionTitle = R.string.health_atlas_gamete_path_distance_companion,
        entryIds = setOf("cell-spermatozoon", "cell-oocyte-or-ovum"),
        evaluate = { (spermShift, oocyteShift) ->
            val spermPosition = SPERM_START + spermShift
            val oocytePosition = OOCYTE_START - oocyteShift
            oocytePosition - spermPosition
        },
        companionValue = { OOCYTE_START - SPERM_START },
        extraSource = "https://openstax.org/books/university-physics-volume-1/pages/3-1-position-displacement-and-average-velocity",
        digits = 0,
    )
}
