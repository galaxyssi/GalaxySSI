package com.galaxyssi.chat

import kotlin.math.PI
import kotlin.math.pow

internal object HealthAtlasToothEnamelSectionTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("tooth-enamel-section-thickness", 5..20, 10, scale = 10.0),
                R.string.health_atlas_tooth_enamel_section_thickness,
                "mm",
                digits = 1,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("tooth-enamel-section-radius", 30..60, 40, scale = 10.0),
                R.string.health_atlas_tooth_enamel_section_radius,
                "mm",
                digits = 1,
            ),
        ),
        axis = 0,
        unit = "%",
        minimum = 0.0,
        maximum = 100.0,
        source = "https://www.nidcr.nih.gov/sites/default/files/2021-04/Open-Wide-and-Trek-Inside.pdf",
        title = R.string.health_atlas_tooth_enamel_section_title,
        scope = R.string.health_atlas_tooth_enamel_section_scope,
        formula = R.string.health_atlas_tooth_enamel_section_formula,
        companionTitle = R.string.health_atlas_tooth_enamel_section_companion,
        entryIds = setOf("teeth"),
        evaluate = { (thickness, radius) -> 100.0 * (1.0 - ((radius - thickness) / radius).pow(2)) },
        companionValue = { (thickness, radius) -> PI * (radius - thickness).pow(2) },
        extraSource = "https://webpath.med.utah.edu/HISTHTML/NORMAL/NORM194.html",
    )
}
