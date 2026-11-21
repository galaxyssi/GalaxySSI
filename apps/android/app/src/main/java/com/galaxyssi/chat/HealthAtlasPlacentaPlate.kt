package com.galaxyssi.chat

internal object HealthAtlasPlacentaPlate {
    private fun anchor(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)

    val plate = HealthAtlasPlate(
        drawable = R.drawable.health_atlas_placenta_plate,
        owner = "placenta",
        viewLabel = R.string.health_atlas_placenta_plate_caption,
        markers = emptyList(),
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/28-2-embryonic-development",
        viewKey = "placenta-section",
        selectorLabel = R.string.health_atlas_placenta_plate_title,
        features = listOf(
            HealthAtlasFeature(anchor("placenta-umbilical-cord", 205, 34),
                R.string.health_atlas_placenta_plate_cord,
                R.string.health_atlas_placenta_plate_cord_detail),
            HealthAtlasFeature(anchor("placenta-chorionic-plate", 278, 104),
                R.string.health_atlas_placenta_plate_chorionic_plate,
                R.string.health_atlas_placenta_plate_chorionic_plate_detail),
            HealthAtlasFeature(anchor("placenta-terminal-villus", 214, 168),
                R.string.health_atlas_placenta_plate_terminal_villus,
                R.string.health_atlas_placenta_plate_terminal_villus_detail),
            HealthAtlasFeature(anchor("placenta-intervillous-space", 255, 190),
                R.string.health_atlas_placenta_plate_intervillous,
                R.string.health_atlas_placenta_plate_intervillous_detail),
            HealthAtlasFeature(anchor("placenta-spiral-artery", 112, 230),
                R.string.health_atlas_placenta_plate_spiral_artery,
                R.string.health_atlas_placenta_plate_spiral_artery_detail),
        ),
        splitCallouts = true,
    )
}
