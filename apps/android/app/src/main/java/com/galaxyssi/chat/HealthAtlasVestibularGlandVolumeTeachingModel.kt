package com.galaxyssi.chat

import kotlin.math.abs

internal object HealthAtlasVestibularGlandVolumeTeachingModel {
    private const val MAX_VOLUME_TENTHS = 60
    private const val VOLUME_SCALE = 10.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("vestibular-gland-volume-a", 0..MAX_VOLUME_TENTHS, 20, scale = VOLUME_SCALE),
                R.string.health_atlas_vestibular_gland_volume_a, "vu", digits = 1,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("vestibular-gland-volume-b", 0..MAX_VOLUME_TENTHS, 30, scale = VOLUME_SCALE),
                R.string.health_atlas_vestibular_gland_volume_b, "vu", digits = 1,
            ),
        ),
        axis = 0,
        unit = "vu",
        minimum = 0.0,
        maximum = 2 * MAX_VOLUME_TENTHS / VOLUME_SCALE,
        source = "https://pmc.ncbi.nlm.nih.gov/articles/PMC9544139/",
        extraSource = "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-2-anatomy-and-physiology-of-the-ovarian-reproductive-system",
        title = R.string.health_atlas_vestibular_gland_volume_title,
        scope = R.string.health_atlas_vestibular_gland_volume_scope,
        formula = R.string.health_atlas_vestibular_gland_volume_formula,
        companionTitle = R.string.health_atlas_vestibular_gland_volume_companion,
        entryIds = setOf("greater-vestibular-glands"),
        evaluate = { (a, b) -> a + b },
        companionValue = { (a, b) -> abs(a - b) },
        digits = 1,
    )
}
