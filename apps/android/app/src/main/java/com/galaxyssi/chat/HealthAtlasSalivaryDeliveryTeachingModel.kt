package com.galaxyssi.chat

internal object HealthAtlasSalivaryDeliveryTeachingModel {
    private const val FLOW_UNIT = "DU/min"
    private const val STEPS_PER_FLOW_UNIT = 4.0
    private const val COLLECTION_MINUTES = 5.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("salivary-parotid-flow", 0..24, 12, STEPS_PER_FLOW_UNIT),
                R.string.health_atlas_salivary_delivery_parotid, FLOW_UNIT,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("salivary-submandibular-flow", 0..24, 16, STEPS_PER_FLOW_UNIT),
                R.string.health_atlas_salivary_delivery_submandibular, FLOW_UNIT,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("salivary-sublingual-flow", 0..12, 4, STEPS_PER_FLOW_UNIT),
                R.string.health_atlas_salivary_delivery_sublingual, FLOW_UNIT,
            ),
        ),
        axis = 0,
        unit = FLOW_UNIT,
        minimum = 0.0,
        maximum = 15.0,
        source = "https://www.nidcr.nih.gov/health-info/saliva-salivary-gland-disorders",
        title = R.string.health_atlas_salivary_delivery_title,
        scope = R.string.health_atlas_salivary_delivery_scope,
        formula = R.string.health_atlas_salivary_delivery_formula,
        companionTitle = R.string.health_atlas_salivary_delivery_companion,
        entryIds = setOf(
            "salivary-glands",
            "parotid-glands",
            "submandibular-glands",
            "sublingual-glands",
            "cell-salivary-acinar-cell",
        ),
        evaluate = ::totalFlow,
        companionValue = { totalFlow(it) * COLLECTION_MINUTES },
        extraSource = "https://pubmed.ncbi.nlm.nih.gov/25680367/",
    )

    private fun totalFlow(contributions: List<Double>): Double = contributions.sum()
}
