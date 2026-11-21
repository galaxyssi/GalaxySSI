package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

internal object HealthAtlasLongBoneAndShoulderPlates {
    private const val OPENSTAX = "https://openstax.org/books/anatomy-and-physiology-2e/pages/"

    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(HealthAtlasMarker(id, x / 360f, y / 280f), title, detail)

    val all = listOf(
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_scapula_posterior_landmarks,
            owner = "scapula",
            viewLabel = string.health_atlas_scapula_landmarks_caption,
            markers = emptyList(),
            source = OPENSTAX + "8-1-the-pectoral-girdle",
            viewKey = "scapula-posterior-landmarks",
            selectorLabel = string.health_atlas_scapula_landmarks_selector,
            features = listOf(
                feature("scapula-acromion", 250, 38, string.health_atlas_scapula_landmarks_acromion,
                    string.health_atlas_scapula_landmarks_acromion_detail),
                feature("scapula-supraspinous-fossa", 136, 72, string.health_atlas_scapula_landmarks_supraspinous,
                    string.health_atlas_scapula_landmarks_supraspinous_detail),
                feature("scapula-spine", 157, 99, string.health_atlas_scapula_landmarks_spine,
                    string.health_atlas_scapula_landmarks_spine_detail),
                feature("scapula-glenoid", 251, 116, string.health_atlas_scapula_landmarks_glenoid,
                    string.health_atlas_scapula_landmarks_glenoid_detail),
                feature("scapula-infraspinous-fossa", 185, 145, string.health_atlas_scapula_landmarks_infraspinous,
                    string.health_atlas_scapula_landmarks_infraspinous_detail),
                feature("scapula-inferior-angle", 152, 243, string.health_atlas_scapula_landmarks_inferior_angle,
                    string.health_atlas_scapula_landmarks_inferior_angle_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_humerus_anterior_landmarks,
            owner = "humerus",
            viewLabel = string.health_atlas_humerus_landmarks_caption,
            markers = emptyList(),
            source = OPENSTAX + "8-2-bones-of-the-upper-limb",
            viewKey = "humerus-anterior-landmarks",
            selectorLabel = string.health_atlas_humerus_landmarks_selector,
            features = listOf(
                feature("humerus-head", 196, 44, string.health_atlas_humerus_landmarks_head,
                    string.health_atlas_humerus_landmarks_head_detail),
                feature("humerus-greater-tubercle", 148, 50, string.health_atlas_humerus_landmarks_greater_tubercle,
                    string.health_atlas_humerus_landmarks_greater_tubercle_detail),
                feature("humerus-deltoid-tuberosity", 156, 137, string.health_atlas_humerus_landmarks_deltoid,
                    string.health_atlas_humerus_landmarks_deltoid_detail),
                feature("humerus-shaft", 181, 172, string.health_atlas_humerus_landmarks_shaft,
                    string.health_atlas_humerus_landmarks_shaft_detail),
                feature("humerus-capitulum", 157, 241, string.health_atlas_humerus_landmarks_capitulum,
                    string.health_atlas_humerus_landmarks_capitulum_detail),
                feature("humerus-trochlea", 190, 245, string.health_atlas_humerus_landmarks_trochlea,
                    string.health_atlas_humerus_landmarks_trochlea_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_tibia_anterior_landmarks,
            owner = "tibia",
            viewLabel = string.health_atlas_tibia_landmarks_caption,
            markers = emptyList(),
            source = OPENSTAX + "8-4-bones-of-the-lower-limb",
            viewKey = "tibia-anterior-landmarks",
            selectorLabel = string.health_atlas_tibia_landmarks_selector,
            features = listOf(
                feature("tibia-lateral-condyle", 153, 43, string.health_atlas_tibia_landmarks_lateral_condyle,
                    string.health_atlas_tibia_landmarks_lateral_condyle_detail),
                feature("tibia-medial-condyle", 213, 43, string.health_atlas_tibia_landmarks_medial_condyle,
                    string.health_atlas_tibia_landmarks_medial_condyle_detail),
                feature("tibia-tuberosity", 185, 92, string.health_atlas_tibia_landmarks_tuberosity,
                    string.health_atlas_tibia_landmarks_tuberosity_detail),
                feature("tibia-anterior-border", 174, 162, string.health_atlas_tibia_landmarks_anterior_border,
                    string.health_atlas_tibia_landmarks_anterior_border_detail),
                feature("tibia-fibular-notch", 156, 237, string.health_atlas_tibia_landmarks_fibular_notch,
                    string.health_atlas_tibia_landmarks_fibular_notch_detail),
                feature("tibia-medial-malleolus", 208, 257, string.health_atlas_tibia_landmarks_malleolus,
                    string.health_atlas_tibia_landmarks_malleolus_detail),
            ),
            splitCallouts = true,
        ),
    )

    fun forId(id: String?) = all.firstOrNull { it.owner == id }
}
