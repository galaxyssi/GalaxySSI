package com.galaxyssi.chat

internal object HealthAtlasPenilePathTraceTeachingModel {
    private const val DRAWN_LENGTH = 10.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("penile-path-trace-position", 0..100, 40),
                R.string.health_atlas_penile_path_trace_position, unit = "%", digits = 0,
            ),
        ),
        axis = 0,
        unit = "u",
        minimum = 0.0,
        maximum = DRAWN_LENGTH,
        source = "https://training.seer.cancer.gov/anatomy/reproductive/male/penis.html",
        extraSource = "https://anatomy.ttuhscep.edu/reproductive_system/perineum_tables.html",
        title = R.string.health_atlas_penile_path_trace_title,
        scope = R.string.health_atlas_penile_path_trace_scope,
        formula = R.string.health_atlas_penile_path_trace_formula,
        companionTitle = R.string.health_atlas_penile_path_trace_companion,
        entryIds = setOf("penis"),
        evaluate = { (position) -> tracedDistance(position) },
        companionValue = { (position) -> DRAWN_LENGTH - tracedDistance(position) },
        digits = 1,
    )

    private fun tracedDistance(position: Double): Double = DRAWN_LENGTH * position / 100.0
}
