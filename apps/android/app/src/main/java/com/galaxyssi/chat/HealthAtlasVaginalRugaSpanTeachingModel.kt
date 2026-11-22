package com.galaxyssi.chat

import kotlin.math.sqrt

internal object HealthAtlasVaginalRugaSpanTeachingModel {
    private const val SIDE_LENGTH_U = 5.0
    private const val FLAT_SPAN_U = 2.0 * SIDE_LENGTH_U

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("vaginal-ruga-span-height", 0..40, 30, scale = 10.0),
                R.string.health_atlas_vaginal_ruga_span_height, "u", digits = 1,
            ),
        ),
        axis = 0,
        unit = "u",
        minimum = 6.0,
        maximum = FLAT_SPAN_U,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-2-anatomy-and-physiology-of-the-ovarian-reproductive-system",
        extraSource = "https://pmc.ncbi.nlm.nih.gov/articles/PMC5382597/",
        title = R.string.health_atlas_vaginal_ruga_span_title,
        scope = R.string.health_atlas_vaginal_ruga_span_scope,
        formula = R.string.health_atlas_vaginal_ruga_span_formula,
        companionTitle = R.string.health_atlas_vaginal_ruga_span_companion,
        entryIds = setOf("vagina"),
        evaluate = { (height) -> projectedSpan(height) },
        companionValue = { (height) -> FLAT_SPAN_U - projectedSpan(height) },
    )

    private fun projectedSpan(height: Double): Double =
        2.0 * sqrt(SIDE_LENGTH_U * SIDE_LENGTH_U - height * height)
}
