package com.galaxyssi.chat

internal object HealthAtlasNeuralRelayDelaysTeachingModel {
    private const val MAX_RELAY_COUNT = 8
    private const val MAX_DELAY_STEP = 25
    private const val DELAY_SCALE = 10.0
    private const val TIME_UNIT = "ms"

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("neural-relay-count", 1..MAX_RELAY_COUNT, 3),
                R.string.health_atlas_neural_relay_delays_count,
                unit = "",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("neural-relay-delay", 5..MAX_DELAY_STEP, 15, scale = DELAY_SCALE),
                R.string.health_atlas_neural_relay_delays_per_relay,
                unit = TIME_UNIT,
                digits = 1,
            ),
        ),
        axis = 1,
        unit = TIME_UNIT,
        minimum = 0.0,
        maximum = MAX_RELAY_COUNT * (MAX_DELAY_STEP / DELAY_SCALE),
        source = "https://openstax.org/books/biology-2e/pages/35-2-how-neurons-communicate",
        title = R.string.health_atlas_neural_relay_delays_title,
        scope = R.string.health_atlas_neural_relay_delays_scope,
        formula = R.string.health_atlas_neural_relay_delays_formula,
        companionTitle = R.string.health_atlas_neural_relay_delays_companion,
        entryIds = setOf("cerebrum", "cerebellum", "brainstem", "ganglia", "autonomic-nerves", "tissue-central-nervous"),
        evaluate = { (relayCount, delayMs) -> relayCount * delayMs },
        companionValue = { (relayCount, delayMs) -> (relayCount - 1.0) * delayMs },
        extraSource = "https://openstax.org/books/anatomy-and-physiology-2e/pages/15-1-divisions-of-the-autonomic-nervous-system",
        digits = 1,
    )
}
