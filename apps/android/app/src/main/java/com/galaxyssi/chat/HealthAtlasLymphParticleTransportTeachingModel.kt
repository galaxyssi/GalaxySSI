package com.galaxyssi.chat

internal object HealthAtlasLymphParticleTransportTeachingModel {
    private const val COLLECTION_MINUTES = 5.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("lymph-particle-transport-flow", 0..20, 8, scale = 4.0),
                label = R.string.health_atlas_lymph_particle_transport_flow,
                unit = "mL/min",
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("lymph-particle-transport-concentration", 0..24, 12, scale = 4.0),
                label = R.string.health_atlas_lymph_particle_transport_concentration,
                unit = "\u00b5g/mL",
            ),
        ),
        axis = 0,
        unit = "\u00b5g/min",
        minimum = 0.0,
        maximum = 30.0,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/21-1-anatomy-of-the-lymphatic-and-immune-systems",
        title = R.string.health_atlas_lymph_particle_transport_title,
        scope = R.string.health_atlas_lymph_particle_transport_scope,
        formula = R.string.health_atlas_lymph_particle_transport_formula,
        companionTitle = R.string.health_atlas_lymph_particle_transport_companion,
        entryIds = setOf("lymph-nodes", "thoracic-duct", "cell-lymphatic-endothelial-cell"),
        evaluate = ::dyeMassRate,
        companionValue = { dyeMassRate(it) * COLLECTION_MINUTES },
    )

    private fun dyeMassRate(values: List<Double>): Double {
        val (flow, concentration) = values
        return concentration * flow
    }
}
