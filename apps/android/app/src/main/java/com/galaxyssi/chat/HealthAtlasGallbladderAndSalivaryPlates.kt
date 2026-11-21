package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasGallbladderAndSalivaryPlates {
    private val gallbladder = HealthAtlasPlate(
        drawable = drawable.health_atlas_gallbladder_cutaway,
        owner = "gallbladder",
        viewLabel = string.health_atlas_gallbladder_cutaway_caption,
        markers = emptyList(),
        source = "https://anatomy.ttuhscep.edu/gastrointestinal_system/duodenum_tables.html",
        viewKey = "gallbladder-biliary-cutaway",
        selectorLabel = string.health_atlas_gallbladder_cutaway_selector,
        features = listOf(
            feature("gallbladder-fundus", 86, 207, string.health_atlas_gallbladder_cutaway_fundus,
                string.health_atlas_gallbladder_cutaway_fundus_detail),
            feature("gallbladder-body", 118, 151, string.health_atlas_gallbladder_cutaway_body,
                string.health_atlas_gallbladder_cutaway_body_detail),
            feature("gallbladder-neck", 161, 114, string.health_atlas_gallbladder_cutaway_neck,
                string.health_atlas_gallbladder_cutaway_neck_detail),
            feature("gallbladder-cystic-duct", 189, 110, string.health_atlas_gallbladder_cutaway_cystic,
                string.health_atlas_gallbladder_cutaway_cystic_detail),
            feature("gallbladder-common-bile-duct", 222, 175, string.health_atlas_gallbladder_cutaway_common,
                string.health_atlas_gallbladder_cutaway_common_detail),
            feature("gallbladder-duodenal-papilla", 281, 207, string.health_atlas_gallbladder_cutaway_papilla,
                string.health_atlas_gallbladder_cutaway_papilla_detail),
        ),
        splitCallouts = true,
    )

    private val parotid = HealthAtlasPlate(
        drawable = drawable.health_atlas_parotid_cutaway,
        owner = "parotid-glands",
        viewLabel = string.health_atlas_parotid_cutaway_caption,
        markers = emptyList(),
        source = "https://pmc.ncbi.nlm.nih.gov/articles/PMC4048853/",
        viewKey = "parotid-duct-cutaway",
        selectorLabel = string.health_atlas_parotid_cutaway_selector,
        features = listOf(
            feature("parotid-gland-bed", 110, 109, string.health_atlas_parotid_cutaway_gland,
                string.health_atlas_parotid_cutaway_gland_detail),
            feature("parotid-stensen-duct", 168, 120, string.health_atlas_parotid_cutaway_duct,
                string.health_atlas_parotid_cutaway_duct_detail),
            feature("parotid-buccinator-turn", 222, 123, string.health_atlas_parotid_cutaway_turn,
                string.health_atlas_parotid_cutaway_turn_detail),
            feature("parotid-duct-papilla", 250, 152, string.health_atlas_parotid_cutaway_papilla,
                string.health_atlas_parotid_cutaway_papilla_detail),
        ),
        splitCallouts = true,
    )

    private val submandibular = HealthAtlasPlate(
        drawable = drawable.health_atlas_submandibular_cutaway,
        owner = "submandibular-glands",
        viewLabel = string.health_atlas_submandibular_cutaway_caption,
        markers = emptyList(),
        source = "https://www.ncbi.nlm.nih.gov/sites/books/NBK538325/",
        viewKey = "submandibular-duct-cutaway",
        selectorLabel = string.health_atlas_submandibular_cutaway_selector,
        features = listOf(
            feature("submandibular-superficial-part", 100, 213, string.health_atlas_submandibular_cutaway_superficial,
                string.health_atlas_submandibular_cutaway_superficial_detail),
            feature("submandibular-deep-part", 141, 169, string.health_atlas_submandibular_cutaway_deep,
                string.health_atlas_submandibular_cutaway_deep_detail),
            feature("submandibular-mylohyoid", 156, 202, string.health_atlas_submandibular_cutaway_mylohyoid,
                string.health_atlas_submandibular_cutaway_mylohyoid_detail),
            feature("submandibular-wharton-duct", 205, 177, string.health_atlas_submandibular_cutaway_duct,
                string.health_atlas_submandibular_cutaway_duct_detail),
            feature("submandibular-sublingual-neighbor", 233, 156, string.health_atlas_submandibular_cutaway_neighbor,
                string.health_atlas_submandibular_cutaway_neighbor_detail),
            feature("submandibular-sublingual-caruncle", 288, 146, string.health_atlas_submandibular_cutaway_caruncle,
                string.health_atlas_submandibular_cutaway_caruncle_detail),
        ),
        splitCallouts = true,
    )

    val all = listOf(gallbladder, parotid, submandibular)

    fun forId(id: String?) = all.firstOrNull { it.owner == id }

    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(HealthAtlasMarker(id, x / 360f, y / 280f), title, detail)
}
