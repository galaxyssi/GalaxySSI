package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasHeartChamberDetailPlates {
    private const val CARDIAC_ANATOMY = "https://onlinelibrary.wiley.com/doi/10.1111/j.0021-8782.2004.00330.x"
    private const val HEART_ANATOMY =
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/19-1-heart-anatomy"

    val all: List<HealthAtlasPlate> = listOf(
        plate(
            "right-atrium", drawable.health_atlas_right_atrium_cutaway, "right-atrium-caval-cutaway",
            string.health_atlas_ra_cutaway_selector, string.health_atlas_ra_cutaway_view, HEART_ANATOMY,
            listOf(marker("tricuspid-valve", 234, 205)),
            feature("right-atrium-superior-caval-opening", 143, 67,
                string.health_atlas_ra_svc, string.health_atlas_ra_svc_detail),
            feature("right-atrium-pectinate-muscles", 103, 124,
                string.health_atlas_ra_pectinate, string.health_atlas_ra_pectinate_detail),
            feature("right-atrium-fossa-ovalis", 219, 132,
                string.health_atlas_ra_fossa, string.health_atlas_ra_fossa_detail),
            feature("right-atrium-inferior-caval-opening", 151, 216,
                string.health_atlas_ra_ivc, string.health_atlas_ra_ivc_detail),
        ),
        plate(
            "left-atrium", drawable.health_atlas_left_atrium_cutaway, "left-atrium-pulmonary-venous-cutaway",
            string.health_atlas_la_cutaway_selector, string.health_atlas_la_cutaway_view, CARDIAC_ANATOMY,
            listOf(marker("mitral-valve", 188, 209)),
            feature("left-atrium-right-pulmonary-openings", 116, 73,
                string.health_atlas_la_right_veins, string.health_atlas_la_right_veins_detail),
            feature("left-atrium-left-pulmonary-openings", 238, 70,
                string.health_atlas_la_left_veins, string.health_atlas_la_left_veins_detail),
            feature("left-atrium-appendage", 280, 133,
                string.health_atlas_la_appendage, string.health_atlas_la_appendage_detail),
            feature("left-atrium-posterior-wall", 149, 148,
                string.health_atlas_la_posterior_wall, string.health_atlas_la_posterior_wall_detail),
        ),
        plate(
            "right-ventricle", drawable.health_atlas_right_ventricle_cutaway, "right-ventricle-inlet-outlet-cutaway",
            string.health_atlas_rv_cutaway_selector, string.health_atlas_rv_cutaway_view, CARDIAC_ANATOMY,
            listOf(marker("tricuspid-valve", 103, 79), marker("pulmonary-trunk", 246, 40)),
            feature("right-ventricle-infundibulum", 224, 105,
                string.health_atlas_rv_infundibulum, string.health_atlas_rv_infundibulum_detail),
            feature("right-ventricle-moderator-band", 189, 191,
                string.health_atlas_rv_moderator_band, string.health_atlas_rv_moderator_band_detail),
            feature("right-ventricle-trabeculae", 126, 217,
                string.health_atlas_rv_trabeculae, string.health_atlas_rv_trabeculae_detail),
        ),
        plate(
            "left-ventricle", drawable.health_atlas_left_ventricle_cutaway, "left-ventricle-long-axis-cutaway",
            string.health_atlas_lv_cutaway_selector, string.health_atlas_lv_cutaway_view, HEART_ANATOMY,
            listOf(marker("mitral-valve", 233, 83), marker("aortic-valve", 136, 60)),
            feature("left-ventricle-myocardium", 91, 155,
                string.health_atlas_lv_myocardium, string.health_atlas_lv_myocardium_detail),
            feature("left-ventricle-chordae", 207, 131,
                string.health_atlas_lv_chordae, string.health_atlas_lv_chordae_detail),
            feature("left-ventricle-papillary-muscles", 146, 181,
                string.health_atlas_lv_papillary, string.health_atlas_lv_papillary_detail),
        ),
    )

    private fun plate(
        owner: String, art: Int, viewKey: String, selector: Int, caption: Int, source: String,
        markers: List<HealthAtlasMarker>, vararg features: HealthAtlasFeature,
    ) = HealthAtlasPlate(
        drawable = art,
        owner = owner,
        viewLabel = caption,
        markers = markers,
        source = source,
        viewKey = viewKey,
        selectorLabel = selector,
        features = features.toList(),
        splitCallouts = true,
    )

    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)

    private fun feature(id: String, x: Int, y: Int, title: Int, explanation: Int) =
        HealthAtlasFeature(marker(id, x, y), title, explanation)
}
