package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasDigestiveDuctDetailPlates {
    private const val SALIVARY_ANATOMY =
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-3-the-mouth-pharynx-and-esophagus"
    private const val FLOOR_OF_MOUTH_ANATOMY =
        "https://iowaprotocols.medicine.uiowa.edu/protocols/salivary-gland-terminology-anatomy-salivation-dry-mouth-drooling"
    private const val PANCREATIC_DUCT_ANATOMY = "https://mapkmc.manipal.edu/specimen/anat310/"

    val all: List<HealthAtlasPlate> = listOf(
        HealthAtlasPlate(
            drawable = drawable.health_atlas_major_salivary_pairs,
            owner = "salivary-glands",
            viewLabel = string.health_atlas_major_salivary_pairs_view,
            markers = listOf(
                marker("parotid-glands", 291, 132),
                marker("submandibular-glands", 252, 225),
                marker("sublingual-glands", 209, 188),
            ),
            source = SALIVARY_ANATOMY,
            viewKey = "salivary-glands-bilateral-map",
            selectorLabel = string.health_atlas_major_salivary_pairs_selector,
            features = listOf(
                feature("salivary-pair-parotid", 69, 132,
                    string.health_atlas_major_salivary_parotid, string.health_atlas_major_salivary_parotid_detail),
                feature("salivary-pair-submandibular", 108, 225,
                    string.health_atlas_major_salivary_submandibular, string.health_atlas_major_salivary_submandibular_detail),
                feature("salivary-pair-sublingual", 151, 188,
                    string.health_atlas_major_salivary_sublingual, string.health_atlas_major_salivary_sublingual_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = drawable.health_atlas_sublingual_floor_cutaway,
            owner = "sublingual-glands",
            viewLabel = string.health_atlas_sublingual_floor_view,
            markers = listOf(marker("tongue", 214, 73)),
            source = FLOOR_OF_MOUTH_ANATOMY,
            viewKey = "sublingual-glands-oral-floor-cutaway",
            selectorLabel = string.health_atlas_sublingual_floor_selector,
            features = listOf(
                feature("sublingual-floor-gland-bed", 92, 143,
                    string.health_atlas_sublingual_floor_gland, string.health_atlas_sublingual_floor_gland_detail),
                feature("sublingual-floor-rivinus-ducts", 127, 171,
                    string.health_atlas_sublingual_floor_rivinus, string.health_atlas_sublingual_floor_rivinus_detail),
                feature("sublingual-floor-mucosal-fold", 224, 177,
                    string.health_atlas_sublingual_floor_fold, string.health_atlas_sublingual_floor_fold_detail),
                feature("sublingual-floor-caruncle", 190, 201,
                    string.health_atlas_sublingual_floor_caruncle, string.health_atlas_sublingual_floor_caruncle_detail),
                feature("sublingual-floor-frenulum", 179, 112,
                    string.health_atlas_sublingual_floor_frenulum, string.health_atlas_sublingual_floor_frenulum_detail),
                feature("sublingual-floor-wharton-duct", 250, 198,
                    string.health_atlas_sublingual_floor_wharton, string.health_atlas_sublingual_floor_wharton_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = drawable.health_atlas_pancreatic_main_duct_cutaway,
            owner = "pancreatic-duct",
            viewLabel = string.health_atlas_pancreatic_main_duct_view,
            markers = listOf(
                marker("pancreas", 130, 180),
                marker("biliary-tract", 105, 54),
                marker("duodenum", 68, 213),
            ),
            source = PANCREATIC_DUCT_ANATOMY,
            viewKey = "pancreatic-duct-tail-to-papilla-cutaway",
            selectorLabel = string.health_atlas_pancreatic_main_duct_selector,
            features = listOf(
                feature("pancreatic-main-tail-tributaries", 279, 94,
                    string.health_atlas_pancreatic_main_duct_tributaries, string.health_atlas_pancreatic_main_duct_tributaries_detail),
                feature("pancreatic-main-trunk", 204, 120,
                    string.health_atlas_pancreatic_main_duct_trunk, string.health_atlas_pancreatic_main_duct_trunk_detail),
                feature("pancreatic-main-head-bend", 119, 142,
                    string.health_atlas_pancreatic_main_duct_bend, string.health_atlas_pancreatic_main_duct_bend_detail),
                feature("pancreatic-main-major-papilla", 72, 174,
                    string.health_atlas_pancreatic_main_duct_papilla, string.health_atlas_pancreatic_main_duct_papilla_detail),
            ),
            splitCallouts = true,
        ),
    )

    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)

    private fun feature(id: String, x: Int, y: Int, title: Int, explanation: Int) =
        HealthAtlasFeature(marker(id, x, y), title, explanation)
}
