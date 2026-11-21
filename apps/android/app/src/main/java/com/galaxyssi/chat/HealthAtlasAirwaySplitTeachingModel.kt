package com.galaxyssi.chat

internal object HealthAtlasAirwaySplitTeachingModel {
    private const val flowUnit = "L/s"
    private const val resistanceUnit = "cmH\u2082O\u00b7s/L"

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("airway-split-total-flow", 10..60, 30, 100.0),
                R.string.health_atlas_airway_split_total_flow,
                flowUnit,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("airway-split-selected-resistance", 10..40, 15, 10.0),
                R.string.health_atlas_airway_split_selected_resistance,
                resistanceUnit,
                digits = 1,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("airway-split-other-resistance", 10..40, 30, 10.0),
                R.string.health_atlas_airway_split_other_resistance,
                resistanceUnit,
                digits = 1,
            ),
        ),
        axis = 1,
        unit = flowUnit,
        minimum = 0.0,
        maximum = 0.50,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/22-3-the-process-of-breathing",
        title = R.string.health_atlas_airway_split_title,
        scope = R.string.health_atlas_airway_split_scope,
        formula = R.string.health_atlas_airway_split_formula,
        companionTitle = R.string.health_atlas_airway_split_companion,
        entryIds = setOf("trachea", "bronchi", "bronchioles"),
        evaluate = { (total, selected, other) -> branchFlow(total, selected, other) },
        companionValue = { (total, selected, other) -> branchFlow(total, other, selected) },
        extraSource = "https://openstax.org/books/university-physics-volume-2/pages/10-2-resistors-in-series-and-parallel",
    )

    private fun branchFlow(total: Double, ownResistance: Double, otherResistance: Double): Double =
        total * otherResistance / (ownResistance + otherResistance)
}
