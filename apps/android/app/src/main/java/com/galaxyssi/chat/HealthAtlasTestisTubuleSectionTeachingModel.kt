package com.galaxyssi.chat

import kotlin.math.PI
import kotlin.math.pow

internal object HealthAtlasTestisTubuleSectionTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("testis-tubule-section-radius", 40..80, 60, scale = 10.0),
                R.string.health_atlas_testis_tubule_section_radius, "u", digits = 1,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("testis-tubule-section-thickness", 10..30, 20, scale = 10.0),
                R.string.health_atlas_testis_tubule_section_thickness, "u", digits = 1,
            ),
        ),
        axis = 1,
        unit = "%",
        minimum = 0.0,
        maximum = 100.0,
        source = "https://www.histologyguide.com/slideview/MH-178a-testis/19-slide-1.html",
        title = R.string.health_atlas_testis_tubule_section_title,
        scope = R.string.health_atlas_testis_tubule_section_scope,
        formula = R.string.health_atlas_testis_tubule_section_formula,
        companionTitle = R.string.health_atlas_testis_tubule_section_companion,
        entryIds = setOf(
            "testes", "cell-sertoli-cell", "cell-leydig-cell", "cell-spermatogonium", "cell-spermatocyte",
        ),
        evaluate = { (radius, thickness) -> 100.0 * (1.0 - ((radius - thickness) / radius).pow(2)) },
        companionValue = { (radius, thickness) -> PI * (radius - thickness).pow(2) },
        extraSource = "https://ocw.mit.edu/courses/18-01-single-variable-calculus-fall-2005/c08b62b60d20c5151c369bc284280c54_lecture_19.pdf",
    )
}
