package com.galaxyssi.chat

import kotlin.math.roundToInt

internal object HealthAtlasLangerhansDendriteReachTeachingModel {
    private const val PATCH_SPACES = 10
    private const val MAX_REACH = 8

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("langerhans-dendrite-reach-left", 0..MAX_REACH, 6),
                R.string.health_atlas_langerhans_dendrite_reach_left, unit = "", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("langerhans-dendrite-reach-right", 0..MAX_REACH, 5),
                R.string.health_atlas_langerhans_dendrite_reach_right, unit = "", digits = 0,
            ),
        ),
        axis = 0,
        unit = "",
        minimum = 0.0,
        maximum = PATCH_SPACES.toDouble(),
        source = "https://pubmed.ncbi.nlm.nih.gov/9435249/",
        title = R.string.health_atlas_langerhans_dendrite_reach_title,
        scope = R.string.health_atlas_langerhans_dendrite_reach_scope,
        formula = R.string.health_atlas_langerhans_dendrite_reach_formula,
        companionTitle = R.string.health_atlas_langerhans_dendrite_reach_companion,
        entryIds = setOf("cell-langerhans-cell"),
        evaluate = { totalReach(it).coerceAtMost(PATCH_SPACES).toDouble() },
        companionValue = { (totalReach(it) - PATCH_SPACES).coerceAtLeast(0).toDouble() },
        digits = 0,
    )

    private fun totalReach(values: List<Double>): Int {
        val (left, right) = values
        return left.roundToInt() + right.roundToInt()
    }
}
