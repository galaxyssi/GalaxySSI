package com.galaxyssi.chat

import kotlin.math.PI

internal object HealthAtlasBoneSectionTeachingModel {
    private const val OUTER_RADIUS_MM = 5.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("bone-section-force", 0..120, 60),
                R.string.health_atlas_bone_section_force, "N", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("bone-section-wall-thickness", 10..30, 20, scale = 10.0),
                R.string.health_atlas_bone_section_wall_thickness, "mm", digits = 1,
            ),
        ),
        axis = 0,
        unit = "MPa",
        minimum = 0.0,
        maximum = 5.0,
        source = "https://openstax.org/books/university-physics-volume-1/pages/12-3-stress-strain-and-elastic-modulus",
        title = R.string.health_atlas_bone_section_title,
        scope = R.string.health_atlas_bone_section_scope,
        formula = R.string.health_atlas_bone_section_formula,
        companionTitle = R.string.health_atlas_bone_section_area,
        entryIds = setOf("tissue-compact-bone", "clavicle", "hand-bones", "foot-bones"),
        // Force in N divided by area in mm^2 gives the stress magnitude in MPa.
        evaluate = { (force, thickness) -> force / corticalAreaMm2(thickness) },
        companionValue = { (_, thickness) -> corticalAreaMm2(thickness) },
        extraSource = "https://openstax.org/books/anatomy-and-physiology-2e/pages/6-3-bone-structure",
    )

    private fun corticalAreaMm2(thickness: Double): Double {
        val innerRadius = OUTER_RADIUS_MM - thickness
        return PI * (OUTER_RADIUS_MM * OUTER_RADIUS_MM - innerRadius * innerRadius)
    }
}
