package com.galaxyssi.chat

internal object HealthAtlasCutaneousSebumTeachingModel {
    private const val MASS_UNIT = "\u00b5g"
    private const val AREA_UNIT = "cm\u00b2"

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("cutaneous-sebum-mass", 20..80, 40),
                R.string.health_atlas_cutaneous_sebum_mass,
                MASS_UNIT,
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("cutaneous-sebum-area", 4..16, 8),
                R.string.health_atlas_cutaneous_sebum_area,
                AREA_UNIT,
                digits = 0,
            ),
        ),
        axis = 1,
        unit = "$MASS_UNIT/$AREA_UNIT",
        minimum = 0.0,
        maximum = 20.0,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/5-2-accessory-structures-of-the-skin",
        title = R.string.health_atlas_cutaneous_sebum_title,
        scope = R.string.health_atlas_cutaneous_sebum_scope,
        formula = R.string.health_atlas_cutaneous_sebum_formula,
        companionTitle = R.string.health_atlas_cutaneous_sebum_companion,
        entryIds = setOf("sebaceous-glands", "cell-sebocyte"),
        evaluate = { (mass, area) -> mass / area },
        companionValue = { (mass) -> mass },
        extraSource = "https://histologyguide.com/EM-view/EM-373-sebaceous-gland/12-photo-1.html",
    )
}
