package com.galaxyssi.chat

internal object HealthAtlasAstrocyteRecyclingTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("astrocyte-recycling-uptake", 0..100, 60),
                R.string.health_atlas_astrocyte_recycling_uptake, "%", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("astrocyte-recycling-return", 0..100, 50),
                R.string.health_atlas_astrocyte_recycling_return, "%", digits = 0,
            ),
        ),
        axis = 0,
        unit = "%",
        minimum = 0.0,
        maximum = 100.0,
        source = "https://pmc.ncbi.nlm.nih.gov/articles/PMC2995528/",
        title = R.string.health_atlas_astrocyte_recycling_title,
        scope = R.string.health_atlas_astrocyte_recycling_scope,
        formula = R.string.health_atlas_astrocyte_recycling_formula,
        companionTitle = R.string.health_atlas_astrocyte_recycling_companion,
        entryIds = setOf("cell-astrocyte"),
        evaluate = { (uptake, returned) -> uptake * returned / 100.0 },
        companionValue = { (uptake, _) -> 100.0 - uptake },
    )
}
