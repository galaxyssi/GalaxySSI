package com.galaxyssi.chat

internal object HealthAtlasDuctTransitTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("duct-transit-length", 4..24, 12),
                label = R.string.health_atlas_duct_transit_length,
                unit = "LU",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("duct-transit-speed", 10..50, 25, scale = 10.0),
                label = R.string.health_atlas_duct_transit_speed,
                unit = "LU/TU",
                digits = 1,
            ),
        ),
        axis = 0,
        unit = "TU",
        minimum = 0.0,
        maximum = 25.0,
        source = "https://www.ncbi.nlm.nih.gov/books/NBK538429/",
        title = R.string.health_atlas_duct_transit_title,
        scope = R.string.health_atlas_duct_transit_scope,
        formula = R.string.health_atlas_duct_transit_formula,
        companionTitle = R.string.health_atlas_duct_transit_companion,
        entryIds = setOf("male", "epididymis", "vas-deferens", "ejaculatory-ducts"),
        evaluate = { (length, speed) -> length / speed },
        companionValue = { (_, speed) -> 1.0 / speed },
        extraSource = "https://pubmed.ncbi.nlm.nih.gov/31033221/",
    )
}
