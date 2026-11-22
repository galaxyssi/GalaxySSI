package com.galaxyssi.chat

import kotlin.math.pow

internal object HealthAtlasCochlearFrequencyTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("cochlear-frequency-position", 0..100, 50, 100.0),
                label = R.string.health_atlas_model_cochlear_frequency_position,
                unit = "",
            ),
        ),
        axis = 0,
        unit = "Hz",
        minimum = 0.0,
        maximum = 21_000.0,
        source = "https://pubmed.ncbi.nlm.nih.gov/2373794/",
        title = R.string.health_atlas_model_cochlear_frequency_title,
        scope = R.string.health_atlas_model_cochlear_frequency_scope,
        formula = R.string.health_atlas_model_cochlear_frequency_formula,
        companionTitle = R.string.health_atlas_model_cochlear_frequency_from_base,
        entryIds = setOf("cochlea", "inner-ear", "cell-inner-ear-hair-cell"),
        // Greenwood (1990), Eq. 1, with x as the fraction of basilar membrane length from the apex.
        evaluate = { (x) -> 165.4 * (10.0.pow(2.1 * x) - 0.88) },
        companionValue = { (x) -> 100.0 * (1.0 - x) },
        extraSource = "https://www.nidcd.nih.gov/research/labs/section-sensory-cell-biology",
    )
}
