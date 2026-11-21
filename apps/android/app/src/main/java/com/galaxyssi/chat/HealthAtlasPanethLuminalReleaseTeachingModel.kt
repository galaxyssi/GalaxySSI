package com.galaxyssi.chat

import kotlin.math.roundToInt

internal object HealthAtlasPanethLuminalReleaseTeachingModel {
    private const val MAX_ICONS = 10

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("paneth-luminal-release-selected", 0..MAX_ICONS, 4),
                R.string.health_atlas_paneth_luminal_release_selected, unit = "", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("paneth-luminal-release-starting", 1..MAX_ICONS, 7),
                R.string.health_atlas_paneth_luminal_release_starting, unit = "", digits = 0,
            ),
        ),
        axis = 0,
        unit = "",
        minimum = 0.0,
        maximum = MAX_ICONS.toDouble(),
        source = "https://histology.oit.duke.edu/NormalBody/GItract/GItract_answers.html",
        extraSource = "https://histology.leeds.ac.uk/home/digestive/small_intestine/",
        title = R.string.health_atlas_paneth_luminal_release_title,
        scope = R.string.health_atlas_paneth_luminal_release_scope,
        formula = R.string.health_atlas_paneth_luminal_release_formula,
        companionTitle = R.string.health_atlas_paneth_luminal_release_companion,
        entryIds = setOf("cell-paneth-cell"),
        evaluate = ::luminalIcons,
        companionValue = { values -> values[1].roundToInt() - luminalIcons(values) },
        digits = 0,
    )

    private fun luminalIcons(values: List<Double>): Double {
        val (selected, starting) = values
        return minOf(selected.roundToInt(), starting.roundToInt()).toDouble()
    }
}
