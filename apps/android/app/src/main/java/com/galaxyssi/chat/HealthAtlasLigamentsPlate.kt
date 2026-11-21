package com.galaxyssi.chat

internal object HealthAtlasLigamentsPlate {
    const val ANATOMY_SOURCE = "https://openstax.org/books/anatomy-and-physiology-2e/pages/9-6-anatomy-of-selected-synovial-joints"
    const val ACL_FOOTPRINT_SOURCE = "https://pubmed.ncbi.nlm.nih.gov/23717777/"
    const val PCL_FOOTPRINT_SOURCE = "https://pubmed.ncbi.nlm.nih.gov/32556668/"
    const val MOTION_SOURCE = "https://pubmed.ncbi.nlm.nih.gov/30972464/"

    private fun anchor(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)

    val aclFemur = anchor("ligaments-acl-femoral-footprint", 162, 104)
    val aclTibia = anchor("ligaments-acl-tibial-footprint", 191, 185)
    val pclFemur = anchor("ligaments-pcl-femoral-footprint", 207, 108)
    val pclTibia = anchor("ligaments-pcl-tibial-footprint", 163, 155)
    val tibia = anchor("tibia", 232, 212)

    val plate = HealthAtlasPlate(
        drawable = R.drawable.health_atlas_ligaments_plate,
        owner = "ligaments",
        viewLabel = R.string.health_atlas_ligaments_plate_caption,
        markers = listOf(tibia),
        source = ANATOMY_SOURCE,
        viewKey = "ligaments-knee-cruciates",
        selectorLabel = R.string.health_atlas_ligaments_plate_title,
        features = listOf(
            HealthAtlasFeature(aclFemur, R.string.health_atlas_ligaments_plate_acl_femur,
                R.string.health_atlas_ligaments_plate_acl_femur_detail),
            HealthAtlasFeature(aclTibia, R.string.health_atlas_ligaments_plate_acl_tibia,
                R.string.health_atlas_ligaments_plate_acl_tibia_detail),
            HealthAtlasFeature(pclFemur, R.string.health_atlas_ligaments_plate_pcl_femur,
                R.string.health_atlas_ligaments_plate_pcl_femur_detail),
            HealthAtlasFeature(pclTibia, R.string.health_atlas_ligaments_plate_pcl_tibia,
                R.string.health_atlas_ligaments_plate_pcl_tibia_detail),
        ),
        splitCallouts = true,
    )
}
