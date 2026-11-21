package com.galaxyssi.chat

import kotlin.math.PI
import kotlin.math.pow

internal object HealthAtlasBladderExpansionTeachingModel {
    const val MAX_FINAL_VOLUME = 450.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(HealthAtlasInput("bladder-starting-volume", 50..150, 100),
                R.string.health_atlas_bladder_expansion_initial, "mL", digits = 0),
            HealthAtlasTeachingInput(HealthAtlasInput("bladder-added-volume", 0..300, 100),
                R.string.health_atlas_bladder_expansion_added, "mL", digits = 0),
        ),
        axis = 1,
        unit = "%",
        minimum = 0.0,
        maximum = 270.0,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/25-2-gross-anatomy-of-urine-transport",
        extraSource = "https://openstax.org/books/prealgebra-2e/pages/c-geometric-formulas",
        title = R.string.health_atlas_bladder_expansion_title,
        scope = R.string.health_atlas_bladder_expansion_scope,
        formula = R.string.health_atlas_bladder_expansion_formula,
        companionTitle = R.string.health_atlas_bladder_expansion_area,
        entryIds = setOf("bladder", "cell-urothelial-cell"),
        evaluate = { (start, added) -> 100.0 * ((1 + added / start).pow(2.0 / 3.0) - 1.0) },
        companionValue = { (start, added) ->
            val r = radiusCm(start + added)
            4.0 * PI * r * r
        },
    )

    fun radiusCm(volumeMl: Double) = Math.cbrt(3.0 * volumeMl / (4.0 * PI))
}
