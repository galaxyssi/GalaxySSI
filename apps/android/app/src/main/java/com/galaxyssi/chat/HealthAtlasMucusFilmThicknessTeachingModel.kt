package com.galaxyssi.chat

internal object HealthAtlasMucusFilmThicknessTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("mucus-film-volume", 4..24, 12),
                label = R.string.health_atlas_mucus_film_thickness_volume,
                unit = "u\u00b3",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("mucus-film-area", 2..12, 6),
                label = R.string.health_atlas_mucus_film_thickness_area,
                unit = "u\u00b2",
                digits = 0,
            ),
        ),
        axis = 1,
        unit = "u",
        minimum = 0.0,
        maximum = 12.0,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/22-1-organs-and-structures-of-the-respiratory-system",
        extraSource = "https://histology.leeds.ac.uk/home/digestive/small_intestine/",
        title = R.string.health_atlas_mucus_film_thickness_title,
        scope = R.string.health_atlas_mucus_film_thickness_scope,
        formula = R.string.health_atlas_mucus_film_thickness_formula,
        companionTitle = R.string.health_atlas_mucus_film_thickness_companion,
        entryIds = setOf("cell-goblet-cell", "pharynx", "tissue-intestinal-epithelium"),
        evaluate = { (volume, area) -> volume / area },
        companionValue = { (volume) -> volume },
    )
}
