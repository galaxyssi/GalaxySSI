package com.galaxyssi.chat

internal object HealthAtlasExternalEarResonanceTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("external-ear-resonance-length", 10..50, 20),
                label = R.string.health_atlas_model_external_ear_resonance_length,
                unit = "cm",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("external-ear-resonance-speed", 330..360, 343),
                label = R.string.health_atlas_model_external_ear_resonance_speed,
                unit = "m/s",
                digits = 0,
            ),
        ),
        axis = 0,
        unit = "Hz",
        minimum = 150.0,
        maximum = 950.0,
        source = "https://openstax.org/books/university-physics-volume-1/pages/17-4-normal-modes-of-a-standing-sound-wave",
        title = R.string.health_atlas_model_external_ear_resonance_title,
        scope = R.string.health_atlas_model_external_ear_resonance_scope,
        formula = R.string.health_atlas_model_external_ear_resonance_formula,
        companionTitle = R.string.health_atlas_model_external_ear_resonance_wavelength,
        entryIds = setOf("external-ear"),
        evaluate = { (lengthCm, speedMps) -> speedMps / (4.0 * (lengthCm / 100.0)) },
        companionValue = { (lengthCm) -> 4.0 * lengthCm },
        extraSource = "https://pubmed.ncbi.nlm.nih.gov/2745873/",
    )
}
