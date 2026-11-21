package com.galaxyssi.chat

import kotlin.math.roundToInt

internal object HealthAtlasMarrowRenewalTeachingModel {
    private const val STARTING_ICONS = 12
    private const val MAX_RENEWAL_ICONS = 12

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("marrow-renewal-added", 0..MAX_RENEWAL_ICONS, 5),
                R.string.health_atlas_marrow_renewal_added,
                unit = "",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("marrow-renewal-left", 0..STARTING_ICONS, 3),
                R.string.health_atlas_marrow_renewal_left,
                unit = "",
                digits = 0,
            ),
        ),
        axis = 0,
        unit = "",
        minimum = -STARTING_ICONS.toDouble(),
        maximum = MAX_RENEWAL_ICONS.toDouble(),
        source = "https://www.cancer.gov/publications/dictionaries/cancer-terms/def/hematopoietic-stem-cell",
        extraSource = "https://openstax.org/books/anatomy-and-physiology-2e/pages/18-2-production-of-the-formed-elements",
        title = R.string.health_atlas_marrow_renewal_title,
        scope = R.string.health_atlas_marrow_renewal_scope,
        formula = R.string.health_atlas_marrow_renewal_formula,
        companionTitle = R.string.health_atlas_marrow_renewal_companion,
        entryIds = setOf("bone-marrow", "cell-hematopoietic-stem-cell"),
        evaluate = ::netChange,
        companionValue = { STARTING_ICONS + netChange(it) },
        digits = 0,
    )

    private fun netChange(values: List<Double>): Double {
        val (added, left) = values
        // The chart samples between slider steps; the tally still counts whole icons.
        return (added.roundToInt() - left.roundToInt()).toDouble()
    }
}
