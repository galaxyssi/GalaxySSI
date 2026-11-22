package com.galaxyssi.chat

internal object HealthAtlasSkinWaterBarrierTeachingModel {
    private const val RELATIVE_UNIT = "\u00d7"

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("skin-water-diffusivity", 10..30, 20, scale = 20.0),
                R.string.health_atlas_skin_water_barrier_diffusivity,
                RELATIVE_UNIT,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("skin-water-gradient", 0..30, 20, scale = 20.0),
                R.string.health_atlas_skin_water_barrier_gradient,
                RELATIVE_UNIT,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("skin-water-thickness", 10..30, 20, scale = 20.0),
                R.string.health_atlas_skin_water_barrier_thickness,
                RELATIVE_UNIT,
            ),
        ),
        axis = 1,
        unit = RELATIVE_UNIT,
        minimum = 0.0,
        maximum = 4.5,
        source = "https://pubmed.ncbi.nlm.nih.gov/9740228/",
        title = R.string.health_atlas_skin_water_barrier_title,
        scope = R.string.health_atlas_skin_water_barrier_scope,
        formula = R.string.health_atlas_skin_water_barrier_formula,
        companionTitle = R.string.health_atlas_skin_water_barrier_conductance,
        entryIds = setOf("skin", "skin-organ", "epidermis", "tissue-epidermal", "cell-keratinocyte"),
        evaluate = { (diffusivity, gradient, thickness) -> diffusivity * gradient / thickness },
        companionValue = { (diffusivity, _, thickness) -> diffusivity / thickness },
        extraSource = "https://openstax.org/books/anatomy-and-physiology-2e/pages/5-1-layers-of-the-skin",
    )
}
