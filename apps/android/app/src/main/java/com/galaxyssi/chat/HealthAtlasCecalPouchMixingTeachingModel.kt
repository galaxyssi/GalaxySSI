package com.galaxyssi.chat

import kotlin.math.pow
import kotlin.math.roundToInt

internal object HealthAtlasCecalPouchMixingTeachingModel {
    private const val MAX_ROUNDS = 6
    private const val MAX_MARKER_AMOUNT = 16

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("cecal-pouch-mixing-rounds", 0..MAX_ROUNDS, 3),
                R.string.health_atlas_cecal_pouch_mixing_rounds,
                unit = "",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("cecal-pouch-mixing-marker-amount", 0..MAX_MARKER_AMOUNT, 12),
                R.string.health_atlas_cecal_pouch_mixing_marker_amount,
                "u",
                digits = 0,
            ),
        ),
        axis = 0,
        unit = "u",
        minimum = 0.0,
        maximum = MAX_MARKER_AMOUNT / 2.0,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-5-the-small-and-large-intestines",
        extraSource = "https://pubmed.ncbi.nlm.nih.gov/18513218/",
        title = R.string.health_atlas_cecal_pouch_mixing_title,
        scope = R.string.health_atlas_cecal_pouch_mixing_scope,
        formula = R.string.health_atlas_cecal_pouch_mixing_formula,
        companionTitle = R.string.health_atlas_cecal_pouch_mixing_companion,
        entryIds = setOf("cecum"),
        evaluate = ::farSideAmount,
        companionValue = { values -> values[1] - farSideAmount(values) },
    )

    private fun farSideAmount(values: List<Double>): Double {
        val (rounds, markerAmount) = values
        // Swapping one quarter from each side halves the difference in each whole round.
        return markerAmount / 2.0 * (1.0 - 0.5.pow(rounds.roundToInt()))
    }
}
