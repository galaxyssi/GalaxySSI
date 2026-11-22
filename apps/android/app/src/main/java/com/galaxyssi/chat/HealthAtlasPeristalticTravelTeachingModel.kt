package com.galaxyssi.chat

internal object HealthAtlasPeristalticTravelTeachingModel {
    private const val DEMO_SEGMENT_CM = 10.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("peristaltic-travel-speed", 10..40, 25, scale = 10.0),
                label = R.string.health_atlas_peristaltic_travel_speed,
                unit = "cm/s",
                digits = 1,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("peristaltic-travel-time", 0..25, 20, scale = 10.0),
                label = R.string.health_atlas_peristaltic_travel_time,
                unit = "s",
                digits = 1,
            ),
        ),
        axis = 1,
        unit = "cm",
        minimum = 0.0,
        maximum = DEMO_SEGMENT_CM,
        source = "https://www.niddk.nih.gov/health-information/digestive-diseases/digestive-system-how-it-works",
        title = R.string.health_atlas_peristaltic_travel_title,
        scope = R.string.health_atlas_peristaltic_travel_scope,
        formula = R.string.health_atlas_peristaltic_travel_formula,
        companionTitle = R.string.health_atlas_peristaltic_travel_progress,
        entryIds = setOf("esophagus", "tissue-smooth-muscle", "cell-smooth-muscle-cell"),
        evaluate = ::waveFrontDistanceCm,
        companionValue = { 100.0 * waveFrontDistanceCm(it) / DEMO_SEGMENT_CM },
    )

    private fun waveFrontDistanceCm(values: List<Double>) = values[0] * values[1]
}
