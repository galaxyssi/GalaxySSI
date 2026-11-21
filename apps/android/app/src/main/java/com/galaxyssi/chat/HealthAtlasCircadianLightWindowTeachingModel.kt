package com.galaxyssi.chat

internal object HealthAtlasCircadianLightWindowTeachingModel {
    private const val DEGREES_PER_CYCLE = 360.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("circadian-light-window-period", 12..30, 24),
                label = R.string.health_atlas_circadian_light_window_period,
                unit = "h",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("circadian-light-window-elapsed", 0..48, 30),
                label = R.string.health_atlas_circadian_light_window_elapsed,
                unit = "h",
                digits = 0,
            ),
        ),
        axis = 1,
        unit = "\u00b0",
        minimum = 0.0,
        maximum = 1440.0,
        source = "https://nigms.nih.gov/education/fact-sheets/Pages/circadian-rhythms",
        title = R.string.health_atlas_circadian_light_window_title,
        scope = R.string.health_atlas_circadian_light_window_scope,
        formula = R.string.health_atlas_circadian_light_window_formula,
        companionTitle = R.string.health_atlas_circadian_light_window_companion,
        entryIds = setOf("hypothalamus", "pineal-gland", "cell-pinealocyte"),
        evaluate = { (periodHours, elapsedHours) -> elapsedPhase(periodHours, elapsedHours) },
        companionValue = { (periodHours, elapsedHours) -> elapsedPhase(periodHours, elapsedHours) % DEGREES_PER_CYCLE },
        extraSource = "https://pmc.ncbi.nlm.nih.gov/articles/PMC2658055/",
    )

    private fun elapsedPhase(periodHours: Double, elapsedHours: Double): Double =
        DEGREES_PER_CYCLE * elapsedHours / periodHours
}
