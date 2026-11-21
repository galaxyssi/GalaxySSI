package com.galaxyssi.chat

import kotlin.math.PI
import kotlin.math.roundToInt

internal object HealthAtlasThyroidFollicularFacesTeachingModel {
    private const val MIN_WEDGES = 8
    private const val MAX_WEDGES = 16
    private const val MAX_RADIUS_STEP = 60
    private const val RADIUS_SCALE = 10.0
    private const val WALL_THICKNESS = 2.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("thyroid-follicular-faces-wedges", MIN_WEDGES..MAX_WEDGES, 12),
                R.string.health_atlas_thyroid_follicular_faces_wedges, unit = "", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("thyroid-follicular-faces-radius", 20..MAX_RADIUS_STEP, 40, RADIUS_SCALE),
                R.string.health_atlas_thyroid_follicular_faces_radius, unit = "u", digits = 1,
            ),
        ),
        axis = 0,
        unit = "u",
        minimum = 0.0,
        maximum = arcLength(MAX_RADIUS_STEP / RADIUS_SCALE, MIN_WEDGES),
        source = "https://histology.oit.duke.edu/NormalBody/Endocrine/Endocrine.html",
        title = R.string.health_atlas_thyroid_follicular_faces_title,
        scope = R.string.health_atlas_thyroid_follicular_faces_scope,
        formula = R.string.health_atlas_thyroid_follicular_faces_formula,
        companionTitle = R.string.health_atlas_thyroid_follicular_faces_companion,
        entryIds = setOf("cell-thyroid-follicular-cell"),
        evaluate = { (wedges, radius) -> arcLength(radius, wedges.roundToInt()) },
        companionValue = { (wedges, radius) -> arcLength(radius + WALL_THICKNESS, wedges.roundToInt()) },
    )

    private fun arcLength(radius: Double, wedges: Int): Double = 2.0 * PI * radius / wedges
}
