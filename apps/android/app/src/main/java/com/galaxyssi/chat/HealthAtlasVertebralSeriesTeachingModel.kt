package com.galaxyssi.chat

internal object HealthAtlasVertebralSeriesTeachingModel {
    private const val INITIAL_PAD_THICKNESS_MM = 5.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("vertebral-series-pad-count", 1..8, 4),
                R.string.health_atlas_vertebral_series_pad_count, "", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("vertebral-series-shortening-per-pad", 0..100, 25, scale = 100.0),
                R.string.health_atlas_vertebral_series_shortening_per_pad, "mm",
            ),
        ),
        axis = 1,
        unit = "mm",
        minimum = 0.0,
        maximum = 8.0,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/7-3-the-vertebral-column",
        title = R.string.health_atlas_vertebral_series_title,
        scope = R.string.health_atlas_vertebral_series_scope,
        formula = R.string.health_atlas_vertebral_series_formula,
        companionTitle = R.string.health_atlas_vertebral_series_remaining_pad_thickness,
        entryIds = setOf("vertebrae"),
        evaluate = { (count, shorteningMm) -> count * shorteningMm },
        companionValue = { (count, shorteningMm) -> count * (INITIAL_PAD_THICKNESS_MM - shorteningMm) },
    )
}
