package com.galaxyssi.chat

internal object HealthAtlasRectalReservoirTeachingModel {
    private const val MAX_INITIAL_ML = 200
    private const val WHOLE_PERCENT = 100

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("rectal-reservoir-initial-volume", 20..MAX_INITIAL_ML, 120),
                R.string.health_atlas_rectal_reservoir_initial_volume,
                "mL",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("rectal-reservoir-release-share", 0..WHOLE_PERCENT, 40),
                R.string.health_atlas_rectal_reservoir_release_share,
                "%",
                digits = 0,
            ),
        ),
        axis = 1,
        unit = "mL",
        minimum = 0.0,
        maximum = MAX_INITIAL_ML.toDouble(),
        source = "https://www.niddk.nih.gov/health-information/digestive-diseases/digestive-system-how-it-works",
        extraSource = "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-5-the-small-and-large-intestines",
        title = R.string.health_atlas_rectal_reservoir_title,
        scope = R.string.health_atlas_rectal_reservoir_scope,
        formula = R.string.health_atlas_rectal_reservoir_formula,
        companionTitle = R.string.health_atlas_rectal_reservoir_companion,
        entryIds = setOf("rectum", "anal-canal"),
        evaluate = ::releasedMl,
        companionValue = { values -> values[0] - releasedMl(values) },
    )

    private fun releasedMl(values: List<Double>): Double {
        val (initialMl, releasePercent) = values
        return initialMl * (releasePercent / WHOLE_PERCENT)
    }
}
