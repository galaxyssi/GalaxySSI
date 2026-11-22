package com.galaxyssi.chat

internal object HealthAtlasImmuneCompositionTeachingModel {
    private const val countUnit = "cells"

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("immune-composition-sample-size", 1..5, 2, 0.01),
                R.string.health_atlas_immune_composition_sample_size,
                countUnit,
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("immune-composition-selected-percent", 0..100, 25),
                R.string.health_atlas_immune_composition_selected_percent,
                "%",
                digits = 0,
            ),
        ),
        axis = 1,
        unit = countUnit,
        minimum = 0.0,
        maximum = 500.0,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/18-4-leukocytes-and-platelets",
        title = R.string.health_atlas_immune_composition_title,
        scope = R.string.health_atlas_immune_composition_scope,
        formula = R.string.health_atlas_immune_composition_formula,
        companionTitle = R.string.health_atlas_immune_composition_companion,
        entryIds = setOf(
            "immune",
            "cell-neutrophil",
            "cell-eosinophil",
            "cell-basophil",
            "cell-monocyte",
            "cell-t-cell",
            "cell-b-cell",
            "cell-natural-killer-cell",
        ),
        evaluate = { (sampleSize, percent) -> selectedCount(sampleSize, percent) },
        companionValue = { (sampleSize, percent) -> sampleSize - selectedCount(sampleSize, percent) },
        digits = 0,
    )

    private fun selectedCount(sampleSize: Double, percent: Double): Double = sampleSize * percent / 100.0
}
