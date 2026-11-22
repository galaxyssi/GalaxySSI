package com.galaxyssi.chat

internal object HealthAtlasDiaphragmTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(HealthAtlasInput("diaphragm-descent", 0..30, 12),
                R.string.health_atlas_diaphragm_demo_descent, "mm", digits = 0),
            HealthAtlasTeachingInput(HealthAtlasInput("diaphragm-projected-area", 100..250, 180),
                R.string.health_atlas_diaphragm_demo_area, "cm\u00b2", digits = 0),
        ),
        axis = 0,
        unit = "mL",
        minimum = 0.0,
        maximum = 750.0,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/22-3-the-process-of-breathing",
        title = R.string.health_atlas_diaphragm_demo_title,
        scope = R.string.health_atlas_diaphragm_demo_scope,
        formula = R.string.health_atlas_diaphragm_demo_formula,
        companionTitle = R.string.health_atlas_diaphragm_demo_per_mm,
        entryIds = setOf("diaphragm"),
        evaluate = { (descent, area) -> area * descent / 10.0 },
        companionValue = { (_, area) -> area / 10.0 },
        extraSource = "https://pubmed.ncbi.nlm.nih.gov/19521009/",
    )
}
