package com.galaxyssi.chat

import kotlin.math.pow

internal object HealthAtlasGastricLiquidEmptyingTeachingModel {
    private const val START_PERCENT = 100.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("gastric-liquid-removal", 5..40, 20),
                R.string.health_atlas_gastric_liquid_emptying_removal,
                "%",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("gastric-liquid-intervals", 0..10, 4),
                R.string.health_atlas_gastric_liquid_emptying_intervals,
                "",
                digits = 0,
            ),
        ),
        axis = 1,
        unit = "%",
        minimum = 0.0,
        maximum = START_PERCENT,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-4-the-stomach",
        title = R.string.health_atlas_gastric_liquid_emptying_title,
        scope = R.string.health_atlas_gastric_liquid_emptying_scope,
        formula = R.string.health_atlas_gastric_liquid_emptying_formula,
        companionTitle = R.string.health_atlas_gastric_liquid_emptying_companion,
        entryIds = setOf("stomach"),
        evaluate = ::remainingPercent,
        companionValue = { START_PERCENT - remainingPercent(it) },
        extraSource = "https://pmc.ncbi.nlm.nih.gov/articles/PMC1159224/",
    )

    private fun remainingPercent(values: List<Double>): Double {
        val (removalPercent, intervals) = values
        return START_PERCENT * (1.0 - removalPercent / START_PERCENT).pow(intervals)
    }
}
