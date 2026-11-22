package com.galaxyssi.chat

internal object HealthAtlasAirwayCiliaryClearanceTeachingModel {
    private const val TRACK_LENGTH = 60.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("airway-ciliary-clearance-cycles", 0..24, 12),
                label = R.string.health_atlas_airway_ciliary_clearance_cycles,
                unit = "cycles",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("airway-ciliary-clearance-advance", 0..25, 15, scale = 10.0),
                label = R.string.health_atlas_airway_ciliary_clearance_advance,
                unit = "u/cycle",
                digits = 1,
            ),
        ),
        axis = 0,
        unit = "u",
        minimum = 0.0,
        maximum = TRACK_LENGTH,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/22-1-organs-and-structures-of-the-respiratory-system",
        extraSource = "https://iowaprotocols.medicine.uiowa.edu/protocols/endoscopic-sinus-surgery",
        title = R.string.health_atlas_airway_ciliary_clearance_title,
        scope = R.string.health_atlas_airway_ciliary_clearance_scope,
        formula = R.string.health_atlas_airway_ciliary_clearance_formula,
        companionTitle = R.string.health_atlas_airway_ciliary_clearance_progress,
        entryIds = setOf(
            "nose",
            "nasal-cavity",
            "paranasal-sinuses",
            "tissue-respiratory-epithelium",
            "cell-ciliated-airway-cell",
        ),
        evaluate = ::markerTravel,
        companionValue = { 100.0 * markerTravel(it) / TRACK_LENGTH },
        digits = 1,
    )

    private fun markerTravel(values: List<Double>): Double {
        val (cycles, advancePerCycle) = values
        return cycles * advancePerCycle
    }
}
