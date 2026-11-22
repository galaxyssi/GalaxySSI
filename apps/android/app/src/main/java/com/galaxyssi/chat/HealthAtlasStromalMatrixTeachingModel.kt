package com.galaxyssi.chat

internal object HealthAtlasStromalMatrixTeachingModel {
    private const val PATCH_AREA = 2.0
    private const val MAX_ADDED_MASS = 20
    private const val MAX_INITIAL_MASS = 40
    private const val MASS_UNIT = "MU"

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("stromal-matrix-added-mass", 0..MAX_ADDED_MASS, 6),
                R.string.health_atlas_stromal_matrix_added_mass,
                MASS_UNIT,
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("stromal-matrix-initial-mass", 0..MAX_INITIAL_MASS, 12),
                R.string.health_atlas_stromal_matrix_initial_mass,
                MASS_UNIT,
                digits = 0,
            ),
        ),
        axis = 0,
        unit = "MU/AU",
        minimum = 0.0,
        maximum = (MAX_INITIAL_MASS + MAX_ADDED_MASS) / PATCH_AREA,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/4-3-connective-tissue-supports-and-protects",
        extraSource = "https://pmc.ncbi.nlm.nih.gov/articles/PMC8224746/",
        title = R.string.health_atlas_stromal_matrix_title,
        scope = R.string.health_atlas_stromal_matrix_scope,
        formula = R.string.health_atlas_stromal_matrix_formula,
        companionTitle = R.string.health_atlas_stromal_matrix_companion,
        entryIds = setOf("cell-fibroblast", "cell-endometrial-stromal-cell", "endometrium"),
        evaluate = { (addedMass, initialMass) -> (initialMass + addedMass) / PATCH_AREA },
        companionValue = { (_, initialMass) -> initialMass / PATCH_AREA },
    )
}
