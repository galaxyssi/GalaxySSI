package com.galaxyssi.chat

internal object HealthAtlasCartilageOverviewPlate {
    private fun anchor(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)

    val plate = HealthAtlasPlate(
        drawable = R.drawable.health_atlas_cartilage_overview_plate,
        owner = "cartilage",
        viewLabel = R.string.health_atlas_cartilage_overview_plate_caption,
        markers = listOf(
            anchor("tissue-hyaline-cartilage", 268, 114),
            anchor("cell-chondrocyte", 235, 109)
        ),
        source = "https://pubmed.ncbi.nlm.nih.gov/24455780/",
        viewKey = "cartilage-overview",
        selectorLabel = R.string.health_atlas_cartilage_overview_plate_title,
        features = listOf(
            HealthAtlasFeature(anchor("cartilage-articular-surface", 148, 68),
                R.string.health_atlas_cartilage_overview_plate_surface,
                R.string.health_atlas_cartilage_overview_plate_surface_detail),
            HealthAtlasFeature(anchor("cartilage-chondrocytes", 115, 122),
                R.string.health_atlas_cartilage_overview_plate_chondrocytes,
                R.string.health_atlas_cartilage_overview_plate_chondrocytes_detail),
            HealthAtlasFeature(anchor("cartilage-matrix", 217, 126),
                R.string.health_atlas_cartilage_overview_plate_matrix,
                R.string.health_atlas_cartilage_overview_plate_matrix_detail),
            HealthAtlasFeature(anchor("cartilage-calcified-zone", 231, 170),
                R.string.health_atlas_cartilage_overview_plate_calcified,
                R.string.health_atlas_cartilage_overview_plate_calcified_detail),
            HealthAtlasFeature(anchor("cartilage-subchondral-bone", 152, 195),
                R.string.health_atlas_cartilage_overview_plate_bone,
                R.string.health_atlas_cartilage_overview_plate_bone_detail)
        ),
        splitCallouts = true
    )
}
