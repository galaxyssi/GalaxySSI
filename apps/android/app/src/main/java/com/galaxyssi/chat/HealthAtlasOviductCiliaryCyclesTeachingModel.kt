package com.galaxyssi.chat

internal object HealthAtlasOviductCiliaryCyclesTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("oviduct-ciliary-cycles-rate", 4..10, 5),
                label = R.string.health_atlas_oviduct_ciliary_cycles_rate,
                unit = "Hz",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("oviduct-ciliary-cycles-time", 0..20, 15, scale = 10.0),
                label = R.string.health_atlas_oviduct_ciliary_cycles_time,
                unit = "s",
                digits = 1,
            ),
        ),
        axis = 1,
        unit = "cycles",
        minimum = 0.0,
        maximum = 20.0,
        source = "https://pubmed.ncbi.nlm.nih.gov/11870107/",
        title = R.string.health_atlas_oviduct_ciliary_cycles_title,
        scope = R.string.health_atlas_oviduct_ciliary_cycles_scope,
        formula = R.string.health_atlas_oviduct_ciliary_cycles_formula,
        companionTitle = R.string.health_atlas_oviduct_ciliary_cycles_companion,
        entryIds = setOf("female", "uterine-tubes", "cell-ciliated-oviduct-cell"),
        evaluate = { (rateHz, timeSeconds) -> rateHz * timeSeconds },
        companionValue = { (rateHz) ->
            require(rateHz.isFinite() && rateHz > 0.0)
            1000.0 / rateHz
        },
        extraSource = "https://www.nature.com/articles/s41467-024-55440-2",
    )
}
