package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasCardiacComparisonDetailPlates {
    private const val ATRIAL_ANATOMY = "https://pmc.ncbi.nlm.nih.gov/articles/PMC1571338/"
    private const val VENTRICULAR_ANATOMY = "https://pmc.ncbi.nlm.nih.gov/articles/PMC1860731/"
    private const val VALVE_ANATOMY =
        "https://www.vhlab.umn.edu/atlas/anatomy-tutorial/cardiac-valve-nomenclature.shtml"

    val all: List<HealthAtlasPlate> = listOf(
        plate(
            "atria", drawable.health_atlas_atria_comparison, "atria-opened-interiors",
            string.health_atlas_atria_compare_selector, string.health_atlas_atria_compare_view, ATRIAL_ANATOMY,
            listOf(marker("right-atrium", 95, 188), marker("left-atrium", 282, 186)),
            feature("atria-superior-caval-opening", 105, 79,
                string.health_atlas_atria_compare_caval, string.health_atlas_atria_compare_caval_detail),
            feature("atria-pectinate-wall", 63, 135,
                string.health_atlas_atria_compare_pectinate, string.health_atlas_atria_compare_pectinate_detail),
            feature("atria-oval-fossa", 141, 148,
                string.health_atlas_atria_compare_fossa, string.health_atlas_atria_compare_fossa_detail),
            feature("atria-pulmonary-venous-openings", 225, 92,
                string.health_atlas_atria_compare_pulmonary, string.health_atlas_atria_compare_pulmonary_detail),
            feature("atria-smooth-posterior-wall", 255, 139,
                string.health_atlas_atria_compare_smooth, string.health_atlas_atria_compare_smooth_detail),
        ),
        plate(
            "ventricles", drawable.health_atlas_ventricles_short_axis, "ventricles-mid-short-axis",
            string.health_atlas_ventricles_compare_selector, string.health_atlas_ventricles_compare_view,
            VENTRICULAR_ANATOMY,
            listOf(marker("right-ventricle", 108, 87), marker("left-ventricle", 230, 160)),
            feature("ventricles-right-free-wall", 98, 50,
                string.health_atlas_ventricles_compare_right_wall, string.health_atlas_ventricles_compare_right_wall_detail),
            feature("ventricles-right-trabeculae", 78, 128,
                string.health_atlas_ventricles_compare_trabeculae, string.health_atlas_ventricles_compare_trabeculae_detail),
            feature("ventricles-muscular-septum", 143, 157,
                string.health_atlas_ventricles_compare_septum, string.health_atlas_ventricles_compare_septum_detail),
            feature("ventricles-left-free-wall", 291, 178,
                string.health_atlas_ventricles_compare_left_wall, string.health_atlas_ventricles_compare_left_wall_detail),
        ),
        plate(
            "heart-valves", drawable.health_atlas_heart_valves_comparison, "heart-valves-comparative-faces",
            string.health_atlas_valves_compare_selector, string.health_atlas_valves_compare_view, VALVE_ANATOMY,
            listOf(
                marker("pulmonary-valve", 99, 72), marker("aortic-valve", 259, 72),
                marker("tricuspid-valve", 102, 205), marker("mitral-valve", 252, 220),
            ),
            feature("heart-valves-pulmonary-cusps", 99, 44,
                string.health_atlas_valves_compare_pulmonary, string.health_atlas_valves_compare_pulmonary_detail),
            feature("heart-valves-aortic-cusps", 269, 97,
                string.health_atlas_valves_compare_aortic, string.health_atlas_valves_compare_aortic_detail),
            feature("heart-valves-tricuspid-leaflets", 75, 178,
                string.health_atlas_valves_compare_tricuspid, string.health_atlas_valves_compare_tricuspid_detail),
            feature("heart-valves-mitral-leaflets", 255, 182,
                string.health_atlas_valves_compare_mitral, string.health_atlas_valves_compare_mitral_detail),
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
