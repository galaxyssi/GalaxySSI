package com.galaxyssi.chat

import kotlin.math.PI

internal object HealthAtlasUrethralOpeningAreaTeachingModel {
    private const val MAX_WIDTH_TENTHS = 80
    private const val WIDTH_SCALE = 10.0
    private const val WHOLE_PERCENT = 100

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("urethral-opening-area-width", 20..MAX_WIDTH_TENTHS, 60, scale = WIDTH_SCALE),
                R.string.health_atlas_urethral_opening_area_width,
                "u",
                digits = 1,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("urethral-opening-area-height-percent", 0..WHOLE_PERCENT, 50),
                R.string.health_atlas_urethral_opening_area_height_percent,
                "%",
                digits = 0,
            ),
        ),
        axis = 1,
        unit = "u\u00b2",
        minimum = 0.0,
        maximum = ellipseArea(MAX_WIDTH_TENTHS / WIDTH_SCALE, MAX_WIDTH_TENTHS / WIDTH_SCALE),
        source = "https://www.niddk.nih.gov/health-information/urologic-diseases/urinary-tract-how-it-works",
        title = R.string.health_atlas_urethral_opening_area_title,
        scope = R.string.health_atlas_urethral_opening_area_scope,
        formula = R.string.health_atlas_urethral_opening_area_formula,
        companionTitle = R.string.health_atlas_urethral_opening_area_companion,
        entryIds = setOf("urethra"),
        evaluate = { values -> ellipseArea(values[0], openingHeight(values)) },
        companionValue = ::openingHeight,
    )

    private fun openingHeight(values: List<Double>): Double {
        val (width, heightPercent) = values
        return width * (heightPercent / WHOLE_PERCENT)
    }

    private fun ellipseArea(width: Double, height: Double): Double = PI * (width / 2.0) * (height / 2.0)
}
