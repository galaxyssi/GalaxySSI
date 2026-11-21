package com.galaxyssi.chat

internal object HealthAtlasSweatDuctBalanceTeachingModel {
    private const val MAX_COIL_SODIUM_NMOL = 160
    private const val WHOLE_PERCENT = 100.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("sweat-duct-coil-sodium", 120..MAX_COIL_SODIUM_NMOL, 140),
                R.string.health_atlas_sweat_duct_balance_coil_sodium,
                "nmol",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("sweat-duct-net-reabsorbed", 0..90, 75),
                R.string.health_atlas_sweat_duct_balance_net_reabsorbed,
                "%",
                digits = 0,
            ),
        ),
        axis = 1,
        unit = "nmol",
        minimum = 0.0,
        maximum = MAX_COIL_SODIUM_NMOL.toDouble(),
        source = "https://pubmed.ncbi.nlm.nih.gov/18653750/",
        title = R.string.health_atlas_sweat_duct_balance_title,
        scope = R.string.health_atlas_sweat_duct_balance_scope,
        formula = R.string.health_atlas_sweat_duct_balance_formula,
        companionTitle = R.string.health_atlas_sweat_duct_balance_companion,
        entryIds = setOf("cell-sweat-gland-secretory-cell", "dermis"),
        evaluate = { values -> values[0] - reabsorbedSodiumNmol(values) },
        companionValue = ::reabsorbedSodiumNmol,
        extraSource = "https://pubmed.ncbi.nlm.nih.gov/7943277/",
    )

    private fun reabsorbedSodiumNmol(values: List<Double>): Double {
        val (coilSodiumNmol, netReabsorbedPercent) = values
        return coilSodiumNmol * (netReabsorbedPercent / WHOLE_PERCENT)
    }
}
