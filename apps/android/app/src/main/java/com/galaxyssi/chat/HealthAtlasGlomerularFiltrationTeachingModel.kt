package com.galaxyssi.chat

internal object HealthAtlasGlomerularFiltrationTeachingModel {
    private const val PRESSURE_UNIT = "mmHg"

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("glomerular-filtration-capillary-hydrostatic", 40..65, 52),
                R.string.health_atlas_glomerular_filtration_capillary_hydrostatic,
                PRESSURE_UNIT,
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("glomerular-filtration-capsular-hydrostatic", 8..20, 12),
                R.string.health_atlas_glomerular_filtration_capsular_hydrostatic,
                PRESSURE_UNIT,
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("glomerular-filtration-capillary-oncotic", 18..35, 28),
                R.string.health_atlas_glomerular_filtration_capillary_oncotic,
                PRESSURE_UNIT,
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("glomerular-filtration-kf", 5..50, 25, scale = 10.0),
                R.string.health_atlas_glomerular_filtration_coefficient,
                "nL/(min\u00b7mmHg)",
                digits = 1,
            ),
        ),
        axis = 0,
        unit = "nL/min",
        minimum = 0.0,
        maximum = 200.0, // Largest slider result: (65 - 8 - 18) * 5 = 195 nL/min.
        source = "https://journals.physiology.org/doi/10.1152/advan.00120.2024",
        title = R.string.health_atlas_glomerular_filtration_title,
        scope = R.string.health_atlas_glomerular_filtration_scope,
        formula = R.string.health_atlas_glomerular_filtration_formula,
        companionTitle = R.string.health_atlas_glomerular_filtration_net_pressure,
        entryIds = setOf("glomerulus", "bowmans-capsule", "cell-podocyte"),
        evaluate = { values ->
            val filtrationCoefficient = values[3]
            maxOf(0.0, netPressure(values)) * filtrationCoefficient
        },
        companionValue = ::netPressure,
        digits = 1,
    )

    private fun netPressure(values: List<Double>): Double {
        val (capillaryHydrostatic, capsularHydrostatic, capillaryOncotic) = values
        return capillaryHydrostatic - capsularHydrostatic - capillaryOncotic
    }
}
