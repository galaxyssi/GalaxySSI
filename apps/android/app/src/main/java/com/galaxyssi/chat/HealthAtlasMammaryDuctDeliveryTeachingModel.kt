package com.galaxyssi.chat

internal object HealthAtlasMammaryDuctDeliveryTeachingModel {
    private const val VOLUME_UNIT = "VU"
    private const val MAX_SECRETED_VOLUME = 12
    private const val WHOLE_PERCENT = 100

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("mammary-duct-secreted-volume", 4..MAX_SECRETED_VOLUME, 8),
                R.string.health_atlas_mammary_duct_delivery_secreted_volume,
                VOLUME_UNIT,
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("mammary-duct-displaced-share", 0..WHOLE_PERCENT, 60),
                R.string.health_atlas_mammary_duct_delivery_displaced_share,
                "%",
                digits = 0,
            ),
        ),
        axis = 1,
        unit = VOLUME_UNIT,
        minimum = 0.0,
        maximum = MAX_SECRETED_VOLUME.toDouble(),
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/28-6-lactation",
        title = R.string.health_atlas_mammary_duct_delivery_title,
        scope = R.string.health_atlas_mammary_duct_delivery_scope,
        formula = R.string.health_atlas_mammary_duct_delivery_formula,
        companionTitle = R.string.health_atlas_mammary_duct_delivery_companion,
        entryIds = setOf("mammary-glands", "cell-mammary-luminal-cell", "cell-myoepithelial-cell"),
        evaluate = ::deliveredVolume,
        companionValue = { values -> values[0] - deliveredVolume(values) },
        extraSource = "https://pmc.ncbi.nlm.nih.gov/articles/PMC3098485/",
    )

    private fun deliveredVolume(values: List<Double>): Double {
        val (secretedVolume, displacedPercent) = values
        return secretedVolume * (displacedPercent / WHOLE_PERCENT)
    }
}
