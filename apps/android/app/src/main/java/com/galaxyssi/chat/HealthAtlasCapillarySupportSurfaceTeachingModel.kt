package com.galaxyssi.chat

import kotlin.math.PI

internal object HealthAtlasCapillarySupportSurfaceTeachingModel {
    private const val MAX_RADIUS = 8
    private const val MAX_LENGTH = 60
    private const val LENGTH_UNIT = "\u00b5m"

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("capillary-support-surface-radius", 2..MAX_RADIUS, 4),
                R.string.health_atlas_capillary_support_surface_radius,
                LENGTH_UNIT,
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("capillary-support-surface-length", 10..MAX_LENGTH, 30),
                R.string.health_atlas_capillary_support_surface_length,
                LENGTH_UNIT,
                digits = 0,
            ),
        ),
        axis = 0,
        unit = "${LENGTH_UNIT}\u00b2",
        minimum = 0.0,
        maximum = circumference(MAX_RADIUS.toDouble()) * MAX_LENGTH,
        source = "https://pubmed.ncbi.nlm.nih.gov/29298435/",
        extraSource = "https://pubmed.ncbi.nlm.nih.gov/12682087/",
        title = R.string.health_atlas_capillary_support_surface_title,
        scope = R.string.health_atlas_capillary_support_surface_scope,
        formula = R.string.health_atlas_capillary_support_surface_formula,
        companionTitle = R.string.health_atlas_capillary_support_surface_companion,
        entryIds = setOf("cell-pericyte", "cell-mesangial-cell"),
        evaluate = { (radius, length) -> circumference(radius) * length },
        companionValue = { (radius, _) -> circumference(radius) },
    )

    private fun circumference(radius: Double) = 2.0 * PI * radius
}
