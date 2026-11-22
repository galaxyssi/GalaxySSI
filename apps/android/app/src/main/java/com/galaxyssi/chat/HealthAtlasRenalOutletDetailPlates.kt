package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasRenalOutletDetailPlates {
    private const val KIDNEY_HISTOLOGY = "https://histology.oit.duke.edu/NormalBody/Urinary/Urinary.html"
    private const val DISTAL_ANATOMY = "https://pmc.ncbi.nlm.nih.gov/articles/PMC5810970/"
    private const val COLLECTING_ANATOMY =
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/25-4-microscopic-anatomy-of-the-kidney"

    val all: List<HealthAtlasPlate> = listOf(
        HealthAtlasPlate(
            drawable = drawable.health_atlas_renal_tubules_segment_overview,
            owner = "renal-tubules",
            viewLabel = string.health_atlas_renal_tubules_segment_view,
            markers = listOf(
                marker("glomerulus", 168, 89),
                marker("proximal-tubule", 91, 80),
                marker("distal-tubule", 252, 61),
                marker("collecting-ducts", 307, 164),
            ),
            source = KIDNEY_HISTOLOGY,
            viewKey = "renal-tubules-segment-overview",
            selectorLabel = string.health_atlas_renal_tubules_segment_selector,
            features = listOf(
                feature("renal-tubules-urinary-pole", 134, 106, string.health_atlas_renal_tubules_urinary_pole,
                    string.health_atlas_renal_tubules_urinary_pole_detail),
                feature("renal-tubules-loop-bend", 160, 237, string.health_atlas_renal_tubules_loop_bend,
                    string.health_atlas_renal_tubules_loop_bend_detail),
                feature("renal-tubules-thick-ascending", 212, 161, string.health_atlas_renal_tubules_thick_ascending,
                    string.health_atlas_renal_tubules_thick_ascending_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = drawable.health_atlas_distal_tubule_cortical_junction,
            owner = "distal-tubule",
            viewLabel = string.health_atlas_distal_tubule_junction_view,
            markers = listOf(
                marker("glomerulus", 89, 76),
                marker("nephron-loop", 79, 208),
                marker("collecting-ducts", 306, 188),
            ),
            source = DISTAL_ANATOMY,
            viewKey = "distal-tubule-cortical-junction",
            selectorLabel = string.health_atlas_distal_tubule_junction_selector,
            features = listOf(
                feature("distal-tubule-macula-densa", 113, 119, string.health_atlas_distal_tubule_macula,
                    string.health_atlas_distal_tubule_macula_detail),
                feature("distal-tubule-convolution", 177, 57, string.health_atlas_distal_tubule_convolution,
                    string.health_atlas_distal_tubule_convolution_detail),
                feature("distal-tubule-cuboidal-lining", 225, 138, string.health_atlas_distal_tubule_lining,
                    string.health_atlas_distal_tubule_lining_detail),
                feature("distal-tubule-connecting-segment", 254, 222, string.health_atlas_distal_tubule_connector,
                    string.health_atlas_distal_tubule_connector_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = drawable.health_atlas_collecting_ducts_papillary_tree,
            owner = "collecting-ducts",
            viewLabel = string.health_atlas_collecting_ducts_tree_view,
            markers = listOf(
                marker("distal-tubule", 66, 49),
                marker("renal-medulla", 250, 139),
            ),
            source = COLLECTING_ANATOMY,
            viewKey = "collecting-ducts-papillary-tree",
            selectorLabel = string.health_atlas_collecting_ducts_tree_selector,
            features = listOf(
                feature("collecting-ducts-cortical-confluence", 146, 108,
                    string.health_atlas_collecting_ducts_cortical, string.health_atlas_collecting_ducts_cortical_detail),
                feature("collecting-ducts-medullary-trunk", 224, 160,
                    string.health_atlas_collecting_ducts_medullary, string.health_atlas_collecting_ducts_medullary_detail),
                feature("collecting-ducts-papillary-outlet", 190, 220,
                    string.health_atlas_collecting_ducts_papillary, string.health_atlas_collecting_ducts_papillary_detail),
                feature("collecting-ducts-minor-calyx", 153, 235,
                    string.health_atlas_collecting_ducts_calyx, string.health_atlas_collecting_ducts_calyx_detail),
            ),
            splitCallouts = true,
        ),
    )

    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)

    private fun feature(id: String, x: Int, y: Int, title: Int, explanation: Int) =
        HealthAtlasFeature(marker(id, x, y), title, explanation)
}
