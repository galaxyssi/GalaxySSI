package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasPosteriorMuscleTendonDetailPlates {
    private const val POSTERIOR_ANATOMY =
        "https://anatomy.ttuhscep.edu/musculoskeletal_system/gluteal_tables.html"
    private const val TENDON_STRUCTURE = "https://pmc.ncbi.nlm.nih.gov/articles/PMC8154658/"

    val all: List<HealthAtlasPlate> = listOf(
        HealthAtlasPlate(
            drawable = drawable.health_atlas_gluteus_maximus_posterior_attachments,
            owner = "gluteus-maximus",
            viewLabel = string.health_atlas_gluteus_maximus_posterior_attachments_view,
            markers = listOf(marker("pelvis", 149, 47), marker("femur", 223, 233)),
            source = POSTERIOR_ANATOMY,
            viewKey = "gluteus-maximus-posterior-attachments",
            selectorLabel = string.health_atlas_gluteus_maximus_posterior_attachments_selector,
            features = listOf(
                feature("gluteus-maximus-iliac-origin", 166, 67,
                    string.health_atlas_gluteus_maximus_iliac_origin,
                    string.health_atlas_gluteus_maximus_iliac_origin_detail),
                feature("gluteus-maximus-sacral-origin", 124, 111,
                    string.health_atlas_gluteus_maximus_sacral_origin,
                    string.health_atlas_gluteus_maximus_sacral_origin_detail),
                feature("gluteus-maximus-iliotibial-insertion", 255, 145,
                    string.health_atlas_gluteus_maximus_iliotibial_insertion,
                    string.health_atlas_gluteus_maximus_iliotibial_insertion_detail),
                feature("gluteus-maximus-femoral-insertion", 216, 190,
                    string.health_atlas_gluteus_maximus_femoral_insertion,
                    string.health_atlas_gluteus_maximus_femoral_insertion_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = drawable.health_atlas_gastrocnemius_posterior_attachments,
            owner = "gastrocnemius",
            viewLabel = string.health_atlas_gastrocnemius_posterior_attachments_view,
            markers = listOf(marker("soleus", 116, 151), marker("tendons", 170, 212)),
            source = POSTERIOR_ANATOMY,
            viewKey = "gastrocnemius-posterior-attachments",
            selectorLabel = string.health_atlas_gastrocnemius_posterior_attachments_selector,
            features = listOf(
                feature("gastrocnemius-medial-origin", 140, 57,
                    string.health_atlas_gastrocnemius_medial_origin,
                    string.health_atlas_gastrocnemius_medial_origin_detail),
                feature("gastrocnemius-lateral-origin", 216, 56,
                    string.health_atlas_gastrocnemius_lateral_origin,
                    string.health_atlas_gastrocnemius_lateral_origin_detail),
                feature("gastrocnemius-aponeurosis", 185, 166,
                    string.health_atlas_gastrocnemius_aponeurosis,
                    string.health_atlas_gastrocnemius_aponeurosis_detail),
                feature("gastrocnemius-calcaneal-insertion", 183, 245,
                    string.health_atlas_gastrocnemius_calcaneal_insertion,
                    string.health_atlas_gastrocnemius_calcaneal_insertion_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = drawable.health_atlas_tendons_fascicle_cross_section,
            owner = "tendons",
            viewLabel = string.health_atlas_tendons_fascicle_cross_section_view,
            markers = listOf(marker("gastrocnemius", 80, 61)),
            source = TENDON_STRUCTURE,
            viewKey = "tendons-fascicle-cross-section",
            selectorLabel = string.health_atlas_tendons_fascicle_cross_section_selector,
            features = listOf(
                feature("tendons-achilles-midportion", 96, 155,
                    string.health_atlas_tendons_achilles_midportion,
                    string.health_atlas_tendons_achilles_midportion_detail),
                feature("tendons-epitenon", 304, 143,
                    string.health_atlas_tendons_epitenon,
                    string.health_atlas_tendons_epitenon_detail),
                feature("tendons-fascicle", 251, 141,
                    string.health_atlas_tendons_fascicle,
                    string.health_atlas_tendons_fascicle_detail),
                feature("tendons-endotenon", 248, 162,
                    string.health_atlas_tendons_endotenon,
                    string.health_atlas_tendons_endotenon_detail),
            ),
            splitCallouts = true,
        ),
    )

    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)

    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(marker(id, x, y), title, detail)
}
