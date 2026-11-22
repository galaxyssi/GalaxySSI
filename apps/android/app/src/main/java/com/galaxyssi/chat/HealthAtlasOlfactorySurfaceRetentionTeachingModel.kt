package com.galaxyssi.chat

internal object HealthAtlasOlfactorySurfaceRetentionTeachingModel {
    private const val MAX_MARKER_AMOUNT = 100
    private const val WHOLE_PERCENT = 100.0
    private const val UNIT = "a.u."

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("olfactory-marker-total", 20..MAX_MARKER_AMOUNT, 80),
                R.string.health_atlas_olfactory_surface_retention_total,
                UNIT,
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("olfactory-mucus-side-share", 0..100, 35),
                R.string.health_atlas_olfactory_surface_retention_mucus_share,
                "%",
                digits = 0,
            ),
        ),
        axis = 1,
        unit = UNIT,
        minimum = 0.0,
        maximum = MAX_MARKER_AMOUNT.toDouble(),
        source = "https://pmc.ncbi.nlm.nih.gov/articles/PMC5515430/",
        title = R.string.health_atlas_olfactory_surface_retention_title,
        scope = R.string.health_atlas_olfactory_surface_retention_scope,
        formula = R.string.health_atlas_olfactory_surface_retention_formula,
        companionTitle = R.string.health_atlas_olfactory_surface_retention_companion,
        entryIds = setOf("olfactory-mucosa"),
        evaluate = ::mucusSideAmount,
        companionValue = { values -> values[0] - mucusSideAmount(values) },
        extraSource = "https://www.nidcd.nih.gov/health/smell-disorders",
    )

    private fun mucusSideAmount(values: List<Double>): Double {
        val (totalMarker, mucusSidePercent) = values
        return totalMarker * (mucusSidePercent / WHOLE_PERCENT)
    }
}
