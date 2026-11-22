package com.galaxyssi.chat

import kotlin.math.roundToInt

internal object HealthAtlasAccessoryGlandEntryTeachingModel {
    private const val MARKERS_PER_ROUTE = 4

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("accessory-gland-entry-vesicle-markers", 0..MARKERS_PER_ROUTE, 3),
                R.string.health_atlas_accessory_gland_entry_vesicles, unit = "", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("accessory-gland-entry-prostate-markers", 0..MARKERS_PER_ROUTE, 2),
                R.string.health_atlas_accessory_gland_entry_prostate, unit = "", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("accessory-gland-entry-bulbourethral-markers", 0..MARKERS_PER_ROUTE, 1),
                R.string.health_atlas_accessory_gland_entry_bulbourethral, unit = "", digits = 0,
            ),
        ),
        axis = 0,
        unit = "",
        minimum = 0.0,
        maximum = 2.0 * MARKERS_PER_ROUTE,
        source = "https://training.seer.cancer.gov/anatomy/reproductive/male/duct.html",
        extraSource = "https://training.seer.cancer.gov/anatomy/reproductive/male/glands.html",
        title = R.string.health_atlas_accessory_gland_entry_title,
        scope = R.string.health_atlas_accessory_gland_entry_scope,
        formula = R.string.health_atlas_accessory_gland_entry_formula,
        companionTitle = R.string.health_atlas_accessory_gland_entry_companion,
        entryIds = setOf("seminal-vesicles", "prostate", "bulbourethral-glands"),
        // Chart samples between slider steps still represent whole diagram markers.
        evaluate = { (vesicles, prostate) -> (vesicles.roundToInt() + prostate.roundToInt()).toDouble() },
        companionValue = { (_, _, bulbourethral) -> bulbourethral.roundToInt().toDouble() },
        digits = 0,
    )
}
