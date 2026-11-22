package com.galaxyssi.chat

import kotlin.math.exp
import kotlin.math.expm1

internal object HealthAtlasCapillaryExchangeTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(HealthAtlasInput("capillary-exchange-ps", 0..40, 20),
                R.string.health_atlas_capillary_exchange_ps, "mL/min"),
            HealthAtlasTeachingInput(HealthAtlasInput("capillary-exchange-flow", 5..80, 20),
                R.string.health_atlas_capillary_exchange_flow, "mL/min"),
        ),
        axis = 0,
        unit = "%",
        minimum = 0.0,
        maximum = 100.0,
        source = "https://pubmed.ncbi.nlm.nih.gov/14078649/",
        title = R.string.health_atlas_capillary_exchange_title,
        scope = R.string.health_atlas_capillary_exchange_scope,
        formula = R.string.health_atlas_capillary_exchange_formula,
        companionTitle = R.string.health_atlas_capillary_exchange_remaining,
        entryIds = setOf("capillaries", "tissue-vascular-endothelium", "cell-vascular-endothelial-cell"),
        evaluate = { (capacity, flow) -> -100.0 * expm1(-capacity / flow) },
        companionValue = { (capacity, flow) -> 100.0 * exp(-capacity / flow) },
    )
}
