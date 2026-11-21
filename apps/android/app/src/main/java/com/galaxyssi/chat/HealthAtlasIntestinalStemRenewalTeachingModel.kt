package com.galaxyssi.chat

import kotlin.math.roundToInt

internal object HealthAtlasIntestinalStemRenewalTeachingModel {
    private const val LINING_SLOTS = 12

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("intestinal-stem-renewal-steps", 0..6, 2),
                R.string.health_atlas_intestinal_stem_model_steps, unit = "", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("intestinal-stem-renewal-base-icons", 1..4, 3),
                R.string.health_atlas_intestinal_stem_model_base_icons, unit = "", digits = 0,
            ),
        ),
        axis = 0,
        unit = "",
        minimum = 0.0,
        maximum = LINING_SLOTS.toDouble(),
        source = "https://pubmed.ncbi.nlm.nih.gov/19156773/",
        extraSource = "https://histology.oit.duke.edu/NormalBody/GItract/GItract_answers.html",
        title = R.string.health_atlas_intestinal_stem_model_title,
        scope = R.string.health_atlas_intestinal_stem_model_scope,
        formula = R.string.health_atlas_intestinal_stem_model_formula,
        companionTitle = R.string.health_atlas_intestinal_stem_model_companion,
        entryIds = setOf("cell-intestinal-stem-cell"),
        evaluate = ::filledSlots,
        companionValue = { LINING_SLOTS - filledSlots(it) },
        digits = 0,
    )

    private fun filledSlots(values: List<Double>): Double {
        val (steps, baseIcons) = values
        // Fractional chart samples still represent whole diagram steps.
        return minOf(LINING_SLOTS, steps.roundToInt() * baseIcons.roundToInt()).toDouble()
    }
}
