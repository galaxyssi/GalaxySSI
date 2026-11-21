package com.galaxyssi.chat

import kotlin.math.asin
import kotlin.math.sin

internal object HealthAtlasCornealRefractionTeachingModel {
    private const val AIR_INDEX = 1.0
    private const val DEGREES = "\u00b0"

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("corneal-refraction-incident-angle", 0..80, 40),
                label = R.string.health_atlas_model_corneal_refraction_incident_angle,
                unit = DEGREES,
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("corneal-refraction-medium-index", 130..145, 134, scale = 100.0),
                label = R.string.health_atlas_model_corneal_refraction_medium_index,
                unit = "",
            ),
        ),
        axis = 0,
        unit = DEGREES,
        minimum = 0.0,
        maximum = 50.0,
        source = "https://openstax.org/books/college-physics-2e/pages/25-3-the-law-of-refraction",
        title = R.string.health_atlas_model_corneal_refraction_title,
        scope = R.string.health_atlas_model_corneal_refraction_scope,
        formula = R.string.health_atlas_model_corneal_refraction_formula,
        companionTitle = R.string.health_atlas_model_corneal_refraction_companion,
        entryIds = setOf("cornea", "cell-corneal-epithelial-cell"),
        evaluate = { (incident, mediumIndex) -> refractedDegrees(incident, mediumIndex) },
        companionValue = { (incident, mediumIndex) -> incident - refractedDegrees(incident, mediumIndex) },
        extraSource = "https://pubmed.ncbi.nlm.nih.gov/22488267/",
    )

    private fun refractedDegrees(incidentDegrees: Double, mediumIndex: Double): Double =
        Math.toDegrees(asin(AIR_INDEX / mediumIndex * sin(Math.toRadians(incidentDegrees))))
}
