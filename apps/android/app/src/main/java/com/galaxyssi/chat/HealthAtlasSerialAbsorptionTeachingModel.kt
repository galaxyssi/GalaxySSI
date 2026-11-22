package com.galaxyssi.chat

internal object HealthAtlasSerialAbsorptionTeachingModel {
    private const val WHOLE_PERCENT = 100.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("serial-absorption-stage-a", 0..100, 40),
                R.string.health_atlas_serial_absorption_stage_a,
                "%",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("serial-absorption-stage-b", 0..100, 50),
                R.string.health_atlas_serial_absorption_stage_b,
                "%",
                digits = 0,
            ),
        ),
        axis = 1,
        unit = "%",
        minimum = 0.0,
        maximum = WHOLE_PERCENT,
        source = "https://www.niddk.nih.gov/health-information/digestive-diseases/digestive-system-how-it-works",
        title = R.string.health_atlas_serial_absorption_title,
        scope = R.string.health_atlas_serial_absorption_scope,
        formula = R.string.health_atlas_serial_absorption_formula,
        companionTitle = R.string.health_atlas_serial_absorption_companion,
        entryIds = setOf("gut", "digestive", "duodenum", "ileum", "cell-enterocyte"),
        evaluate = { WHOLE_PERCENT - remainingPercent(it) },
        companionValue = ::remainingPercent,
        extraSource = "https://pmc.ncbi.nlm.nih.gov/articles/PMC1413011/",
    )

    private fun remainingPercent(values: List<Double>): Double {
        val (aPercent, bPercent) = values
        val enteringB = WHOLE_PERCENT - aPercent
        val fractionLeavingB = (WHOLE_PERCENT - bPercent) / WHOLE_PERCENT
        return enteringB * fractionLeavingB
    }
}
