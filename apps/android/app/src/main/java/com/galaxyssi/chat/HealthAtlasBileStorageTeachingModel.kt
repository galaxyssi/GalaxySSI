package com.galaxyssi.chat

internal object HealthAtlasBileStorageTeachingModel {
    private const val STARTING_VOLUME = 12.0
    private const val MAX_WATER_REMOVED = 8
    private const val MAX_MARKER_AMOUNT = 12
    private const val MARKER_UNIT = "TU"
    private const val VOLUME_UNIT = "VU"

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("bile-storage-marker-amount", 1..MAX_MARKER_AMOUNT, 6),
                R.string.health_atlas_bile_storage_marker_amount,
                MARKER_UNIT,
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("bile-storage-water-removed", 0..MAX_WATER_REMOVED, 6),
                R.string.health_atlas_bile_storage_water_removed,
                VOLUME_UNIT,
                digits = 0,
            ),
        ),
        axis = 1,
        unit = "$MARKER_UNIT/$VOLUME_UNIT",
        minimum = 0.0,
        maximum = MAX_MARKER_AMOUNT / (STARTING_VOLUME - MAX_WATER_REMOVED),
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-6-accessory-organs-in-digestion-the-liver-pancreas-and-gallbladder",
        title = R.string.health_atlas_bile_storage_title,
        scope = R.string.health_atlas_bile_storage_scope,
        formula = R.string.health_atlas_bile_storage_formula,
        companionTitle = R.string.health_atlas_bile_storage_companion,
        entryIds = setOf("gallbladder"),
        evaluate = { (markerAmount, waterRemoved) -> markerAmount / (STARTING_VOLUME - waterRemoved) },
        companionValue = { (markerAmount) -> markerAmount },
        extraSource = "https://www.niddk.nih.gov/health-information/digestive-diseases/digestive-system-how-it-works",
    )
}
