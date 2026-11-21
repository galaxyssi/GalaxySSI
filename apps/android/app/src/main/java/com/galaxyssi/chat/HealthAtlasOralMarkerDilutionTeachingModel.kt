package com.galaxyssi.chat

internal object HealthAtlasOralMarkerDilutionTeachingModel {
    private const val MARKER_AMOUNT = 8.0
    private const val MIN_MARKER_STREAM_VOLUME = 2
    private const val VOLUME_UNIT = "VU"

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("oral-marker-dilution-marker-stream", MIN_MARKER_STREAM_VOLUME..8, 4),
                R.string.health_atlas_oral_marker_dilution_marker_stream,
                VOLUME_UNIT,
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("oral-marker-dilution-added-water", 0..12, 4),
                R.string.health_atlas_oral_marker_dilution_added_water,
                VOLUME_UNIT,
                digits = 0,
            ),
        ),
        axis = 1,
        unit = "TU/$VOLUME_UNIT",
        minimum = 0.0,
        maximum = MARKER_AMOUNT / MIN_MARKER_STREAM_VOLUME,
        source = "https://openstax.org/books/biology-2e/pages/36-3-taste-and-smell",
        title = R.string.health_atlas_oral_marker_dilution_title,
        scope = R.string.health_atlas_oral_marker_dilution_scope,
        formula = R.string.health_atlas_oral_marker_dilution_formula,
        companionTitle = R.string.health_atlas_oral_marker_dilution_companion,
        entryIds = setOf("oral-cavity", "tongue", "taste-buds", "cell-taste-receptor-cell"),
        evaluate = { volumes -> MARKER_AMOUNT / volumes.sum() },
        companionValue = { volumes -> volumes.sum() },
        extraSource = "https://www.nidcd.nih.gov/health/taste-disorders",
    )
}
