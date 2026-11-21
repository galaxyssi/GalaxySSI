package com.galaxyssi.chat

internal object HealthAtlasColonicWaterBalanceTeachingModel {
    private const val MAX_STARTING_ML = 1000
    private const val WHOLE_PERCENT = 100.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("colonic-water-starting-volume", 100..MAX_STARTING_ML, 500),
                R.string.health_atlas_colonic_water_balance_starting_volume,
                "mL",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("colonic-water-net-absorbed", 0..100, 80),
                R.string.health_atlas_colonic_water_balance_net_absorbed,
                "%",
                digits = 0,
            ),
        ),
        axis = 1,
        unit = "mL",
        minimum = 0.0,
        maximum = MAX_STARTING_ML.toDouble(),
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-7-chemical-digestion-and-absorption-a-closer-look",
        title = R.string.health_atlas_colonic_water_balance_title,
        scope = R.string.health_atlas_colonic_water_balance_scope,
        formula = R.string.health_atlas_colonic_water_balance_formula,
        companionTitle = R.string.health_atlas_colonic_water_balance_companion,
        entryIds = setOf("large-intestine", "colon"),
        evaluate = { values -> values[0] - absorbedMl(values) },
        companionValue = ::absorbedMl,
    )

    private fun absorbedMl(values: List<Double>): Double {
        val (startingMl, netAbsorbedPercent) = values
        return startingMl * (netAbsorbedPercent / WHOLE_PERCENT)
    }
}
