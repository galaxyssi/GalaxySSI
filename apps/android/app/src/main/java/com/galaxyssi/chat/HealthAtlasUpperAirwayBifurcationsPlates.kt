package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

internal object HealthAtlasUpperAirwayBifurcationsPlates {
    private const val RESPIRATORY_ANATOMY =
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/22-1-organs-and-structures-of-the-respiratory-system"
    private const val MAIN_BRONCHI_ANATOMY = "https://pmc.ncbi.nlm.nih.gov/articles/PMC4404098/"

    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(HealthAtlasMarker(id, x / 360f, y / 280f), title, detail)

    val larynx = HealthAtlasPlate(
        drawable = R.drawable.health_atlas_larynx_inlet_cutaway,
        owner = "larynx",
        viewLabel = string.health_atlas_larynx_inlet_plate_caption,
        markers = emptyList(),
        source = RESPIRATORY_ANATOMY,
        viewKey = "larynx-inlet-cutaway",
        selectorLabel = string.health_atlas_larynx_inlet_plate_selector,
        features = listOf(
            feature("larynx-inlet-epiglottis", 152, 64, string.health_atlas_larynx_inlet_plate_epiglottis,
                string.health_atlas_larynx_inlet_plate_epiglottis_detail),
            feature("larynx-inlet-vestibular-folds", 227, 130, string.health_atlas_larynx_inlet_plate_vestibular_folds,
                string.health_atlas_larynx_inlet_plate_vestibular_folds_detail),
            feature("larynx-inlet-vocal-folds", 145, 153, string.health_atlas_larynx_inlet_plate_vocal_folds,
                string.health_atlas_larynx_inlet_plate_vocal_folds_detail),
            feature("larynx-inlet-glottic-opening", 191, 174, string.health_atlas_larynx_inlet_plate_glottic_opening,
                string.health_atlas_larynx_inlet_plate_glottic_opening_detail),
        ),
        splitCallouts = true,
    )

    val trachea = HealthAtlasPlate(
        drawable = R.drawable.health_atlas_trachea_ring_cutaway,
        owner = "trachea",
        viewLabel = string.health_atlas_trachea_ring_plate_caption,
        markers = emptyList(),
        source = RESPIRATORY_ANATOMY,
        viewKey = "trachea-ring-cutaway",
        selectorLabel = string.health_atlas_trachea_ring_plate_selector,
        features = listOf(
            feature("trachea-ring-posterior-wall", 193, 49, string.health_atlas_trachea_ring_plate_posterior_wall,
                string.health_atlas_trachea_ring_plate_posterior_wall_detail),
            feature("trachea-ring-lumen", 163, 85, string.health_atlas_trachea_ring_plate_lumen,
                string.health_atlas_trachea_ring_plate_lumen_detail),
            feature("trachea-ring-cartilage", 112, 89, string.health_atlas_trachea_ring_plate_cartilage,
                string.health_atlas_trachea_ring_plate_cartilage_detail),
            feature("trachea-ring-lining", 218, 174, string.health_atlas_trachea_ring_plate_lining,
                string.health_atlas_trachea_ring_plate_lining_detail),
        ),
        splitCallouts = true,
    )

    val bronchi = HealthAtlasPlate(
        drawable = R.drawable.health_atlas_main_bronchi_cutaway,
        owner = "bronchi",
        viewLabel = string.health_atlas_main_bronchi_plate_caption,
        markers = emptyList(),
        source = MAIN_BRONCHI_ANATOMY,
        viewKey = "main-bronchi-cutaway",
        selectorLabel = string.health_atlas_main_bronchi_plate_selector,
        features = listOf(
            feature("main-bronchi-distal-trachea", 171, 67, string.health_atlas_main_bronchi_plate_distal_trachea,
                string.health_atlas_main_bronchi_plate_distal_trachea_detail),
            feature("main-bronchi-carina", 185, 135, string.health_atlas_main_bronchi_plate_carina,
                string.health_atlas_main_bronchi_plate_carina_detail),
            feature("main-bronchi-right", 144, 175, string.health_atlas_main_bronchi_plate_right,
                string.health_atlas_main_bronchi_plate_right_detail),
            feature("main-bronchi-left", 253, 163, string.health_atlas_main_bronchi_plate_left,
                string.health_atlas_main_bronchi_plate_left_detail),
        ),
        splitCallouts = true,
    )

    val all = listOf(larynx, trachea, bronchi)

    fun forId(id: String?) = all.firstOrNull { it.owner == id }
}
