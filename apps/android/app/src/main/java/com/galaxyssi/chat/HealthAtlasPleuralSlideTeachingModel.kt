package com.galaxyssi.chat

internal object HealthAtlasPleuralSlideTeachingModel {
    const val MAX_SLIDING_SPEED = 24
    private const val MODEL_VISCOSITY = .01

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(HealthAtlasInput("pleural-slide-speed", 0..MAX_SLIDING_SPEED, 8),
                R.string.health_atlas_pleural_slide_speed, "mm/s", digits = 0),
            HealthAtlasTeachingInput(HealthAtlasInput("pleural-slide-thickness", 2..16, 8, 10.0),
                R.string.health_atlas_pleural_slide_thickness, "mm", digits = 1),
        ),
        axis = 0,
        unit = "s\u207b\u00b9",
        minimum = 0.0,
        maximum = 120.0,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/22-2-the-lungs",
        extraSource = "https://openstax.org/books/university-physics-volume-1/pages/14-7-viscosity-and-turbulence",
        title = R.string.health_atlas_pleural_slide_title,
        scope = R.string.health_atlas_pleural_slide_scope,
        formula = R.string.health_atlas_pleural_slide_formula,
        companionTitle = R.string.health_atlas_pleural_slide_stress,
        entryIds = setOf("pleura"),
        evaluate = { (speed, thickness) -> speed / thickness },
        companionValue = { (speed, thickness) -> MODEL_VISCOSITY * (speed / thickness) },
    )

    /** In an ideal parallel film the velocity varies linearly from the reference surface. */
    fun relativeVelocity(surfaceSpeed: Double, fractionFromReference: Float) =
        surfaceSpeed * fractionFromReference
}
