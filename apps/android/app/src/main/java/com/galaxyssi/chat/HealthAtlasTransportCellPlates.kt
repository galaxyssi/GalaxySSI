package com.galaxyssi.chat

internal object HealthAtlasTransportCellPlates {
    private const val BOOK = "https://openstax.org/books/anatomy-and-physiology-2e/pages/"
    private fun feature(id: String, x: Int, y: Int, title: Int, explanation: Int) =
        HealthAtlasFeature(HealthAtlasMarker(id, x / 360f, y / 280f), title, explanation)
    private fun plate(id: String, drawable: Int, chapter: String, vararg features: HealthAtlasFeature): HealthAtlasPlate {
        val caption = when (id) {
            "cell-collecting-duct-intercalated-cell" -> R.string.health_atlas_type_a_intercalated_view
            "cell-urothelial-cell" -> R.string.health_atlas_umbrella_view
            else -> R.string.health_atlas_cell_morphology
        }
        return HealthAtlasPlate(drawable, id, caption, emptyList(), BOOK + chapter, features = features.toList())
    }

    val all = listOf(
        plate("cell-type-i-pneumocyte", R.drawable.health_atlas_transport_pneumocyte_i, "22-1-organs-and-structures-of-the-respiratory-system",
            feature("attenuated", 90, 148, R.string.health_atlas_feature_attenuated, R.string.health_atlas_feature_attenuated_detail),
            feature("flat-nucleus", 184, 137, R.string.health_atlas_feature_flat_nucleus, R.string.health_atlas_feature_flat_nucleus_detail)),
        plate("cell-type-ii-pneumocyte", R.drawable.health_atlas_transport_pneumocyte_ii, "22-1-organs-and-structures-of-the-respiratory-system",
            feature("lamellar-body", 196, 121, R.string.health_atlas_feature_lamellar_body, R.string.health_atlas_feature_lamellar_body_detail),
            feature("at2-surface", 201, 73, R.string.health_atlas_feature_at2_surface, R.string.health_atlas_feature_at2_surface_detail)),
        plate("cell-ciliated-airway-cell", R.drawable.health_atlas_transport_ciliated_airway, "22-1-organs-and-structures-of-the-respiratory-system",
            feature("motile-cilia", 163, 66, R.string.health_atlas_feature_motile_cilia, R.string.health_atlas_feature_motile_cilia_detail),
            feature("ciliated-apical", 210, 83, R.string.health_atlas_feature_ciliated_apical, R.string.health_atlas_feature_ciliated_apical_detail)),
        plate("cell-goblet-cell", R.drawable.health_atlas_transport_goblet, "22-1-organs-and-structures-of-the-respiratory-system",
            feature("mucin-granules", 178, 105, R.string.health_atlas_feature_mucin_granules, R.string.health_atlas_feature_mucin_granules_detail),
            feature("goblet-neck", 183, 198, R.string.health_atlas_feature_goblet_neck, R.string.health_atlas_feature_goblet_neck_detail)),
        plate("cell-club-cell", R.drawable.health_atlas_transport_club, "22-1-organs-and-structures-of-the-respiratory-system",
            feature("club-dome", 179, 66, R.string.health_atlas_feature_club_dome, R.string.health_atlas_feature_club_dome_detail),
            feature("club-granules", 195, 108, R.string.health_atlas_feature_club_granules, R.string.health_atlas_feature_club_granules_detail)),
        plate("cell-podocyte", R.drawable.health_atlas_transport_podocyte, "25-4-microscopic-anatomy-of-the-kidney",
            feature("podocyte-foot", 128, 187, R.string.health_atlas_feature_podocyte_foot, R.string.health_atlas_feature_podocyte_foot_detail),
            feature("gbm", 236, 201, R.string.health_atlas_feature_gbm, R.string.health_atlas_feature_gbm_detail),
            feature("podocyte-body", 175, 94, R.string.health_atlas_feature_podocyte_body, R.string.health_atlas_feature_podocyte_body_detail)),
        plate("cell-mesangial-cell", R.drawable.health_atlas_transport_mesangial, "25-4-microscopic-anatomy-of-the-kidney",
            feature("mesangial-core", 170, 134, R.string.health_atlas_feature_mesangial_core, R.string.health_atlas_feature_mesangial_core_detail),
            feature("mesangial-support", 223, 159, R.string.health_atlas_feature_mesangial_support, R.string.health_atlas_feature_mesangial_support_detail)),
        plate("cell-proximal-tubular-cell", R.drawable.health_atlas_transport_proximal, "25-6-tubular-reabsorption",
            feature("prox-brush", 168, 57, R.string.health_atlas_feature_prox_brush, R.string.health_atlas_feature_prox_brush_detail),
            feature("prox-mito", 213, 186, R.string.health_atlas_feature_prox_mito, R.string.health_atlas_feature_prox_mito_detail)),
        plate("cell-distal-tubular-cell", R.drawable.health_atlas_transport_distal, "25-6-tubular-reabsorption",
            feature("distal-microvilli", 175, 73, R.string.health_atlas_feature_distal_microvilli, R.string.health_atlas_feature_distal_microvilli_detail),
            feature("distal-inflections", 184, 198, R.string.health_atlas_feature_distal_inflections, R.string.health_atlas_feature_distal_inflections_detail)),
        plate("cell-collecting-duct-principal-cell", R.drawable.health_atlas_transport_principal, "25-6-tubular-reabsorption",
            feature("principal-apical", 192, 76, R.string.health_atlas_feature_principal_apical, R.string.health_atlas_feature_principal_apical_detail),
            feature("principal-body", 206, 168, R.string.health_atlas_feature_principal_body, R.string.health_atlas_feature_principal_body_detail)),
        plate("cell-collecting-duct-intercalated-cell", R.drawable.health_atlas_transport_intercalated, "25-6-tubular-reabsorption",
            feature("type-a-pump", 182, 76, R.string.health_atlas_feature_type_a_pump, R.string.health_atlas_feature_type_a_pump_detail),
            feature("intercalated-mito", 216, 132, R.string.health_atlas_feature_intercalated_mito, R.string.health_atlas_feature_intercalated_mito_detail)),
        plate("cell-urothelial-cell", R.drawable.health_atlas_transport_urothelial, "25-2-gross-anatomy-of-urine-transport",
            feature("umbrella-surface", 180, 85, R.string.health_atlas_feature_umbrella_surface, R.string.health_atlas_feature_umbrella_surface_detail),
            feature("urothelial-apical", 222, 86, R.string.health_atlas_feature_urothelial_apical, R.string.health_atlas_feature_urothelial_apical_detail)),
    )
    private val byId = all.associateBy { it.owner }
    fun forId(id: String?) = byId[id]
}
