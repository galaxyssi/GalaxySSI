package com.galaxyssi.chat

internal object HealthAtlasBoneRemodelingBalanceTeachingModel {
    private const val STARTING_AMOUNT_AU = 100.0
    private const val MAX_TRANSFER_AU = 20
    private const val UNIT = "a.u."

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("bone-remodeling-resorbed", 0..MAX_TRANSFER_AU, 10),
                R.string.health_atlas_bone_remodeling_balance_resorbed,
                UNIT,
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("bone-remodeling-formed", 0..MAX_TRANSFER_AU, 10),
                R.string.health_atlas_bone_remodeling_balance_formed,
                UNIT,
                digits = 0,
            ),
        ),
        axis = 0,
        unit = UNIT,
        minimum = -MAX_TRANSFER_AU.toDouble(),
        maximum = MAX_TRANSFER_AU.toDouble(),
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/6-3-bone-structure",
        title = R.string.health_atlas_bone_remodeling_balance_title,
        scope = R.string.health_atlas_bone_remodeling_balance_scope,
        formula = R.string.health_atlas_bone_remodeling_balance_formula,
        companionTitle = R.string.health_atlas_bone_remodeling_balance_companion,
        entryIds = setOf("cell-osteoblast", "cell-osteoclast", "cell-osteocyte"),
        evaluate = ::netChange,
        companionValue = { STARTING_AMOUNT_AU + netChange(it) },
        extraSource = "https://www.ncbi.nlm.nih.gov/sites/books/NBK279149/",
        digits = 0,
    )

    private fun netChange(values: List<Double>): Double {
        val (resorbed, formed) = values
        return formed - resorbed
    }
}
