package com.galaxyssi.chat

internal object HealthAtlasEndocrineDilutionTeachingModel {
    private const val tracerUnit = "TU"
    private const val volumeUnit = "VU"

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("endocrine-dilution-tracer-amount", 1..12, 6),
                R.string.health_atlas_endocrine_dilution_amount,
                tracerUnit,
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("endocrine-dilution-final-volume", 2..12, 4),
                R.string.health_atlas_endocrine_dilution_volume,
                volumeUnit,
                digits = 0,
            ),
        ),
        axis = 1,
        unit = "$tracerUnit/$volumeUnit",
        minimum = 0.0,
        maximum = 6.0,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-1-an-overview-of-the-endocrine-system",
        title = R.string.health_atlas_endocrine_dilution_title,
        scope = R.string.health_atlas_endocrine_dilution_scope,
        formula = R.string.health_atlas_endocrine_dilution_formula,
        companionTitle = R.string.health_atlas_endocrine_dilution_companion,
        entryIds = setOf(
            "adrenal-glands",
            "cell-adrenocortical-cell",
            "cell-chromaffin-cell",
            "cell-somatotroph",
            "cell-lactotroph",
            "cell-corticotroph",
            "cell-gonadotroph",
            "pancreatic-islets",
            "cell-pancreatic-beta-cell",
            "cell-pancreatic-alpha-cell",
            "cell-pancreatic-delta-cell",
            "cell-pancreatic-pp-cell",
        ),
        evaluate = { (amount, volume) -> amount / volume },
        companionValue = { (amount) -> amount },
        extraSource = "https://openstax.org/books/chemistry-2e/pages/3-3-molarity",
    )
}
