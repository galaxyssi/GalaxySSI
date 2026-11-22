package com.galaxyssi.chat

import kotlin.math.ln1p

internal object HealthAtlasGlialCapacitanceTeachingModel {
    private const val RELATIVE_UNIT = "\u00d7"
    private const val BASELINE_THICKNESS_OVER_RADIUS = 0.5
    private val baselineLogRadiusRatio = ln1p(BASELINE_THICKNESS_OVER_RADIUS)

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("glial-capacitance-thickness", 10..40, 20, scale = 20.0),
                R.string.health_atlas_glial_capacitance_thickness,
                RELATIVE_UNIT,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("glial-capacitance-area", 10..40, 20, scale = 20.0),
                R.string.health_atlas_glial_capacitance_area,
                RELATIVE_UNIT,
            ),
        ),
        axis = 0,
        unit = RELATIVE_UNIT,
        minimum = 0.0,
        maximum = 4.0,
        source = "https://openstax.org/books/university-physics-volume-2/pages/8-1-capacitors-and-capacitance",
        title = R.string.health_atlas_glial_capacitance_title,
        scope = R.string.health_atlas_glial_capacitance_scope,
        formula = R.string.health_atlas_glial_capacitance_formula,
        companionTitle = R.string.health_atlas_glial_capacitance_per_area,
        entryIds = setOf("cell-schwann-cell", "cell-oligodendrocyte"),
        evaluate = { (thickness, area) -> area * relativeCapacitancePerArea(thickness) },
        companionValue = { (thickness) -> relativeCapacitancePerArea(thickness) },
        extraSource = "https://openstax.org/books/anatomy-and-physiology-2e/pages/12-2-nervous-tissue",
    )

    // At fixed inner radius, inner area scales with cylinder length; the dielectric is unchanged.
    private fun relativeCapacitancePerArea(thickness: Double): Double =
        baselineLogRadiusRatio / ln1p(thickness * BASELINE_THICKNESS_OVER_RADIUS)
}
