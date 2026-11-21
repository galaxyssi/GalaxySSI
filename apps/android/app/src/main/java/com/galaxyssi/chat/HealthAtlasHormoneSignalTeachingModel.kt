package com.galaxyssi.chat

import kotlin.math.pow

internal object HealthAtlasHormoneSignalTeachingModel {
    private const val START_PERCENT = 100.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("hormone-signal-half-life", 10..40, 20, scale = 10.0),
                label = R.string.health_atlas_hormone_signal_half_life,
                unit = "",
                digits = 1,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("hormone-signal-elapsed", 0..80, 40, scale = 10.0),
                label = R.string.health_atlas_hormone_signal_elapsed,
                unit = "",
                digits = 1,
            ),
        ),
        axis = 1,
        unit = "%",
        minimum = 0.0,
        maximum = START_PERCENT,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-2-hormones",
        title = R.string.health_atlas_hormone_signal_title,
        scope = R.string.health_atlas_hormone_signal_scope,
        formula = R.string.health_atlas_hormone_signal_formula,
        companionTitle = R.string.health_atlas_hormone_signal_removed,
        entryIds = setOf("endocrine", "pituitary-gland", "cell-thyrotroph"),
        evaluate = ::remainingPercent,
        companionValue = { START_PERCENT - remainingPercent(it) },
        extraSource = "https://pubmed.ncbi.nlm.nih.gov/2823271/",
    )

    private fun remainingPercent(values: List<Double>): Double {
        val (halfLife, elapsed) = values
        return START_PERCENT * 2.0.pow(-elapsed / halfLife)
    }
}
