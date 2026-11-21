package com.galaxyssi.chat

internal object HealthAtlasValveFluxTeachingModel {
    private const val STEADY_INTERVAL_SECONDS = 0.1

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("valve-flux-area", 10..50, 25, 10.0),
                label = R.string.health_atlas_valve_flux_area,
                unit = "cm\u00b2",
                digits = 1,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("valve-flux-speed", 0..100, 50),
                label = R.string.health_atlas_valve_flux_speed,
                unit = "cm/s",
                digits = 0,
            ),
        ),
        axis = 1,
        unit = "mL/s",
        minimum = 0.0,
        maximum = 500.0,
        source = "https://openstax.org/books/college-physics-ap-courses-2e/pages/12-1-flow-rate-and-its-relation-to-velocity",
        title = R.string.health_atlas_valve_flux_title,
        scope = R.string.health_atlas_valve_flux_scope,
        formula = R.string.health_atlas_valve_flux_formula,
        companionTitle = R.string.health_atlas_valve_flux_companion,
        entryIds = setOf("heart-valves", "tricuspid-valve", "mitral-valve", "pulmonary-valve", "aortic-valve"),
        evaluate = ::flowMlPerSecond,
        companionValue = { flowMlPerSecond(it) * STEADY_INTERVAL_SECONDS },
        extraSource = "https://www.nist.gov/pml/owm/si-units-volume",
    )

    private fun flowMlPerSecond(values: List<Double>): Double {
        val (areaCm2, meanForwardSpeedCmPerSecond) = values
        return areaCm2 * meanForwardSpeedCmPerSecond
    }
}
