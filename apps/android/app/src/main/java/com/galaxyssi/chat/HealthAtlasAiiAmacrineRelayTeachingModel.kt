package com.galaxyssi.chat

internal object HealthAtlasAiiAmacrineRelayTeachingModel {
    private const val MAX_MAGNITUDE = 10

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("aii-amacrine-relay-input", -MAX_MAGNITUDE..MAX_MAGNITUDE, 4),
                R.string.health_atlas_aii_amacrine_relay_input, "u", digits = 0,
            ),
        ),
        axis = 0,
        unit = "u",
        minimum = -MAX_MAGNITUDE.toDouble(),
        maximum = MAX_MAGNITUDE.toDouble(),
        source = "https://pmc.ncbi.nlm.nih.gov/articles/PMC6133723/",
        extraSource = "https://escholarship.org/content/qt81b3q81m/qt81b3q81m.pdf",
        title = R.string.health_atlas_aii_amacrine_relay_title,
        scope = R.string.health_atlas_aii_amacrine_relay_scope,
        formula = R.string.health_atlas_aii_amacrine_relay_formula,
        companionTitle = R.string.health_atlas_aii_amacrine_relay_companion,
        entryIds = setOf("cell-retinal-aii-amacrine-cell"),
        evaluate = { it.single() },
        companionValue = { 0.0 - it.single() },
        digits = 0,
    )
}
