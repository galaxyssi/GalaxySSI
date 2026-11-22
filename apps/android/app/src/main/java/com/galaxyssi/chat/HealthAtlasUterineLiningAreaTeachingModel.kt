package com.galaxyssi.chat

import kotlin.math.PI

internal object HealthAtlasUterineLiningAreaTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("uterine-lining-radius", 10..40, 20, scale = 10.0),
                label = R.string.health_atlas_uterine_lining_area_radius,
                unit = "LU",
                digits = 1,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("uterine-lining-length", 20..80, 40, scale = 10.0),
                label = R.string.health_atlas_uterine_lining_area_length,
                unit = "LU",
                digits = 1,
            ),
        ),
        axis = 0,
        unit = "LU\u00b2",
        minimum = 0.0,
        maximum = 210.0,
        source = "https://histology.oit.duke.edu/NormalBody/FemaleRepro/FemaleRepro.html",
        extraSource = "https://openstax.org/books/prealgebra/pages/9-6-solve-geometry-applications-volume-and-surface-area",
        title = R.string.health_atlas_uterine_lining_area_title,
        scope = R.string.health_atlas_uterine_lining_area_scope,
        formula = R.string.health_atlas_uterine_lining_area_formula,
        companionTitle = R.string.health_atlas_uterine_lining_area_companion,
        entryIds = setOf("uterus", "cervix", "cell-endometrial-epithelial-cell"),
        evaluate = { (radius, length) -> circumference(radius) * length },
        companionValue = { (radius) -> circumference(radius) },
    )

    private fun circumference(radius: Double) = 2.0 * PI * radius
}
