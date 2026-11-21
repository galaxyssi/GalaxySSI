package com.galaxyssi.chat

internal object HealthAtlasKeratinGrowthTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("keratin-growth-time", 0..20, 8),
                label = R.string.health_atlas_keratin_growth_time,
                unit = "d",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("keratin-growth-rate", 2..8, 5, scale = 10.0),
                label = R.string.health_atlas_keratin_growth_rate,
                unit = "mm/d",
                digits = 1,
            ),
        ),
        axis = 0,
        unit = "mm",
        minimum = 0.0,
        maximum = 16.0,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/5-2-accessory-structures-of-the-skin",
        title = R.string.health_atlas_keratin_growth_title,
        scope = R.string.health_atlas_keratin_growth_scope,
        formula = R.string.health_atlas_keratin_growth_formula,
        companionTitle = R.string.health_atlas_keratin_growth_companion,
        entryIds = setOf("hair", "hair-follicles", "cell-hair-matrix-cell"),
        evaluate = { (days, rateMmPerDay) -> days * rateMmPerDay },
        companionValue = { (_, rateMmPerDay) -> 1.0 / rateMmPerDay },
    )
}
