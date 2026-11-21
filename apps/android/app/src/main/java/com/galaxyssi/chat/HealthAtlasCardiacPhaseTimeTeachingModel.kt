package com.galaxyssi.chat

internal object HealthAtlasCardiacPhaseTimeTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("cardiac-phase-time-rate", 50..150, 75),
                label = R.string.health_atlas_cardiac_phase_time_rate,
                unit = "bpm",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("cardiac-phase-time-filling-percent", 30..70, 50),
                label = R.string.health_atlas_cardiac_phase_time_filling_percent,
                unit = "%",
                digits = 0,
            ),
        ),
        axis = 1,
        unit = "ms",
        minimum = 0.0,
        maximum = 1200.0,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/19-3-cardiac-cycle",
        title = R.string.health_atlas_cardiac_phase_time_title,
        scope = R.string.health_atlas_cardiac_phase_time_scope,
        formula = R.string.health_atlas_cardiac_phase_time_formula,
        companionTitle = R.string.health_atlas_cardiac_phase_time_companion,
        entryIds = setOf(
            "cardio", "heart", "atria", "left-atrium", "right-atrium",
            "tissue-cardiac-muscle", "cell-cardiomyocyte",
        ),
        evaluate = { (bpm, fillingPercent) -> cycleMs(bpm) * (fillingPercent / 100.0) },
        companionValue = { (bpm) -> cycleMs(bpm) },
        extraSource = "https://pubmed.ncbi.nlm.nih.gov/15217800/",
        digits = 1,
    )

    private fun cycleMs(bpm: Double): Double = 60_000.0 / bpm
}
