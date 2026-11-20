package com.galaxyssi.chat

internal object HealthAtlasLymphOrgans {
    const val SOURCE = "https://openstax.org/books/anatomy-and-physiology-2e/pages/21-1-anatomy-of-the-lymphatic-and-immune-systems"

    data class Lesson(val plate: HealthAtlasPlate, val stageFeatures: IntArray) {
        val owner get() = requireNotNull(plate.owner)
        init { require(stageFeatures.size == 4 && stageFeatures.all { it in plate.features.indices }) }
    }

    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)
    private fun feature(id: String, x: Int, y: Int, name: Int, detail: Int) =
        HealthAtlasFeature(marker(id, x, y), name, detail)
    private fun lesson(id: String, art: Int, caption: Int, features: List<HealthAtlasFeature>,
        markers: List<HealthAtlasMarker>, stageFeatures: IntArray) =
        Lesson(HealthAtlasPlate(art, id, caption, markers, SOURCE, features = features), stageFeatures)

    private val lessons = listOf(
        lesson("bone-marrow", R.drawable.health_atlas_lymph_marrow, R.string.health_atlas_lymph_marrow_view,
            listOf(
                feature("marrow-0", 78, 80, R.string.health_atlas_lymph_marrow_feature_0, R.string.health_atlas_lymph_marrow_detail_0),
                feature("marrow-1", 151, 136, R.string.health_atlas_lymph_marrow_feature_1, R.string.health_atlas_lymph_marrow_detail_1),
                feature("marrow-2", 205, 205, R.string.health_atlas_lymph_marrow_feature_2, R.string.health_atlas_lymph_marrow_detail_2)),
            listOf(marker("cell-hematopoietic-stem-cell", 157, 105), marker("cell-megakaryocyte", 264, 158)),
            intArrayOf(1, 1, 1, 2)),
        lesson("thymus", R.drawable.health_atlas_lymph_thymus, R.string.health_atlas_lymph_thymus_view,
            listOf(
                feature("thymus-0", 95, 119, R.string.health_atlas_lymph_thymus_feature_0, R.string.health_atlas_lymph_thymus_detail_0),
                feature("thymus-1", 135, 190, R.string.health_atlas_lymph_thymus_feature_1, R.string.health_atlas_lymph_thymus_detail_1),
                feature("thymus-2", 171, 163, R.string.health_atlas_lymph_thymus_feature_2, R.string.health_atlas_lymph_thymus_detail_2),
                feature("thymus-3", 225, 156, R.string.health_atlas_lymph_thymus_feature_3, R.string.health_atlas_lymph_thymus_detail_3)),
            listOf(marker("cell-t-cell", 189, 138)),
            intArrayOf(1, 0, 2, 1)),
        lesson("spleen", R.drawable.health_atlas_lymph_spleen, R.string.health_atlas_lymph_spleen_view,
            listOf(
                feature("spleen-0", 228, 150, R.string.health_atlas_lymph_spleen_feature_0, R.string.health_atlas_lymph_spleen_detail_0),
                feature("spleen-1", 175, 104, R.string.health_atlas_lymph_spleen_feature_1, R.string.health_atlas_lymph_spleen_detail_1),
                feature("spleen-2", 105, 168, R.string.health_atlas_lymph_spleen_feature_2, R.string.health_atlas_lymph_spleen_detail_2)),
            listOf(marker("cell-macrophage", 124, 198), marker("cell-b-cell", 151, 113)),
            intArrayOf(0, 1, 2, 0)),
        lesson("lymph-nodes", R.drawable.health_atlas_lymph_node, R.string.health_atlas_lymph_node_view,
            listOf(
                feature("node-0", 94, 51, R.string.health_atlas_lymph_node_feature_0, R.string.health_atlas_lymph_node_detail_0),
                feature("node-1", 100, 103, R.string.health_atlas_lymph_node_feature_1, R.string.health_atlas_lymph_node_detail_1),
                feature("node-2", 200, 183, R.string.health_atlas_lymph_node_feature_2, R.string.health_atlas_lymph_node_detail_2),
                feature("node-3", 299, 184, R.string.health_atlas_lymph_node_feature_3, R.string.health_atlas_lymph_node_detail_3),
                feature("node-4", 145, 122, R.string.health_atlas_lymph_node_feature_4, R.string.health_atlas_lymph_node_detail_4)),
            listOf(marker("cell-b-cell", 181, 114)),
            intArrayOf(0, 1, 2, 3)),
        lesson("lymphatic-vessels", R.drawable.health_atlas_lymph_vessel, R.string.health_atlas_lymph_vessel_view,
            listOf(
                feature("vessel-0", 105, 130, R.string.health_atlas_lymph_vessel_feature_0, R.string.health_atlas_lymph_vessel_detail_0),
                feature("vessel-1", 191, 104, R.string.health_atlas_lymph_vessel_feature_1, R.string.health_atlas_lymph_vessel_detail_1),
                feature("vessel-2", 260, 145, R.string.health_atlas_lymph_vessel_feature_2, R.string.health_atlas_lymph_vessel_detail_2)),
            listOf(marker("cell-lymphatic-endothelial-cell", 170, 119)),
            intArrayOf(0, 1, 2, 2)),
        lesson("thoracic-duct", R.drawable.health_atlas_lymph_duct, R.string.health_atlas_lymph_duct_view,
            listOf(
                feature("duct-0", 163, 224, R.string.health_atlas_lymph_duct_feature_0, R.string.health_atlas_lymph_duct_detail_0),
                feature("duct-1", 180, 139, R.string.health_atlas_lymph_duct_feature_1, R.string.health_atlas_lymph_duct_detail_1),
                feature("duct-2", 231, 61, R.string.health_atlas_lymph_duct_feature_2, R.string.health_atlas_lymph_duct_detail_2)),
            listOf(marker("lymphatic-vessels", 161, 184)),
            intArrayOf(0, 1, 1, 2)),
        lesson("tonsils", R.drawable.health_atlas_lymph_tonsil, R.string.health_atlas_lymph_tonsil_view,
            listOf(
                feature("tonsil-0", 176, 75, R.string.health_atlas_lymph_tonsil_feature_0, R.string.health_atlas_lymph_tonsil_detail_0),
                feature("tonsil-1", 149, 153, R.string.health_atlas_lymph_tonsil_feature_1, R.string.health_atlas_lymph_tonsil_detail_1),
                feature("tonsil-2", 240, 139, R.string.health_atlas_lymph_tonsil_feature_2, R.string.health_atlas_lymph_tonsil_detail_2)),
            listOf(marker("cell-b-cell", 106, 121)),
            intArrayOf(0, 1, 1, 2)),
        lesson("adenoids", R.drawable.health_atlas_lymph_adenoid, R.string.health_atlas_lymph_adenoid_view,
            listOf(
                feature("adenoid-0", 216, 77, R.string.health_atlas_lymph_adenoid_feature_0, R.string.health_atlas_lymph_adenoid_detail_0),
                feature("adenoid-1", 237, 128, R.string.health_atlas_lymph_adenoid_feature_1, R.string.health_atlas_lymph_adenoid_detail_1),
                feature("adenoid-2", 266, 105, R.string.health_atlas_lymph_adenoid_feature_2, R.string.health_atlas_lymph_adenoid_detail_2)),
            listOf(marker("cell-dendritic-cell", 279, 120)),
            intArrayOf(0, 1, 2, 2)),
        lesson("gut-associated-lymphoid-tissue", R.drawable.health_atlas_lymph_galt, R.string.health_atlas_lymph_galt_view,
            listOf(
                feature("galt-0", 178, 83, R.string.health_atlas_lymph_galt_feature_0, R.string.health_atlas_lymph_galt_detail_0),
                feature("galt-1", 169, 122, R.string.health_atlas_lymph_galt_feature_1, R.string.health_atlas_lymph_galt_detail_1),
                feature("galt-2", 189, 184, R.string.health_atlas_lymph_galt_feature_2, R.string.health_atlas_lymph_galt_detail_2)),
            listOf(marker("cell-dendritic-cell", 195, 132), marker("cell-b-cell", 211, 177)),
            intArrayOf(0, 0, 1, 2))
    ).associateBy(Lesson::owner)
    val all = lessons.values.map(Lesson::plate)
    operator fun get(id: String?) = lessons[id]
}
