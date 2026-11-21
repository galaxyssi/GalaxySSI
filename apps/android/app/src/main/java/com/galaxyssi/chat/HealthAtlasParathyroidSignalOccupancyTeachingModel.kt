package com.galaxyssi.chat

internal object HealthAtlasParathyroidSignalOccupancyTeachingModel {
    private const val FULL_PERCENT = 100.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("parathyroid-occupancy-signal", 0..120, 20, scale = 10.0),
                label = R.string.health_atlas_parathyroid_occupancy_signal,
                unit = "",
                digits = 1,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("parathyroid-occupancy-half-point", 5..60, 20, scale = 10.0),
                label = R.string.health_atlas_parathyroid_occupancy_half_point,
                unit = "",
                digits = 1,
            ),
        ),
        axis = 0,
        unit = "%",
        minimum = 0.0,
        maximum = FULL_PERCENT,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-5-the-parathyroid-glands",
        title = R.string.health_atlas_parathyroid_occupancy_title,
        scope = R.string.health_atlas_parathyroid_occupancy_scope,
        formula = R.string.health_atlas_parathyroid_occupancy_formula,
        companionTitle = R.string.health_atlas_parathyroid_occupancy_unoccupied,
        entryIds = setOf("parathyroid-glands", "cell-parathyroid-chief-cell"),
        evaluate = ::occupiedPercent,
        companionValue = { FULL_PERCENT - occupiedPercent(it) },
        extraSource = "https://pmc.ncbi.nlm.nih.gov/articles/PMC6580154/",
    )

    private fun occupiedPercent(values: List<Double>): Double {
        val (signal, halfPoint) = values
        return FULL_PERCENT * (signal / (signal + halfPoint))
    }
}
