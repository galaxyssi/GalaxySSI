package com.galaxyssi.chat

internal object HealthAtlasEnteroendocrinePolarityTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("enteroendocrine-polarity-basal-offset", 5..25, 15, scale = 10.0),
                R.string.health_atlas_enteroendocrine_polarity_basal_offset, "u", digits = 1,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("enteroendocrine-polarity-cell-height", 60..120, 80, scale = 10.0),
                R.string.health_atlas_enteroendocrine_polarity_cell_height, "u", digits = 1,
            ),
        ),
        axis = 0,
        unit = "%",
        minimum = 0.0,
        maximum = 50.0,
        source = "https://www.jstage.jst.go.jp/article/aohc1950/31/3-4/31_3-4_477/_article/-char/en",
        extraSource = "https://open.umich.edu/sites/default/files/downloads/01.07.09-hist-velkey-esophstom.pdf",
        title = R.string.health_atlas_enteroendocrine_polarity_title,
        scope = R.string.health_atlas_enteroendocrine_polarity_scope,
        formula = R.string.health_atlas_enteroendocrine_polarity_formula,
        companionTitle = R.string.health_atlas_enteroendocrine_polarity_companion,
        entryIds = setOf("cell-enteroendocrine-cell"),
        evaluate = { (offset, height) -> 100.0 * offset / height },
        companionValue = { (offset, height) -> height - offset },
    )
}
