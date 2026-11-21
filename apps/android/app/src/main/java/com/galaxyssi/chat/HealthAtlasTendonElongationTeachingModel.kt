package com.galaxyssi.chat

internal object HealthAtlasTendonElongationTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("tendon-elongation-force", 0..12, 6),
                R.string.health_atlas_tendon_elongation_force, "N", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("tendon-elongation-length", 20..80, 50),
                R.string.health_atlas_tendon_elongation_length, "mm", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("tendon-elongation-area", 30..60, 40, scale = 10.0),
                R.string.health_atlas_tendon_elongation_area, "mm\u00b2", digits = 1,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("tendon-elongation-modulus", 50..100, 75, scale = 0.1),
                R.string.health_atlas_tendon_elongation_modulus, "N/mm\u00b2", digits = 0,
            ),
        ),
        axis = 0,
        unit = "mm",
        minimum = 0.0,
        maximum = 0.65,
        source = "https://mechref.engr.illinois.edu/sol/axial.html",
        title = R.string.health_atlas_tendon_elongation_title,
        scope = R.string.health_atlas_tendon_elongation_scope,
        formula = R.string.health_atlas_tendon_elongation_formula,
        companionTitle = R.string.health_atlas_tendon_elongation_strain,
        entryIds = setOf("tendons", "ligaments", "tissue-dense-regular-connective", "cell-tenocyte"),
        evaluate = { (force, length, area, modulus) -> length * axialStrain(force, area, modulus) },
        companionValue = { (force, _, area, modulus) -> 100.0 * axialStrain(force, area, modulus) },
        extraSource = "https://pubmed.ncbi.nlm.nih.gov/11985759/",
        digits = 3,
    )

    private fun axialStrain(force: Double, area: Double, modulus: Double) = force / (modulus * area)
}
