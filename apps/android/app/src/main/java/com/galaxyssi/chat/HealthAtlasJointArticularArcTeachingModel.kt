package com.galaxyssi.chat

internal object HealthAtlasJointArticularArcTeachingModel {
    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("joint-articular-arc-angle", 0..90, 45),
                label = R.string.health_atlas_joint_articular_arc_angle,
                unit = "\u00b0",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("joint-articular-arc-radius", 10..40, 25),
                label = R.string.health_atlas_joint_articular_arc_radius,
                unit = "mm",
                digits = 0,
            ),
        ),
        axis = 0,
        unit = "mm",
        minimum = 0.0,
        maximum = 65.0,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/9-6-anatomy-of-selected-synovial-joints",
        title = R.string.health_atlas_joint_articular_arc_title,
        scope = R.string.health_atlas_joint_articular_arc_scope,
        formula = R.string.health_atlas_joint_articular_arc_formula,
        companionTitle = R.string.health_atlas_joint_articular_arc_companion,
        entryIds = setOf("joints", "scapula"),
        evaluate = { (angleDegrees, radiusMm) -> radiusMm * Math.toRadians(angleDegrees) },
        companionValue = { (angleDegrees, _) -> Math.toRadians(angleDegrees) },
        extraSource = "https://openstax.org/books/precalculus-2e/pages/5-1-angles",
    )
}
