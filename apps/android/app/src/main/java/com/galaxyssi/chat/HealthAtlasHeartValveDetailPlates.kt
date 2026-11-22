package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasHeartValveDetailPlates {
    private val tricuspid = plate(
        "tricuspid-valve", drawable.health_atlas_tricuspid_valve_cutaway, "tricuspid-valve-cutaway",
        string.health_atlas_valve_detail_tricuspid_selector, string.health_atlas_valve_detail_tricuspid_view,
        "https://doi.org/10.1002/ca.22591",
        listOf(marker("right-ventricle", 219, 214)),
        feature("tricuspid-anterior-leaflet", 111, 113, string.health_atlas_valve_detail_tricuspid_anterior,
            string.health_atlas_valve_detail_tricuspid_anterior_detail),
        feature("tricuspid-septal-leaflet", 247, 111, string.health_atlas_valve_detail_tricuspid_septal,
            string.health_atlas_valve_detail_tricuspid_septal_detail),
        feature("tricuspid-posterior-leaflet", 164, 155, string.health_atlas_valve_detail_tricuspid_posterior,
            string.health_atlas_valve_detail_tricuspid_posterior_detail),
        feature("tricuspid-chordae", 139, 172, string.health_atlas_valve_detail_tricuspid_chordae,
            string.health_atlas_valve_detail_tricuspid_chordae_detail),
    )

    private val mitral = plate(
        "mitral-valve", drawable.health_atlas_mitral_valve_cutaway, "mitral-valve-cutaway",
        string.health_atlas_valve_detail_mitral_selector, string.health_atlas_valve_detail_mitral_view,
        "https://doi.org/10.1530/ERP-20-0034",
        listOf(marker("left-atrium", 123, 59)),
        feature("mitral-anterior-leaflet", 226, 129, string.health_atlas_valve_detail_mitral_anterior,
            string.health_atlas_valve_detail_mitral_anterior_detail),
        feature("mitral-posterior-leaflet", 107, 120, string.health_atlas_valve_detail_mitral_posterior,
            string.health_atlas_valve_detail_mitral_posterior_detail),
        feature("mitral-chordae", 215, 175, string.health_atlas_valve_detail_mitral_chordae,
            string.health_atlas_valve_detail_mitral_chordae_detail),
        feature("mitral-papillary-muscles", 126, 203, string.health_atlas_valve_detail_mitral_papillary,
            string.health_atlas_valve_detail_mitral_papillary_detail),
    )

    private val pulmonary = plate(
        "pulmonary-valve", drawable.health_atlas_pulmonary_valve_cutaway, "pulmonary-valve-cutaway",
        string.health_atlas_valve_detail_pulmonary_selector, string.health_atlas_valve_detail_pulmonary_view,
        "https://www.asecho.org/wp-content/uploads/2022/01/PIIS0894731721005940.pdf",
        listOf(marker("right-ventricle", 137, 222), marker("pulmonary-trunk", 210, 52)),
        feature("pulmonary-valve-right-cusp", 142, 126, string.health_atlas_valve_detail_pulmonary_right,
            string.health_atlas_valve_detail_pulmonary_right_detail),
        feature("pulmonary-valve-left-cusp", 231, 117, string.health_atlas_valve_detail_pulmonary_left,
            string.health_atlas_valve_detail_pulmonary_left_detail),
        feature("pulmonary-valve-anterior-cusp", 173, 162, string.health_atlas_valve_detail_pulmonary_anterior,
            string.health_atlas_valve_detail_pulmonary_anterior_detail),
    )

    private val aortic = plate(
        "aortic-valve", drawable.health_atlas_aortic_valve_cutaway, "aortic-valve-cutaway",
        string.health_atlas_valve_detail_aortic_selector, string.health_atlas_valve_detail_aortic_view,
        "https://www.vhlab.umn.edu/atlas/anatomy-tutorial/cardiac-valve-nomenclature.shtml",
        listOf(marker("aorta", 153, 48)),
        feature("aortic-valve-left-coronary-cusp", 143, 126, string.health_atlas_valve_detail_aortic_left,
            string.health_atlas_valve_detail_aortic_left_detail),
        feature("aortic-valve-right-coronary-cusp", 225, 126, string.health_atlas_valve_detail_aortic_right,
            string.health_atlas_valve_detail_aortic_right_detail),
        feature("aortic-valve-noncoronary-cusp", 197, 162, string.health_atlas_valve_detail_aortic_noncoronary,
            string.health_atlas_valve_detail_aortic_noncoronary_detail),
        feature("aortic-valve-left-coronary-ostium", 119, 108, string.health_atlas_valve_detail_aortic_ostium,
            string.health_atlas_valve_detail_aortic_ostium_detail),
    )

    val all: List<HealthAtlasPlate> = listOf(tricuspid, mitral, pulmonary, aortic)

    private fun plate(owner: String, art: Int, viewKey: String, selector: Int, caption: Int, source: String,
        markers: List<HealthAtlasMarker>, vararg features: HealthAtlasFeature) =
        HealthAtlasPlate(art, owner, caption, markers, source, viewKey = viewKey,
            selectorLabel = selector, features = features.toList(), splitCallouts = true)

    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)

    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(marker(id, x, y), title, detail)
}
