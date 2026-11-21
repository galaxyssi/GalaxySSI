package com.galaxyssi.chat

import kotlin.math.roundToInt

internal object HealthAtlasPlateletFragmentCountTeachingModel {
    private const val MAX_ICONS = 8
    private const val MAX_TILES_PER_ICON = 6

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("platelet-fragment-count-icons", 0..MAX_ICONS, 4),
                label = R.string.health_atlas_platelet_fragment_count_icons,
                unit = "",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("platelet-fragment-count-tiles-per-icon", 0..MAX_TILES_PER_ICON, 3),
                label = R.string.health_atlas_platelet_fragment_count_tiles_per_icon,
                unit = "",
                digits = 0,
            ),
        ),
        axis = 0,
        unit = "",
        minimum = 0.0,
        maximum = (MAX_ICONS * MAX_TILES_PER_ICON).toDouble(),
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/18-4-leukocytes-and-platelets",
        extraSource = "https://training.seer.cancer.gov/hematopoietic1/intro-to-blood.html",
        title = R.string.health_atlas_platelet_fragment_count_title,
        scope = R.string.health_atlas_platelet_fragment_count_scope,
        formula = R.string.health_atlas_platelet_fragment_count_formula,
        companionTitle = R.string.health_atlas_platelet_fragment_count_companion,
        entryIds = setOf("fragment-platelet", "cell-megakaryocyte"),
        // The shared chart also samples between integer icon counts.
        evaluate = { (icons, tilesPerIcon) -> (icons.roundToInt() * tilesPerIcon.roundToInt()).toDouble() },
        companionValue = { (_, tilesPerIcon) -> tilesPerIcon.roundToInt().toDouble() },
        digits = 0,
    )
}
