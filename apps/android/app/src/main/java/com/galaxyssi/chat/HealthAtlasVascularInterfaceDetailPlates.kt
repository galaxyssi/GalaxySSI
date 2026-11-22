package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasVascularInterfaceDetailPlates {
    private const val VESSEL_ANATOMY =
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/20-1-structure-and-function-of-blood-vessels"
    private const val AIR_BLOOD_BARRIER =
        "https://columbia.edu/itc/hs/medical/sbpm_histology_old/lab/lab10_micrograph.html"
    private const val PULMONARY_MICROVASCULATURE =
        "https://pmc.ncbi.nlm.nih.gov/articles/PMC8397636/"

    val all: List<HealthAtlasPlate> = listOf(
        plate(
            "veins", drawable.health_atlas_limb_vein_cutaway, "veins-limb-valve-cutaway",
            string.health_atlas_vi_vein_selector, string.health_atlas_vi_vein_view, VESSEL_ANATOMY,
            listOf(marker("gastrocnemius", 76, 95)),
            feature("veins-limb-segment", 105, 72,
                string.health_atlas_vi_vein_segment, string.health_atlas_vi_vein_segment_detail),
            feature("veins-limb-valve-leaflets", 207, 120,
                string.health_atlas_vi_vein_valve, string.health_atlas_vi_vein_valve_detail),
            feature("veins-limb-lumen", 239, 192,
                string.health_atlas_vi_vein_lumen, string.health_atlas_vi_vein_lumen_detail),
            feature("veins-limb-wall", 298, 204,
                string.health_atlas_vi_vein_wall, string.health_atlas_vi_vein_wall_detail),
        ),
        plate(
            "capillaries", drawable.health_atlas_systemic_capillary_bed, "capillaries-systemic-muscle-bed",
            string.health_atlas_vi_systemic_selector, string.health_atlas_vi_systemic_view, VESSEL_ANATOMY,
            listOf(marker("tissue-skeletal-muscle", 221, 129), marker("cell-erythrocyte", 208, 225)),
            feature("capillaries-muscle-arteriole", 55, 104,
                string.health_atlas_vi_systemic_inlet, string.health_atlas_vi_systemic_inlet_detail),
            feature("capillaries-muscle-branch", 173, 63,
                string.health_atlas_vi_systemic_bed, string.health_atlas_vi_systemic_bed_detail),
            feature("capillaries-muscle-venule", 302, 111,
                string.health_atlas_vi_systemic_outlet, string.health_atlas_vi_systemic_outlet_detail),
            feature("capillaries-muscle-endothelium", 146, 205,
                string.health_atlas_vi_systemic_wall, string.health_atlas_vi_systemic_wall_detail),
        ),
        plate(
            "respiratory-membrane", drawable.health_atlas_respiratory_membrane_layers,
            "respiratory-membrane-thin-barrier", string.health_atlas_vi_barrier_selector,
            string.health_atlas_vi_barrier_view, AIR_BLOOD_BARRIER,
            listOf(marker("alveoli", 147, 71), marker("pulmonary-capillaries", 223, 186)),
            feature("respiratory-membrane-type-i-lining", 85, 112,
                string.health_atlas_vi_barrier_epithelium, string.health_atlas_vi_barrier_epithelium_detail),
            feature("respiratory-membrane-fused-basal-laminae", 173, 131,
                string.health_atlas_vi_barrier_basal, string.health_atlas_vi_barrier_basal_detail),
            feature("respiratory-membrane-capillary-lining", 268, 157,
                string.health_atlas_vi_barrier_endothelium, string.health_atlas_vi_barrier_endothelium_detail),
        ),
        plate(
            "pulmonary-capillaries", drawable.health_atlas_pulmonary_septal_plexus,
            "pulmonary-capillaries-septal-plexus", string.health_atlas_vi_pulmonary_selector,
            string.health_atlas_vi_pulmonary_view, PULMONARY_MICROVASCULATURE,
            listOf(marker("alveoli", 195, 70), marker("respiratory-membrane", 258, 117)),
            feature("pulmonary-capillaries-feeding-arteriole", 50, 182,
                string.health_atlas_vi_pulmonary_inlet, string.health_atlas_vi_pulmonary_inlet_detail),
            feature("pulmonary-capillaries-septal-mesh", 181, 169,
                string.health_atlas_vi_pulmonary_mesh, string.health_atlas_vi_pulmonary_mesh_detail),
            feature("pulmonary-capillaries-draining-venule", 310, 188,
                string.health_atlas_vi_pulmonary_outlet, string.health_atlas_vi_pulmonary_outlet_detail),
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
