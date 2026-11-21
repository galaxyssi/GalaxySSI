package com.galaxyssi.chat

import kotlin.math.PI

internal object HealthAtlasThoracicCrossSectionTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("thoracic-cross-section-front-to-back", 12..24, 18),
                R.string.health_atlas_thoracic_cross_section_front_to_back,
                "cm",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("thoracic-cross-section-side-to-side", 24..36, 30),
                R.string.health_atlas_thoracic_cross_section_side_to_side,
                "cm",
                digits = 0,
            ),
        ),
        axis = 0,
        unit = "cm\u00b2",
        minimum = 200.0,
        maximum = 700.0,
        source = "https://sta.uwi.edu/fms/MDSC1001/Thorax_Thoracic_wall.pdf",
        title = R.string.health_atlas_thoracic_cross_section_title,
        scope = R.string.health_atlas_thoracic_cross_section_scope,
        formula = R.string.health_atlas_thoracic_cross_section_formula,
        companionTitle = R.string.health_atlas_thoracic_cross_section_companion,
        entryIds = setOf("ribs", "sternum"),
        evaluate = { (frontToBack, sideToSide) -> PI * frontToBack * sideToSide / 4.0 },
        companionValue = { (frontToBack, sideToSide) -> frontToBack / sideToSide },
        extraSource = "https://openstax.org/books/calculus-volume-3/pages/6-4-greens-theorem",
    )
}
