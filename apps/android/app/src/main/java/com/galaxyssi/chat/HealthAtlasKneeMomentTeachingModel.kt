package com.galaxyssi.chat

internal object HealthAtlasKneeMomentTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("knee-moment-force", 0..20, 10),
                R.string.health_atlas_knee_moment_force, "N", digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("knee-moment-arm", 0..6, 4),
                R.string.health_atlas_knee_moment_arm, "cm", digits = 0,
            ),
        ),
        axis = 0,
        unit = "N\u00b7m",
        minimum = 0.0,
        maximum = 1.25,
        source = "https://pubmed.ncbi.nlm.nih.gov/26520912/",
        title = R.string.health_atlas_knee_moment_title,
        scope = R.string.health_atlas_knee_moment_scope,
        formula = R.string.health_atlas_knee_moment_formula,
        companionTitle = R.string.health_atlas_knee_moment_arm_meters,
        entryIds = setOf("patella", "quadriceps-femoris"),
        evaluate = { (force, armCm) -> force * armMeters(armCm) },
        companionValue = { (_, armCm) -> armMeters(armCm) },
    )

    private fun armMeters(armCm: Double) = armCm / 100.0
}
