package com.galaxyssi.chat

import kotlin.math.pow

internal object HealthAtlasAdiposeVolumeShareTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("adipose-volume-share-radius-ratio", 40..98, 90, scale = 100.0),
                R.string.health_atlas_adipose_volume_share_radius_ratio,
                "",
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("adipose-volume-share-cell-percent", 20..70, 60),
                R.string.health_atlas_adipose_volume_share_cell_percent,
                "%",
                digits = 0,
            ),
        ),
        axis = 0,
        unit = "%",
        minimum = 0.0,
        maximum = 100.0,
        source = "https://histologylab.ctl.columbia.edu/lab03/adipose-connective-tissue/",
        extraSource = "https://histology.leeds.ac.uk/home/tissue_types/connective/connective_adipocyte/",
        title = R.string.health_atlas_adipose_volume_share_title,
        scope = R.string.health_atlas_adipose_volume_share_scope,
        formula = R.string.health_atlas_adipose_volume_share_formula,
        companionTitle = R.string.health_atlas_adipose_volume_share_companion,
        entryIds = setOf("tissue-white-adipose", "cell-adipocyte"),
        // The sphere-volume constant cancels; the tissue volume budget scales the cell fraction.
        evaluate = { (radiusRatio, cellPercent) -> cellPercent * dropletFraction(radiusRatio) },
        companionValue = { (radiusRatio) -> 100.0 * dropletFraction(radiusRatio) },
    )

    private fun dropletFraction(radiusRatio: Double): Double = radiusRatio.pow(3)
}
