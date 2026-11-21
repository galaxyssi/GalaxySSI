package com.galaxyssi.chat

internal object HealthAtlasEpendymalBeatPhaseTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("ependymal-beat-phase-frequency", 2..8, 5, scale = 4.0),
                label = R.string.health_atlas_ependymal_beat_phase_frequency,
                unit = "cycles/interval",
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("ependymal-beat-phase-offset", 0..8, 5, scale = 4.0),
                label = R.string.health_atlas_ependymal_beat_phase_offset,
                unit = "intervals",
            ),
        ),
        axis = 1,
        unit = "cycles",
        minimum = 0.0,
        maximum = 4.0,
        source = "https://nba.uth.tmc.edu/neuroscience/m/s1/chapter08.html",
        extraSource = "https://pubmed.ncbi.nlm.nih.gov/27387952/",
        title = R.string.health_atlas_ependymal_beat_phase_title,
        scope = R.string.health_atlas_ependymal_beat_phase_scope,
        formula = R.string.health_atlas_ependymal_beat_phase_formula,
        companionTitle = R.string.health_atlas_ependymal_beat_phase_wrapped,
        entryIds = setOf("cell-ependymal-cell"),
        evaluate = ::unwrappedPhase,
        companionValue = { unwrappedPhase(it) % 1.0 },
    )

    private fun unwrappedPhase(values: List<Double>): Double {
        val (frequency, offset) = values
        return frequency * offset
    }
}
