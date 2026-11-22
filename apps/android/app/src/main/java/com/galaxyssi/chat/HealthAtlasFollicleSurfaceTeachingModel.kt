package com.galaxyssi.chat

import kotlin.math.PI
import kotlin.math.pow

internal object HealthAtlasFollicleSurfaceTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("follicle-surface-cavity-diameter", 4..14, 8),
                label = R.string.health_atlas_follicle_surface_cavity_diameter,
                unit = "mm",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("follicle-surface-shell-thickness", 2..10, 5, scale = 10.0),
                label = R.string.health_atlas_follicle_surface_shell_thickness,
                unit = "mm",
                digits = 1,
            ),
        ),
        axis = 0,
        unit = "mm\u00b2",
        minimum = 0.0,
        maximum = 850.0,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-2-anatomy-and-physiology-of-the-ovarian-reproductive-system",
        extraSource = "https://openstax.org/books/prealgebra-2e/pages/c-geometric-formulas",
        title = R.string.health_atlas_follicle_surface_title,
        scope = R.string.health_atlas_follicle_surface_scope,
        formula = R.string.health_atlas_follicle_surface_formula,
        companionTitle = R.string.health_atlas_follicle_surface_shell_volume,
        entryIds = setOf("ovaries", "cell-granulosa-cell", "cell-theca-cell"),
        evaluate = { (diameterMm, thicknessMm) ->
            val outerRadius = outerRadiusMm(diameterMm, thicknessMm)
            4.0 * PI * outerRadius.pow(2)
        },
        companionValue = { (diameterMm, thicknessMm) ->
            val outerRadius = outerRadiusMm(diameterMm, thicknessMm)
            val cavityRadius = diameterMm / 2.0
            (4.0 * PI / 3.0) * (outerRadius.pow(3) - cavityRadius.pow(3))
        },
    )

    private fun outerRadiusMm(cavityDiameterMm: Double, shellThicknessMm: Double): Double {
        require(cavityDiameterMm.isFinite() && cavityDiameterMm > 0.0)
        require(shellThicknessMm.isFinite() && shellThicknessMm > 0.0)
        return cavityDiameterMm / 2.0 + shellThicknessMm
    }
}
