package com.galaxyssi.chat

internal object HealthAtlasNailPlateAdvanceTeachingModel {
    private const val MAX_STEPS = 12
    private const val MAX_ADDITION = 15
    private const val ADDITION_SCALE = 10.0
    private const val MARK_START = 4.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("nail-plate-advance-steps", 0..MAX_STEPS, 4),
                R.string.health_atlas_nail_plate_advance_steps, "", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("nail-plate-advance-addition", 0..MAX_ADDITION, 8, scale = ADDITION_SCALE),
                R.string.health_atlas_nail_plate_advance_addition, "u", digits = 1,
            ),
        ),
        axis = 0,
        unit = "u",
        minimum = 0.0,
        maximum = MAX_STEPS * (MAX_ADDITION / ADDITION_SCALE),
        source = "https://pubmed.ncbi.nlm.nih.gov/15327543/",
        extraSource = "https://doi.org/10.1002/ar.22660",
        title = R.string.health_atlas_nail_plate_advance_title,
        scope = R.string.health_atlas_nail_plate_advance_scope,
        formula = R.string.health_atlas_nail_plate_advance_formula,
        companionTitle = R.string.health_atlas_nail_plate_advance_mark,
        entryIds = setOf("nails"),
        evaluate = ::advance,
        companionValue = { MARK_START + advance(it) },
        digits = 1,
    )

    private fun advance(values: List<Double>): Double {
        val (steps, addition) = values
        return steps * addition
    }
}
