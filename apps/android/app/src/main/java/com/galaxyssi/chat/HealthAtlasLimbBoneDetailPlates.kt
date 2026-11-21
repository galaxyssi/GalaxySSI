package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

internal object HealthAtlasLimbBoneDetailPlates {
    private const val OPENSTAX = "https://openstax.org/books/anatomy-and-physiology-2e/pages/"
    private const val LOWER_LIMB = OPENSTAX + "8-4-bones-of-the-lower-limb"
    private const val PATELLA = "https://faculty.ksu.edu.sa/sites/default/files/2_humanskeletalanatomy.pdf#page=19"

    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)

    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(marker(id, x, y), title, detail)

    val all = listOf(
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_femur_anterior_landmarks,
            owner = "femur",
            viewLabel = string.health_atlas_femur_landmarks_caption,
            markers = emptyList(),
            source = LOWER_LIMB,
            viewKey = "femur-anterior-landmarks",
            selectorLabel = string.health_atlas_femur_landmarks_selector,
            features = listOf(
                feature("femur-head", 206, 39, string.health_atlas_femur_landmarks_head,
                    string.health_atlas_femur_landmarks_head_detail),
                feature("femur-neck", 183, 60, string.health_atlas_femur_landmarks_neck,
                    string.health_atlas_femur_landmarks_neck_detail),
                feature("femur-greater-trochanter", 152, 51, string.health_atlas_femur_landmarks_trochanter,
                    string.health_atlas_femur_landmarks_trochanter_detail),
                feature("femur-shaft", 166, 146, string.health_atlas_femur_landmarks_shaft,
                    string.health_atlas_femur_landmarks_shaft_detail),
                feature("femur-patellar-surface", 176, 237, string.health_atlas_femur_landmarks_patellar_surface,
                    string.health_atlas_femur_landmarks_patellar_surface_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_patella_posterior_landmarks,
            owner = "patella",
            viewLabel = string.health_atlas_patella_landmarks_caption,
            markers = listOf(marker("femur", 272, 120)),
            source = PATELLA,
            viewKey = "patella-posterior-landmarks",
            selectorLabel = string.health_atlas_patella_landmarks_selector,
            features = listOf(
                feature("patella-base", 153, 65, string.health_atlas_patella_landmarks_base,
                    string.health_atlas_patella_landmarks_base_detail),
                feature("patella-medial-facet", 123, 115, string.health_atlas_patella_landmarks_medial_facet,
                    string.health_atlas_patella_landmarks_medial_facet_detail),
                feature("patella-lateral-facet", 183, 109, string.health_atlas_patella_landmarks_lateral_facet,
                    string.health_atlas_patella_landmarks_lateral_facet_detail),
                feature("patella-vertical-ridge", 149, 138, string.health_atlas_patella_landmarks_ridge,
                    string.health_atlas_patella_landmarks_ridge_detail),
                feature("patella-apex", 155, 198, string.health_atlas_patella_landmarks_apex,
                    string.health_atlas_patella_landmarks_apex_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_foot_bones_dorsal_landmarks,
            owner = "foot-bones",
            viewLabel = string.health_atlas_foot_bones_landmarks_caption,
            markers = emptyList(),
            source = LOWER_LIMB,
            viewKey = "foot-bones-dorsal-landmarks",
            selectorLabel = string.health_atlas_foot_bones_landmarks_selector,
            features = listOf(
                feature("foot-bones-phalanges", 136, 36, string.health_atlas_foot_bones_landmarks_phalanges,
                    string.health_atlas_foot_bones_landmarks_phalanges_detail),
                feature("foot-bones-metatarsals", 177, 121, string.health_atlas_foot_bones_landmarks_metatarsals,
                    string.health_atlas_foot_bones_landmarks_metatarsals_detail),
                feature("foot-bones-navicular", 190, 200, string.health_atlas_foot_bones_landmarks_navicular,
                    string.health_atlas_foot_bones_landmarks_navicular_detail),
                feature("foot-bones-talus", 200, 232, string.health_atlas_foot_bones_landmarks_talus,
                    string.health_atlas_foot_bones_landmarks_talus_detail),
                feature("foot-bones-calcaneus", 233, 253, string.health_atlas_foot_bones_landmarks_calcaneus,
                    string.health_atlas_foot_bones_landmarks_calcaneus_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_ulna_lateral_landmarks,
            owner = "ulna",
            viewLabel = string.health_atlas_ulna_landmarks_caption,
            markers = listOf(marker("radius", 220, 150)),
            source = OPENSTAX + "8-2-bones-of-the-upper-limb",
            viewKey = "ulna-lateral-landmarks",
            selectorLabel = string.health_atlas_ulna_landmarks_selector,
            features = listOf(
                feature("ulna-olecranon", 179, 35, string.health_atlas_ulna_landmarks_olecranon,
                    string.health_atlas_ulna_landmarks_olecranon_detail),
                feature("ulna-trochlear-notch", 180, 60, string.health_atlas_ulna_landmarks_trochlear_notch,
                    string.health_atlas_ulna_landmarks_trochlear_notch_detail),
                feature("ulna-coronoid-process", 201, 79, string.health_atlas_ulna_landmarks_coronoid,
                    string.health_atlas_ulna_landmarks_coronoid_detail),
                feature("ulna-head", 176, 246, string.health_atlas_ulna_landmarks_head,
                    string.health_atlas_ulna_landmarks_head_detail),
                feature("ulna-styloid-process", 159, 256, string.health_atlas_ulna_landmarks_styloid,
                    string.health_atlas_ulna_landmarks_styloid_detail),
            ),
            splitCallouts = true,
        ),
    )
}
