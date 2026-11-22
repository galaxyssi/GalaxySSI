package com.galaxyssi.chat

internal object HealthAtlasBiliaryFlowTallyTeachingModel {
    private const val FLOW_UNIT = "VU/min"
    private const val STEPS_PER_FLOW_UNIT = 4.0
    private const val MAX_FLOW_STEP = 24
    private const val MAX_CHANNELS = 8
    private const val DEMO_MINUTES = 4.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("biliary-flow-tally-per-channel", 0..MAX_FLOW_STEP, 10, STEPS_PER_FLOW_UNIT),
                R.string.health_atlas_biliary_flow_tally_per_channel,
                FLOW_UNIT,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("biliary-flow-tally-channel-count", 1..MAX_CHANNELS, 4),
                R.string.health_atlas_biliary_flow_tally_channel_count,
                unit = "",
                digits = 0,
            ),
        ),
        axis = 0,
        unit = FLOW_UNIT,
        minimum = 0.0,
        maximum = MAX_CHANNELS * (MAX_FLOW_STEP / STEPS_PER_FLOW_UNIT),
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-6-accessory-organs-in-digestion-the-liver-pancreas-and-gallbladder",
        title = R.string.health_atlas_biliary_flow_tally_title,
        scope = R.string.health_atlas_biliary_flow_tally_scope,
        formula = R.string.health_atlas_biliary_flow_tally_formula,
        companionTitle = R.string.health_atlas_biliary_flow_tally_companion,
        entryIds = setOf("liver", "biliary-tract", "cell-hepatocyte", "cell-cholangiocyte"),
        evaluate = ::combinedInflow,
        companionValue = { combinedInflow(it) * DEMO_MINUTES },
        extraSource = "https://pubmed.ncbi.nlm.nih.gov/9096607/",
    )

    private fun combinedInflow(values: List<Double>): Double {
        val (perChannel, channelCount) = values
        return perChannel * channelCount
    }
}
