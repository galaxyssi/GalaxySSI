package com.galaxyssi.chat

internal object HealthAtlasSynovialJointPlate {
    private fun anchor(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)

    val plate = HealthAtlasPlate(
        drawable = R.drawable.health_atlas_synovial_joint_plate,
        owner = "joints",
        viewLabel = R.string.health_atlas_synovial_joint_plate_caption,
        markers = listOf(anchor("tissue-hyaline-cartilage", 131, 124)),
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/9-4-synovial-joints",
        viewKey = "synovial-joint-section",
        selectorLabel = R.string.health_atlas_synovial_joint_plate_title,
        features = listOf(
            HealthAtlasFeature(anchor("synovial-joint-capsule", 84, 121),
                R.string.health_atlas_synovial_joint_plate_capsule,
                R.string.health_atlas_synovial_joint_plate_capsule_detail),
            HealthAtlasFeature(anchor("synovial-joint-lining", 258, 157),
                R.string.health_atlas_synovial_joint_plate_lining,
                R.string.health_atlas_synovial_joint_plate_lining_detail),
            HealthAtlasFeature(anchor("synovial-joint-cavity", 179, 147),
                R.string.health_atlas_synovial_joint_plate_cavity,
                R.string.health_atlas_synovial_joint_plate_cavity_detail),
            HealthAtlasFeature(anchor("synovial-joint-articular-surfaces", 214, 153),
                R.string.health_atlas_synovial_joint_plate_surfaces,
                R.string.health_atlas_synovial_joint_plate_surfaces_detail),
            HealthAtlasFeature(anchor("synovial-joint-capsule-attachment", 117, 198),
                R.string.health_atlas_synovial_joint_plate_attachment,
                R.string.health_atlas_synovial_joint_plate_attachment_detail)
        ),
        splitCallouts = true
    )
}
