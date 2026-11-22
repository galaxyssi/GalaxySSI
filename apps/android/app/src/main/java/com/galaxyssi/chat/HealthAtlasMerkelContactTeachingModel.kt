package com.galaxyssi.chat

import kotlin.math.PI

internal object HealthAtlasMerkelContactTeachingModel {
    private const val MAX_FORCE_MN = 80
    private const val MIN_RADIUS_TENTHS_MM = 10
    private const val RADIUS_SCALE = 10.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("merkel-contact-force", 10..MAX_FORCE_MN, 40),
                label = R.string.health_atlas_merkel_contact_force,
                unit = "mN",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput(
                    "merkel-contact-radius", MIN_RADIUS_TENTHS_MM..40, 20, scale = RADIUS_SCALE,
                ),
                label = R.string.health_atlas_merkel_contact_radius,
                unit = "mm",
                digits = 1,
            ),
        ),
        axis = 0,
        unit = "kPa",
        minimum = 0.0,
        maximum = MAX_FORCE_MN / contactAreaMm2(MIN_RADIUS_TENTHS_MM / RADIUS_SCALE),
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/5-1-layers-of-the-skin",
        extraSource = "https://pubmed.ncbi.nlm.nih.gov/24717432/",
        title = R.string.health_atlas_merkel_contact_title,
        scope = R.string.health_atlas_merkel_contact_scope,
        formula = R.string.health_atlas_merkel_contact_formula,
        companionTitle = R.string.health_atlas_merkel_contact_companion,
        entryIds = setOf("cell-merkel-cell"),
        // 1 mN/mm^2 = 1 kPa. This is a surface average, not pressure at the receptor.
        evaluate = { (forceMn, radiusMm) -> forceMn / contactAreaMm2(radiusMm) },
        companionValue = { (_, radiusMm) -> contactAreaMm2(radiusMm) },
    )

    private fun contactAreaMm2(radiusMm: Double): Double = PI * radiusMm * radiusMm
}
