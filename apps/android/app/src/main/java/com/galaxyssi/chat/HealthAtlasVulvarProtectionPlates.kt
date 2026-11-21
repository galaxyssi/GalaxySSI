package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasVulvarProtectionPlates {
    const val ANATOMY_SOURCE = "https://openstax.org/books/biology/pages/43-3-human-reproductive-anatomy-and-gametogenesis"
    const val WIDTH = 360
    const val HEIGHT = 280

    private fun feature(id: String, x: Int, y: Int, title: Int, explanation: Int) =
        HealthAtlasFeature(HealthAtlasMarker(id, x / WIDTH.toFloat(), y / HEIGHT.toFloat()), title, explanation)

    val region = HealthAtlasPlate(
        drawable = drawable.health_atlas_vulvar_protection_region,
        owner = HealthAtlasVulvarProtectionAssignment.VULVA_ID,
        viewLabel = string.health_atlas_vulvar_protection_region_caption,
        markers = emptyList(),
        source = ANATOMY_SOURCE,
        viewKey = "vulva-fold-region",
        selectorLabel = string.health_atlas_vulvar_protection_region_view,
        features = listOf(
            feature("vulva-outer-boundary", 105, 76, string.health_atlas_vulvar_protection_outer_boundary,
                string.health_atlas_vulvar_protection_outer_boundary_detail),
            feature("vulva-outer-folds", 133, 126, string.health_atlas_vulvar_protection_outer_folds,
                string.health_atlas_vulvar_protection_outer_folds_detail),
            feature("vulva-inner-folds", 206, 119, string.health_atlas_vulvar_protection_inner_folds,
                string.health_atlas_vulvar_protection_inner_folds_detail),
            feature("vulva-vestibule", 180, 152, string.health_atlas_vulvar_protection_vestibule,
                string.health_atlas_vulvar_protection_vestibule_detail),
        ),
        splitCallouts = true,
    )

    val outer = HealthAtlasPlate(
        drawable = drawable.health_atlas_vulvar_protection_outer_section,
        owner = HealthAtlasVulvarProtectionAssignment.MAJORA_ID,
        viewLabel = string.health_atlas_vulvar_protection_outer_plate_caption,
        markers = emptyList(),
        source = ANATOMY_SOURCE,
        viewKey = "labia-majora-transverse-section",
        selectorLabel = string.health_atlas_vulvar_protection_outer_view,
        features = listOf(
            feature("labia-majora-skin-surface", 113, 80, string.health_atlas_vulvar_protection_skin_surface,
                string.health_atlas_vulvar_protection_skin_surface_detail),
            feature("labia-majora-fatty-tissue", 101, 151, string.health_atlas_vulvar_protection_fatty_cushion,
                string.health_atlas_vulvar_protection_fatty_cushion_detail),
            feature("labia-majora-vestibule-surface", 180, 190, string.health_atlas_vulvar_protection_vestibule_floor,
                string.health_atlas_vulvar_protection_vestibule_floor_detail),
        ),
        splitCallouts = true,
    )

    val inner = HealthAtlasPlate(
        drawable = drawable.health_atlas_vulvar_protection_inner_closeup,
        owner = HealthAtlasVulvarProtectionAssignment.MINORA_ID,
        viewLabel = string.health_atlas_vulvar_protection_inner_plate_caption,
        markers = emptyList(),
        source = ANATOMY_SOURCE,
        viewKey = "labia-minora-vestibule-closeup",
        selectorLabel = string.health_atlas_vulvar_protection_inner_view,
        features = listOf(
            feature("labia-minora-fold-body", 135, 128, string.health_atlas_vulvar_protection_inner_folds,
                string.health_atlas_vulvar_protection_inner_folds_detail),
            feature("labia-minora-medial-margin", 209, 132, string.health_atlas_vulvar_protection_inner_margin,
                string.health_atlas_vulvar_protection_inner_margin_detail),
            feature("labia-minora-vestibule", 181, 153, string.health_atlas_vulvar_protection_vestibule,
                string.health_atlas_vulvar_protection_vestibule_detail),
        ),
        splitCallouts = true,
    )

    val all = listOf(region, outer, inner)

    fun forId(id: String?): HealthAtlasPlate? = all.firstOrNull { it.owner == id }
}
