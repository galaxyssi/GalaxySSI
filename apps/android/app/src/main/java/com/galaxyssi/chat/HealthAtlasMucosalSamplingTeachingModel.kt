package com.galaxyssi.chat

internal object HealthAtlasMucosalSamplingTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("mucosal-sampling-selected-tiles", 1..12, 3),
                label = R.string.health_atlas_mucosal_sampling_selected_tiles,
                unit = "",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("mucosal-sampling-unselected-tiles", 1..12, 9),
                label = R.string.health_atlas_mucosal_sampling_unselected_tiles,
                unit = "",
                digits = 0,
            ),
        ),
        axis = 0,
        unit = "%",
        minimum = 0.0,
        maximum = 100.0,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/21-1-anatomy-of-the-lymphatic-and-immune-systems",
        extraSource = "https://histology.leeds.ac.uk/home/lymphoid/prim_sec_lymp_tiss/",
        title = R.string.health_atlas_mucosal_sampling_title,
        scope = R.string.health_atlas_mucosal_sampling_scope,
        formula = R.string.health_atlas_mucosal_sampling_formula,
        companionTitle = R.string.health_atlas_mucosal_sampling_companion,
        entryIds = setOf("tonsils", "adenoids", "appendix", "gut-associated-lymphoid-tissue"),
        evaluate = { (selected, unselected) -> 100.0 * selected / (selected + unselected) },
        companionValue = { (selected, unselected) -> 100.0 * unselected / (selected + unselected) },
    )
}
