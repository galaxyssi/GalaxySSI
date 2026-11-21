package com.galaxyssi.chat

internal object HealthAtlasScrotalHeatTallyTeachingModel {
    private const val MAX_HEAT_UNITS = 20
    private const val FULL_SHARE_PERCENT = 100

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("scrotal-heat-tally-surplus", 0..MAX_HEAT_UNITS, 12),
                R.string.health_atlas_scrotal_heat_tally_surplus, "hu", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("scrotal-heat-tally-share", 0..FULL_SHARE_PERCENT, 40),
                R.string.health_atlas_scrotal_heat_tally_share, "%", digits = 0,
            ),
        ),
        axis = 1,
        unit = "hu",
        minimum = 0.0,
        maximum = MAX_HEAT_UNITS.toDouble(),
        source = "https://pmc.ncbi.nlm.nih.gov/articles/PMC12572243/",
        extraSource = "https://pubmed.ncbi.nlm.nih.gov/14507047/",
        title = R.string.health_atlas_scrotal_heat_tally_title,
        scope = R.string.health_atlas_scrotal_heat_tally_scope,
        formula = R.string.health_atlas_scrotal_heat_tally_formula,
        companionTitle = R.string.health_atlas_scrotal_heat_tally_companion,
        entryIds = setOf("scrotum"),
        evaluate = ::transferredHeat,
        companionValue = { values -> values[0] - transferredHeat(values) },
    )

    private fun transferredHeat(values: List<Double>): Double {
        val (surplus, percent) = values
        return surplus * (percent / FULL_SHARE_PERCENT)
    }
}
