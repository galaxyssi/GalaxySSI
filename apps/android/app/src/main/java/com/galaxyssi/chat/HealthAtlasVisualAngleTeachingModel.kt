package com.galaxyssi.chat

import kotlin.math.atan

internal object HealthAtlasVisualAngleTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("visual-angle-width", 1..20, 10),
                label = R.string.health_atlas_model_visual_angle_width,
                unit = "cm",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("visual-angle-distance", 50..150, 100),
                label = R.string.health_atlas_model_visual_angle_distance,
                unit = "cm",
                digits = 0,
            ),
        ),
        axis = 1,
        unit = "\u00b0",
        minimum = 0.0,
        maximum = 25.0,
        source = "https://pmc.ncbi.nlm.nih.gov/articles/PMC3878374/",
        title = R.string.health_atlas_model_visual_angle_title,
        scope = R.string.health_atlas_model_visual_angle_scope,
        formula = R.string.health_atlas_model_visual_angle_formula,
        companionTitle = R.string.health_atlas_model_visual_angle_half,
        entryIds = setOf("sensory", "retina"),
        evaluate = { (width, distance) -> 2.0 * halfAngleDegrees(width, distance) },
        companionValue = { (width, distance) -> halfAngleDegrees(width, distance) },
        extraSource = "https://www.nei.nih.gov/eye-health-information/healthy-vision/how-eyes-work",
    )

    private fun halfAngleDegrees(widthCm: Double, distanceCm: Double): Double =
        Math.toDegrees(atan(widthCm / (2.0 * distanceCm)))
}
