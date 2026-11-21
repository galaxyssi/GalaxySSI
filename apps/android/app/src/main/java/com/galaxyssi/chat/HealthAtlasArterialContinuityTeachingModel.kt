package com.galaxyssi.chat

import kotlin.math.PI

internal object HealthAtlasArterialContinuityTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(HealthAtlasInput("arterial-lumen-diameter", 10..40, 24),
                R.string.health_atlas_arterial_continuity_diameter, "mm", digits = 0),
            HealthAtlasTeachingInput(HealthAtlasInput("arterial-volume-flow", 0..150, 70),
                R.string.health_atlas_arterial_continuity_flow, "mL/s", digits = 0),
        ),
        axis = 0,
        unit = "cm/s",
        minimum = 0.0,
        maximum = 200.0,
        source = "https://openstax.org/books/university-physics-volume-1/pages/14-5-fluid-dynamics",
        extraSource = "https://openstax.org/books/anatomy-and-physiology-2e/pages/20-5-circulatory-pathways",
        title = R.string.health_atlas_arterial_continuity_title,
        scope = R.string.health_atlas_arterial_continuity_scope,
        formula = R.string.health_atlas_arterial_continuity_formula,
        companionTitle = R.string.health_atlas_arterial_continuity_area,
        entryIds = setOf("aorta", "pulmonary-trunk"),
        evaluate = { (diameter, flow) -> flow / area(diameter) },
        companionValue = { (diameter, _) -> area(diameter) },
    )

    fun area(diameterMm: Double): Double {
        val radiusCm = diameterMm / 20.0
        return PI * radiusCm * radiusCm
    }
}
