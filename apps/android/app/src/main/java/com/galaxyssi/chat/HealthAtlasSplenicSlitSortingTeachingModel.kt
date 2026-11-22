package com.galaxyssi.chat

internal object HealthAtlasSplenicSlitSortingTeachingModel {
    private val requiredWidths = listOf(1, 2, 2, 3, 3, 3, 4, 4, 5, 6, 7, 8)

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("splenic-slit-sorting-width", 0..16, 6, scale = 2.0),
                R.string.health_atlas_splenic_slit_sorting_width,
                "u",
                digits = 1,
            ),
        ),
        axis = 0,
        unit = "",
        minimum = 0.0,
        maximum = requiredWidths.size.toDouble(),
        source = "https://pmc.ncbi.nlm.nih.gov/articles/PMC9526706/",
        extraSource = "https://pmc.ncbi.nlm.nih.gov/articles/PMC6199658/",
        title = R.string.health_atlas_splenic_slit_sorting_title,
        scope = R.string.health_atlas_splenic_slit_sorting_scope,
        formula = R.string.health_atlas_splenic_slit_sorting_formula,
        companionTitle = R.string.health_atlas_splenic_slit_sorting_companion,
        entryIds = setOf("spleen"),
        evaluate = ::passedCount,
        companionValue = { values -> requiredWidths.size - passedCount(values) },
        digits = 0,
    )

    private fun passedCount(values: List<Double>): Double {
        val (slitWidth) = values
        return requiredWidths.count { it <= slitWidth }.toDouble()
    }
}
