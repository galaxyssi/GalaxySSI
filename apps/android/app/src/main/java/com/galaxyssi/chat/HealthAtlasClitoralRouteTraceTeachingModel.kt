package com.galaxyssi.chat

import kotlin.math.roundToInt

internal object HealthAtlasClitoralRouteTraceTeachingModel {
    private const val ROUTE_LINKS = 4

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("clitoral-route-trace-links", 0..ROUTE_LINKS, 1),
                R.string.health_atlas_clitoral_route_trace_links, "", digits = 0,
            ),
        ),
        axis = 0,
        unit = "%",
        minimum = 0.0,
        maximum = 100.0,
        source = "https://pmc.ncbi.nlm.nih.gov/articles/PMC11452485/",
        extraSource = "https://pmc.ncbi.nlm.nih.gov/articles/PMC4965354/",
        title = R.string.health_atlas_clitoral_route_trace_title,
        scope = R.string.health_atlas_clitoral_route_trace_scope,
        formula = R.string.health_atlas_clitoral_route_trace_formula,
        companionTitle = R.string.health_atlas_clitoral_route_trace_companion,
        entryIds = setOf("clitoris"),
        // Plot samples may fall between slider steps, but a link is counted whole.
        evaluate = { (links) -> 100.0 * links.roundToInt() / ROUTE_LINKS },
        companionValue = { (links) -> (ROUTE_LINKS - links.roundToInt()).toDouble() },
        digits = 0,
    )
}
