package com.galaxyssi.chat

import kotlin.math.cos

internal object HealthAtlasVulvarFoldOverlapTeachingModel {
    private const val INNER_FLAP_START = 0.25
    private const val INNER_FLAP_LENGTH = 0.50

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("vulvar-fold-overlap-angle", 0..90, 60),
                label = R.string.health_atlas_vulvar_fold_overlap_angle,
                unit = "\u00b0",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("vulvar-fold-overlap-length", 25..100, 75, scale = 100.0),
                label = R.string.health_atlas_vulvar_fold_overlap_length,
                unit = "",
            ),
        ),
        axis = 0,
        unit = "%",
        minimum = 0.0,
        maximum = 100.0,
        source = "https://openstax.org/books/biology/pages/43-3-human-reproductive-anatomy-and-gametogenesis",
        extraSource = "https://openstax.org/books/university-physics-volume-1/pages/2-2-coordinate-systems-and-components-of-a-vector",
        title = R.string.health_atlas_vulvar_fold_overlap_title,
        scope = R.string.health_atlas_vulvar_fold_overlap_scope,
        formula = R.string.health_atlas_vulvar_fold_overlap_formula,
        companionTitle = R.string.health_atlas_vulvar_fold_overlap_companion,
        entryIds = setOf("vulva", "labia-majora", "labia-minora"),
        evaluate = { (angle, length) ->
            val overlapFraction = (projectedReach(angle, length) - INNER_FLAP_START) / INNER_FLAP_LENGTH
            100.0 * overlapFraction.coerceIn(0.0, 1.0)
        },
        companionValue = { (angle, length) -> 100.0 * projectedReach(angle, length) },
    )

    private fun projectedReach(angle: Double, length: Double): Double =
        length * cos(Math.toRadians(angle))
}
