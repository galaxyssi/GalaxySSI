package com.galaxyssi.chat

internal object HealthAtlasRetinalConvergenceTeachingModel {
    private const val MAX_SAMPLES = 16

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("retinal-convergence-samples", 1..MAX_SAMPLES, 8),
                label = R.string.health_atlas_retinal_convergence_samples,
                unit = "",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("retinal-convergence-lit-percent", 0..100, 25),
                label = R.string.health_atlas_retinal_convergence_lit_percent,
                unit = "%",
                digits = 0,
            ),
        ),
        axis = 1,
        unit = "",
        minimum = 0.0,
        maximum = MAX_SAMPLES.toDouble(),
        source = "https://www.webvision.pitt.edu/book/part-viii-psychophysics-of-vision/visual-acuity/",
        title = R.string.health_atlas_retinal_convergence_title,
        scope = R.string.health_atlas_retinal_convergence_scope,
        formula = R.string.health_atlas_retinal_convergence_formula,
        companionTitle = R.string.health_atlas_retinal_convergence_companion,
        entryIds = setOf("cell-retinal-ganglion-cell", "cell-retinal-bipolar-cell"),
        // Expectations add even without assuming independence between samples.
        evaluate = { (samples, litPercent) -> samples * (litPercent / 100.0) },
        companionValue = { (samples, litPercent) -> samples * (1.0 - litPercent / 100.0) },
        extraSource = "https://elifesciences.org/articles/05241",
    )
}
