package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasCardiacOutflowPlates {
    const val AORTA_VIEW_KEY = "aortic-root-arch-cutaway"
    const val PULMONARY_TRUNK_VIEW_KEY = "pulmonary-trunk-bifurcation-cutaway"
    const val CORONARY_VIEW_KEY = "coronary-epicardial-routes"

    private val aorta = plate(
        "aorta", drawable.health_atlas_aortic_root_arch, AORTA_VIEW_KEY,
        string.health_atlas_aortic_root_arch_selector, string.health_atlas_aortic_root_arch_view,
        "https://www.ncbi.nlm.nih.gov/books/NBK538140/",
        feature("aortic-root-valve", 144, 236, string.health_atlas_aortic_root_valve,
            string.health_atlas_aortic_root_valve_detail),
        feature("aortic-root-sinus", 170, 204, string.health_atlas_aortic_root_sinus,
            string.health_atlas_aortic_root_sinus_detail),
        feature("aortic-ascending-segment", 145, 134, string.health_atlas_aortic_ascending,
            string.health_atlas_aortic_ascending_detail),
        feature("aortic-arch-curve", 207, 91, string.health_atlas_aortic_arch,
            string.health_atlas_aortic_arch_detail),
        feature("aortic-arch-brachiocephalic", 120, 54, string.health_atlas_aortic_brachiocephalic,
            string.health_atlas_aortic_brachiocephalic_detail),
        feature("aortic-arch-left-carotid", 194, 35, string.health_atlas_aortic_left_carotid,
            string.health_atlas_aortic_left_carotid_detail),
        feature("aortic-arch-left-subclavian", 254, 54, string.health_atlas_aortic_left_subclavian,
            string.health_atlas_aortic_left_subclavian_detail),
        feature("aortic-descending-segment", 253, 183, string.health_atlas_aortic_descending,
            string.health_atlas_aortic_descending_detail),
    )

    private val pulmonaryTrunk = plate(
        "pulmonary-trunk", drawable.health_atlas_pulmonary_trunk_bifurcation, PULMONARY_TRUNK_VIEW_KEY,
        string.health_atlas_pulmonary_bifurcation_selector, string.health_atlas_pulmonary_bifurcation_view,
        "https://www.ncbi.nlm.nih.gov/books/NBK534812/",
        feature("pulmonary-trunk-valve", 158, 226, string.health_atlas_pulmonary_trunk_valve,
            string.health_atlas_pulmonary_trunk_valve_detail),
        feature("pulmonary-main-trunk", 184, 173, string.health_atlas_pulmonary_main_trunk,
            string.health_atlas_pulmonary_main_trunk_detail),
        feature("pulmonary-trunk-branch-point", 196, 111, string.health_atlas_pulmonary_branch_point,
            string.health_atlas_pulmonary_branch_point_detail),
        feature("pulmonary-right-arterial-branch", 83, 101, string.health_atlas_pulmonary_right_branch,
            string.health_atlas_pulmonary_right_branch_detail),
        feature("pulmonary-left-arterial-branch", 277, 125, string.health_atlas_pulmonary_left_branch,
            string.health_atlas_pulmonary_left_branch_detail),
    )

    private val coronary = plate(
        "coronary-vessels", drawable.health_atlas_coronary_epicardial_routes, CORONARY_VIEW_KEY,
        string.health_atlas_coronary_routes_selector, string.health_atlas_coronary_routes_view,
        "https://pmc.ncbi.nlm.nih.gov/articles/PMC287879/",
        feature("coronary-right-av-groove", 106, 137, string.health_atlas_coronary_right_route,
            string.health_atlas_coronary_right_route_detail),
        feature("coronary-right-marginal-route", 122, 190, string.health_atlas_coronary_right_marginal,
            string.health_atlas_coronary_right_marginal_detail),
        feature("coronary-left-main-stem", 216, 101, string.health_atlas_coronary_left_main,
            string.health_atlas_coronary_left_main_detail),
        feature("coronary-anterior-interventricular-route", 223, 178,
            string.health_atlas_coronary_lad, string.health_atlas_coronary_lad_detail),
        feature("coronary-left-av-groove", 269, 129, string.health_atlas_coronary_circumflex,
            string.health_atlas_coronary_circumflex_detail),
    )

    val all: List<HealthAtlasPlate> = listOf(aorta, pulmonaryTrunk, coronary)
    private val byId = all.associateBy { it.owner }

    fun forId(id: String?): HealthAtlasPlate? = byId[id]

    private fun plate(owner: String, art: Int, viewKey: String, selector: Int, caption: Int, source: String,
        vararg features: HealthAtlasFeature) =
        HealthAtlasPlate(art, owner, caption, emptyList(), source, viewKey = viewKey,
            selectorLabel = selector, features = features.toList(), splitCallouts = true)

    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(HealthAtlasMarker(id, x / 360f, y / 280f), title, detail)
}
