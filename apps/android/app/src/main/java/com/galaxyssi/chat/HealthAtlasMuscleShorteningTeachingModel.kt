package com.galaxyssi.chat

internal object HealthAtlasMuscleShorteningTeachingModel {
    private const val INITIAL_SARCOMERE_LENGTH_UM = 2.5
    private const val MICROMETERS_PER_MILLIMETER = 1000.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("muscle-shortening-count", 200..2000, 1000),
                R.string.health_atlas_muscle_shortening_count, "", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("muscle-shortening-per-sarcomere", 0..50, 25, scale = 100.0),
                R.string.health_atlas_muscle_shortening_per_sarcomere, "\u00b5m",
            ),
        ),
        axis = 1,
        unit = "mm",
        minimum = 0.0,
        maximum = 1.0,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/10-3-muscle-fiber-contraction-and-relaxation",
        title = R.string.health_atlas_muscle_shortening_title,
        scope = R.string.health_atlas_muscle_shortening_scope,
        formula = R.string.health_atlas_muscle_shortening_formula,
        companionTitle = R.string.health_atlas_muscle_shortening_remaining_length,
        entryIds = setOf(
            "cell-skeletal-myocyte", "tissue-skeletal-muscle", "pectoralis-major", "deltoid",
            "triceps-brachii", "rectus-abdominis", "oblique-abdominal-muscles", "trapezius",
            "latissimus-dorsi", "erector-spinae", "gluteus-maximus", "hamstrings",
        ),
        evaluate = { (count, shorteningUm) -> seriesLengthMm(count, shorteningUm) },
        companionValue = { (count, shorteningUm) ->
            seriesLengthMm(count, INITIAL_SARCOMERE_LENGTH_UM - shorteningUm)
        },
        digits = 3,
    )

    private fun seriesLengthMm(count: Double, perSarcomereUm: Double) =
        count * perSarcomereUm / MICROMETERS_PER_MILLIMETER
}
