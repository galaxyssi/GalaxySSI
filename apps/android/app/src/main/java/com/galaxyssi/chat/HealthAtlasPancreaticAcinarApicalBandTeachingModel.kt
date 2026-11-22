package com.galaxyssi.chat

internal object HealthAtlasPancreaticAcinarApicalBandTeachingModel {
    private const val APICAL_WIDTH = 2.0
    private const val BASAL_WIDTH = 6.0
    private const val HEIGHT = 6.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("pancreatic-acinar-apical-band-depth", 0..30, 20, scale = 10.0),
                R.string.health_atlas_pancreatic_acinar_apical_band_depth, "u", digits = 1,
            ),
        ),
        axis = 0,
        unit = "%",
        minimum = 0.0,
        maximum = 40.0,
        source = "https://pancreapedia.org/reviews/anatomy-and-histology-of-pancreas",
        title = R.string.health_atlas_pancreatic_acinar_apical_band_title,
        scope = R.string.health_atlas_pancreatic_acinar_apical_band_scope,
        formula = R.string.health_atlas_pancreatic_acinar_apical_band_formula,
        companionTitle = R.string.health_atlas_pancreatic_acinar_apical_band_companion,
        entryIds = setOf("cell-pancreatic-acinar-cell"),
        evaluate = { (depth) -> 100.0 * bandArea(depth) / bandArea(HEIGHT) },
        companionValue = { (depth) -> bandArea(depth) },
    )

    private fun bandArea(depth: Double): Double {
        val bandEndWidth = APICAL_WIDTH + (BASAL_WIDTH - APICAL_WIDTH) * depth / HEIGHT
        return depth * (APICAL_WIDTH + bandEndWidth) / 2.0
    }
}
