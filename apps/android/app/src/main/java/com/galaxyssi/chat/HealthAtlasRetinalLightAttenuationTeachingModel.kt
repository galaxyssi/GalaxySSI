package com.galaxyssi.chat

import kotlin.math.exp

internal object HealthAtlasRetinalLightAttenuationTeachingModel {
    private const val INCIDENT_LIGHT = 100.0
    private const val UNIT = "a.u."

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("retinal-light-attenuation-coefficient", 1..10, 5, 10.0),
                R.string.health_atlas_retinal_light_attenuation_coefficient,
                "1/$UNIT",
                digits = 1,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("retinal-light-attenuation-path-length", 0..40, 20, 10.0),
                R.string.health_atlas_retinal_light_attenuation_path_length,
                UNIT,
                digits = 1,
            ),
        ),
        axis = 1,
        unit = UNIT,
        minimum = 0.0,
        maximum = INCIDENT_LIGHT,
        source = "https://www.webvision.pitt.edu/book/part-i-foundations/how-the-retina-works/",
        title = R.string.health_atlas_retinal_light_attenuation_title,
        scope = R.string.health_atlas_retinal_light_attenuation_scope,
        formula = R.string.health_atlas_retinal_light_attenuation_formula,
        companionTitle = R.string.health_atlas_retinal_light_attenuation_companion,
        entryIds = setOf("cell-cone-photoreceptor", "cell-retinal-pigment-epithelial-cell"),
        evaluate = ::transmittedLight,
        companionValue = { INCIDENT_LIGHT - transmittedLight(it) },
        extraSource = "https://goldbook.iupac.org/terms/view/B00626/pdf",
    )

    private fun transmittedLight(values: List<Double>): Double {
        val (coefficient, pathLength) = values
        return INCIDENT_LIGHT * exp(-coefficient * pathLength)
    }
}
