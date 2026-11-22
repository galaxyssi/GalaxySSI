package com.galaxyssi.chat

import kotlin.math.roundToInt

internal object HealthAtlasMicrogliaSurveillanceTeachingModel {
    private const val PATCH_TILES = 12
    private const val MAX_TILES_PER_SNAPSHOT = PATCH_TILES / 2

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("microglia-surveillance-width", 0..MAX_TILES_PER_SNAPSHOT, 4),
                R.string.health_atlas_microglia_surveillance_width, unit = "", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("microglia-surveillance-offset", 0..MAX_TILES_PER_SNAPSHOT, 2),
                R.string.health_atlas_microglia_surveillance_offset, unit = "", digits = 0,
            ),
        ),
        axis = 1,
        unit = "",
        minimum = 0.0,
        maximum = PATCH_TILES.toDouble(),
        source = "https://pubmed.ncbi.nlm.nih.gov/15831717/",
        title = R.string.health_atlas_microglia_surveillance_title,
        scope = R.string.health_atlas_microglia_surveillance_scope,
        formula = R.string.health_atlas_microglia_surveillance_formula,
        companionTitle = R.string.health_atlas_microglia_surveillance_companion,
        entryIds = setOf("cell-microglia"),
        evaluate = { values -> 2 * values[0].roundToInt() - overlap(values) },
        companionValue = ::overlap,
        digits = 0,
    )

    private fun overlap(values: List<Double>): Double {
        val (width, offset) = values
        // Chart samples can land between slider steps, but the patch uses whole tiles.
        return (width.roundToInt() - offset.roundToInt()).coerceAtLeast(0).toDouble()
    }
}
