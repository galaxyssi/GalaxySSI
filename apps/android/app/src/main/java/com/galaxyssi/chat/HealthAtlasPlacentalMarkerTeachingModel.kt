package com.galaxyssi.chat

internal object HealthAtlasPlacentalMarkerTeachingModel {
    const val MAX_STARTING_UNITS = 120

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(HealthAtlasInput("placental-marker-amount", 40..MAX_STARTING_UNITS, 80),
                R.string.health_atlas_placental_marker_amount, "a.u.", digits = 0),
            HealthAtlasTeachingInput(HealthAtlasInput("placental-marker-equilibration", 0..100, 50),
                R.string.health_atlas_placental_marker_equilibration, "%", digits = 0),
        ),
        axis = 1,
        unit = "a.u.",
        minimum = 0.0,
        maximum = MAX_STARTING_UNITS / 2.0,
        source = "https://www.ncbi.nlm.nih.gov/books/NBK53254/",
        extraSource = "https://pmc.ncbi.nlm.nih.gov/articles/PMC7613408/",
        title = R.string.health_atlas_placental_marker_title,
        scope = R.string.health_atlas_placental_marker_scope,
        formula = R.string.health_atlas_placental_marker_formula,
        companionTitle = R.string.health_atlas_placental_marker_remaining,
        entryIds = setOf("placenta", "cell-trophoblast"),
        evaluate = { (amount, percent) -> equilibriumShare(amount, percent) },
        companionValue = { (amount, percent) -> amount - equilibriumShare(amount, percent) },
    )

    data class Amounts(val maternal: Double, val fetal: Double)

    fun atPhase(total: Double, finalTransfer: Double, phase: Float): Amounts {
        val moved = finalTransfer * phase
        return Amounts(total - moved, moved)
    }

    private fun equilibriumShare(start: Double, percent: Double) = start * (percent / 200.0)
}
